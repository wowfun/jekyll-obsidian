# frozen_string_literal: true

require "test_helper"

class CompilationWorkTest < Minitest::Test
  def test_locale_fallback_diagnostics_are_unique_in_preparation_and_compilation
    request = JekyllObsidian::BuildRequest.new(
      snapshot: JekyllObsidian::Snapshot.new(entries: [
        note("index.md", "---\npublish: true\ngithub_markdown: https://github.com/acme/widget/blob/main/README.md\n---\nConflicting body"),
        locale_manifest("_locale.yml", "name: English\n"),
        locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n")
      ]),
      config: JekyllObsidian::BuildConfig.new(**DEFAULT_CONFIG.merge(i18n: { "enabled" => true, "locales" => %w[en zh-CN] })),
      reference_time: Time.utc(2026, 10, 24)
    )
    prepared = JekyllObsidian::VaultCompiler.prepare(request).preparation_diagnostics
    assert_equal 1, prepared.count { |item| item.code == "github_markdown_scope" }
    assert_equal 1, prepared.count { |item| item.code == "github_markdown_body_conflict" }
    result = JekyllObsidian::SiteCompilation.compile(request)
    assert_equal prepared, result.diagnostics
    request = request.with(snapshot: JekyllObsidian::Snapshot.new(entries: [
      note("index.md", "---\npublish: true\n---\n[[missing]]"),
      *request.snapshot.entries.drop(1)
    ]))
    diagnostics = JekyllObsidian::VaultCompiler.compile(request).diagnostics
    assert_equal diagnostics.uniq, diagnostics
    request = request.with(snapshot: JekyllObsidian::Snapshot.new(entries: request.snapshot.entries + [
      note("_translations/zh-CN/index.md", "[[missing]]")
    ]))
    diagnostics = JekyllObsidian::VaultCompiler.compile(request).diagnostics
    assert_equal %w[_translations/zh-CN/index.md index.md], diagnostics.select { |item| item.code == "unresolved_link" }.map(&:path)
  end

  def test_plain_hosts_do_not_populate_the_transclusion_selection_cache
    selections = 0
    serializations = 0
    trace = TracePoint.new(:call) do |event|
      selections += 1 if event.defined_class == JekyllObsidian::VaultCompiler && event.method_id == :cached_transclusion_selection
      serializations += 1 if event.method_id == :to_html && event.self.is_a?(Nokogiri::HTML5::DocumentFragment)
    end
    result = trace.enable { compile(note("index.md", "---\npublish: true\n---\n# Home"), note("other.md", "---\npublish: true\n---\n# Other")) }
    assert result.success?
    assert_equal 0, selections
    assert_equal 2, serializations
  end

  def test_external_documents_cannot_be_loaded_before_preparation
    request = JekyllObsidian::BuildRequest.new(
      snapshot: JekyllObsidian::Snapshot.new(entries: [note("index.md", "---\npublish: true\n---\n# Home")]),
      config: JekyllObsidian::BuildConfig.new(**DEFAULT_CONFIG), reference_time: Time.utc(2026, 10, 23)
    )
    [JekyllObsidian::VaultCompiler, JekyllObsidian::LocalizedCompiler].each do |type|
      error = assert_raises(ArgumentError) { type.new(request).load_external_documents({}) }
      assert_match(/prepare/, error.message)
    end
  end

  def test_authored_sentinel_urls_remain_external
    result = compile(
      note("index.md", "---\npublish: true\n---\n[user](https://obsidian.invalid/ref/0) [normal](other.md)"),
      note("other.md", "---\npublish: true\n---\n# Other")
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    links = Nokogiri::HTML5.fragment(page(result, "/").content).css("a")
    assert_equal ["https://obsidian.invalid/ref/0", "/other/"], links.map { |link| link["href"] }
    refute_includes links.last.to_html, "data-website-wikilink-token"
  end

  def test_authored_reference_tokens_cannot_capture_real_occurrences
    result = compile(
      note("index.md", <<~MD),
        ---
        publish: true
        ---
        [user](https://obsidian.invalid/ref/0)
        [normal](other.md)

        <a data-website-wikilink-token="0">fake</a>

        [[other]]

        <website-ofm-embed data-token="0">authored</website-ofm-embed>

        ![[other]]
      MD
      note("other.md", "---\npublish: true\n---\n# Other\nTarget body")
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    doc = Nokogiri::HTML5.fragment(page(result, "/").content)
    assert_equal "https://obsidian.invalid/ref/0", doc.css("a").find { |node| node.text == "user" }["href"]
    assert_equal "/other/", doc.css("a").find { |node| node.text == "normal" }["href"]
    assert_nil doc.css("a").find { |node| node.text == "fake" }["href"]
    assert_equal "/other/", doc.css("a").find { |node| node.text == "other" }["href"]
    assert_equal "authored", doc.at_css("website-ofm-embed").text
    assert_includes doc.at_css(".website-transclusion").text, "Target body"
  end

  def test_prepared_compilers_reuse_the_completed_result_without_accumulating_relations
    [nil, { "enabled" => true, "locales" => %w[en zh-CN] }].each do |i18n|
      entries = [note("index.md", "---\npublish: true\n---\n[[other]]"), note("other.md", "---\npublish: true\n---\n# Other")]
      entries += [locale_manifest("_locale.yml", "name: English\n"), locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n")] if i18n
      request = JekyllObsidian::BuildRequest.new(
        snapshot: JekyllObsidian::Snapshot.new(entries: entries),
        config: JekyllObsidian::BuildConfig.new(**DEFAULT_CONFIG.merge(i18n: i18n)), reference_time: Time.utc(2026, 10, 23)
      )
      compiler = JekyllObsidian::VaultCompiler.prepare(request)
      cached_frontmatter = compiler.instance_variable_get(:@frontmatter_cache).instance_variable_get(:@results)
      refute_empty cached_frontmatter
      first = compiler.compile
      assert first.success?, first.diagnostics.map(&:message).join("\n")
      assert_empty cached_frontmatter
      assert_same first, compiler.compile
      assert_equal(i18n ? 2 : 1, first.relations.length)
      assert_equal [1], generated_json(first, "/assets/website/graph.v1.json").fetch("edges").map { |edge| edge.fetch("count") }
      assert_raises(ArgumentError) { compiler.load_external_documents({}) }
      assert_raises(ArgumentError) { compiler.compile(tab_memberships: {}) } unless i18n
    end
  end

  def test_production_stops_expanding_hosts_after_a_fatal_budget_error
    entries = 30.times.map do |index|
      note("note-#{index}.md", "---\npublish: true\n---\n# Note #{index}\n" + (index < 29 ? "![[note-#{index + 1}]]" : ""))
    end
    hosts = []
    trace = TracePoint.new(:call) do |event|
      next unless event.defined_class == JekyllObsidian::VaultCompiler && event.method_id == :render_with_transclusions
      hosts << event.binding.local_variable_get(:note_id) if event.binding.local_variable_get(:depth).zero?
    end
    result = trace.enable { compile(*entries) }
    refute result.success?
    assert_instance_of JekyllObsidian::BuildFailure, result
    assert_equal [:diagnostics], result.to_h.keys # Failure cannot carry partial pages or generated files.
    assert_equal ["note-0.md"], hosts
    assert_equal 1, result.diagnostics.count { |item| item.code == "embed_budget_exceeded" }
  end

  def test_failed_compilation_is_also_cached
    [nil, { "enabled" => true, "locales" => %w[en zh-CN] }].each do |i18n|
      entries = [note("index.md", "---\npublish: true\n---\n![[index]]")]
      entries += [locale_manifest("_locale.yml", "name: English\n"), locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n")] if i18n
      request = JekyllObsidian::BuildRequest.new(
        snapshot: JekyllObsidian::Snapshot.new(entries: entries),
        config: JekyllObsidian::BuildConfig.new(**DEFAULT_CONFIG.merge(i18n: i18n)), reference_time: Time.utc(2026, 10, 23)
      )
      compiler = JekyllObsidian::VaultCompiler.prepare(request)
      cached_frontmatter = compiler.instance_variable_get(:@frontmatter_cache).instance_variable_get(:@results)
      refute_empty cached_frontmatter
      first = compiler.compile
      refute first.success?
      assert_empty cached_frontmatter
      assert_same first, compiler.compile
    end
  end

  def test_transclusion_selections_are_released_after_success_and_failure
    [false, true].each do |cycle|
      request = JekyllObsidian::BuildRequest.new(
        snapshot: JekyllObsidian::Snapshot.new(entries: [
          note("index.md", "---\npublish: true\n---\n![[other]]"),
          note("other.md", "---\npublish: true\n---\n" + (cycle ? "![[index]]" : "# Other"))
        ]),
        config: JekyllObsidian::BuildConfig.new(**DEFAULT_CONFIG), reference_time: Time.utc(2026, 10, 23)
      )
      compiler = JekyllObsidian::VaultCompiler.prepare(request)
      populated = false
      trace = TracePoint.new(:return) do |event|
        next unless event.self.equal?(compiler) && event.method_id == :cached_transclusion_selection

        populated ||= !compiler.instance_variable_get(:@transclusion_selection_cache).empty?
      end
      result = trace.enable { compiler.compile }
      assert_equal !cycle, result.success?
      assert populated, "the fixture must use the selection cache before checking release"
      assert_empty compiler.instance_variable_get(:@transclusion_selection_cache)
    end
  end

  def test_frontmatter_cache_is_immutable_and_keys_both_path_and_complete_content
    cache = JekyllObsidian::FrontMatter::Cache.new
    bytes = "---\npublish: true\naliases: [One]\n---\nBody"
    first = cache.parse("one.md", bytes)
    assert_same first, cache.parse("one.md", bytes.dup)
    refute_same first, cache.parse("two.md", bytes)
    refute_same first, cache.parse("one.md", bytes + " changed")
    assert_raises(FrozenError) { first.properties["aliases"] << "changed" }
    assert_raises(FrozenError) { first.body << "changed" }

    mutable_path = +"mutable.md"
    mutable_bytes = bytes.dup
    cached = cache.parse(mutable_path, mutable_bytes)
    mutable_path << ".changed"
    mutable_bytes << " changed"
    assert_same cached, cache.parse("mutable.md", bytes)
    refute_same cached, cache.parse(mutable_path, mutable_bytes)
    cache.clear
    refute_same cached, cache.parse("mutable.md", bytes)
  end

  def test_plain_notes_build_yaml_twice_and_render_html_only_once_per_note
    frontmatter = Hash.new(0)
    yaml = 0
    html = 0
    trace = TracePoint.new(:call) do |event|
      if event.defined_class == JekyllObsidian::FrontMatter.singleton_class && event.method_id == :parse
        frontmatter[[event.binding.local_variable_get(:path), event.binding.local_variable_get(:bytes)]] += 1
      elsif event.defined_class == Psych.singleton_class && event.method_id == :parse_stream
        yaml += 1
      elsif event.defined_class == Nokogiri::HTML5.singleton_class && event.method_id == :fragment
        html += 1
      end
    end
    result = trace.enable do
      compile(note("index.md", "---\npublish: true\n---\n# Home\nBody"), note("other.md", "---\npublish: true\n---\n# Other"))
    end
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal [1, 1], frontmatter.values
    assert_equal 4, yaml
    assert_equal 2, html
  end

  def test_localized_overlays_share_frontmatter_results_with_preparation_and_compilation
    counts = Hash.new(0)
    trace = TracePoint.new(:call) do |event|
      next unless event.defined_class == JekyllObsidian::FrontMatter.singleton_class && event.method_id == :parse

      counts[[event.binding.local_variable_get(:path), event.binding.local_variable_get(:bytes)]] += 1
    end
    result = trace.enable do
      compile(
        note("index.md", "---\npublish: true\n---\n# Home"),
        note("other.md", "---\npublish: true\n---\n# Other"),
        note("_translations/zh-CN/index.md", "---\ntitle: 首页\n---\n# 首页"),
        locale_manifest("_locale.yml", "name: English\n"),
        locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
        i18n: { "enabled" => true, "locales" => %w[en zh-CN] }
      )
    end
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal 4, counts.size # Two default notes, the physical translation, and its merged overlay.
    assert counts.values.all? { |count| count == 1 }, counts.inspect
  end

  def test_three_thousand_note_chain_reaches_expansion_budget_without_recursive_cycle_detection
    entries = 3_000.times.map do |index|
      body = "---\npublish: true\n---\n# Note #{index}\n"
      body += "![[note-#{index + 1}]]\n" if index < 2_999
      note("note-#{index}.md", body)
    end
    result = compile(*entries, features: { "graph" => false, "search" => false, "feed" => false })
    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "embed_budget_exceeded" }
    refute result.diagnostics.any? { |item| item.code == "embed_cycle" }
  end

  def test_cached_transclusion_selections_do_not_share_mutated_ids_between_hosts
    result = compile(
      note("a.md", "---\npublish: true\n---\n# A\n![[target#Part]]\n\n![[target#Part]]"),
      note("b.md", "---\npublish: true\n---\n# B\n![[target#Part]]"),
      note("target.md", "---\npublish: true\n---\n# Target\n## Part\n[Jump](#Part)")
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    %w[a b].each do |host|
      doc = Nokogiri::HTML5.fragment(page(result, "/#{host}/").content)
      ids = doc.css("[id]").map { |node| node["id"] }
      assert_equal ids.uniq, ids
      doc.css(".website-transclusion h2").each { |heading| assert_match(/\Aembed-#{host}md-\d+-part\z/, heading["id"]) }
      doc.css('.website-transclusion a[href^="#"]').each { |link| assert_includes ids, link["href"].delete_prefix("#") }
    end
    assert_includes page(result, "/target/").content, 'id="part"'
  end

  def test_byte_budget_includes_the_host_body_and_charges_each_cached_selection
    limit = JekyllObsidian::VaultCompiler::MAX_TRANSCLUSION_BYTES
    # A raw paragraph renders as <p>...</p> followed by one newline.
    at_limit = note("index.md", "---\npublish: true\n---\n<p>#{'x' * (limit - 8)}</p>\n")
    accepted = compile(at_limit)
    assert accepted.success?, accepted.diagnostics.map(&:message).join("\n")
    assert_equal limit, page(accepted, "/").content.bytesize
    rejected = compile(at_limit.with(bytes: at_limit.bytes.sub("</p>", "x</p>")))
    refute rejected.success?
    assert rejected.diagnostics.any? { |item| item.code == "embed_budget_exceeded" && item.message.include?("bytes") }

    leaf = note("leaf.md", "---\npublish: true\n---\n<p>#{'x' * (limit / 2)}</p>\n")
    host = note("index.md", "---\npublish: true\n---\n![[leaf]]\n\n![[leaf]]")
    rejected = compile(host, leaf)
    refute rejected.success?
    assert rejected.diagnostics.any? { |item| item.code == "embed_budget_exceeded" && item.message.include?("bytes") }
    limited = compile(host, leaf, environment: "development")
    assert limited.success?, limited.diagnostics.map(&:message).join("\n")
    assert_includes page(limited, "/").content, "website-embed--limited"
  end
end
