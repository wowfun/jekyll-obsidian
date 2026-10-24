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

end
