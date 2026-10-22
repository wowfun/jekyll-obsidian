# frozen_string_literal: true
require "test_helper"
require "liquid"
require "nokogiri"

class ArchiveVisibilityTest < Minitest::Test
  def entries
    [note("index.md", "---\npublish: true\n---\n# Home"),
     note("arxiv/index.md", "---\npublish: true\ntab:\n  id: arxiv\n  layout: archive\n  topics: [source/arxiv]\n---\n# arXiv"),
     note("items/a.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-21\ntags: [source/arxiv, topics/research]\n---\n# Paper"),
     note("items/b.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-20\ntags: [source/news, topics/research]\n---\n# News")]
  end

  def test_home_scope_preserves_complete_index_article_labels_and_tab
    result = compile(*entries, locale_manifest("_locale.yml", "name: English\nhidden_tags: [topics/research]\n"),
      home: { "layout" => "archive", "hide_tab_sources" => true },
      blog: { "page_size" => 1, "timeline_granularity" => "day" }, features: { "favorites" => true })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    data = page(result, "/").data.dig("website", "theme_data")
    archive = data.fetch("archive")
    assert_equal 2, archive.fetch("total")
    assert_equal 1, archive.dig("default_view", "total")
    assert_equal ["arxiv"], archive.fetch("tab_sources")
    assert_equal ["topics/research"], archive.fetch("hidden_tags")
    assert_equal "News", data.fetch("archive_groups").first.fetch("posts").first.fetch("title")
    assert_equal 1, archive.dig("default_view", "facets", "topic", "research")
    assert_equal 2, archive.dig("facets", "topic").first.fetch("count")
    template = Liquid::Template.parse(File.read(File.expand_path("../../_includes/website/archive-facets.html", __dir__)))
    html = template.render!("page" => { "website" => { "theme_data" => data } })
    dom = Nokogiri::HTML.fragment(html)
    news = dom.at_css('button[data-archive-facet="source"][data-archive-value="news"]')
    refute news.parent.key?("hidden")
    assert_equal "1", news.at_css("span").text
    assert dom.at_css('button[data-archive-value="research"]').parent.key?("hidden")
    assert_equal [0, 1], data.fetch("timeline").first.fetch("days").map { |day| day.fetch("count") }
    assert_equal [], page(result, "/arxiv/").data.dig("website", "theme_data", "archive", "tab_sources")
    assert page(result, "/items/a/").data.dig("website", "archive_facets").any? { |facet| facet["id"] == "research" }
    plain = compile(*entries, home: { "layout" => "archive" }, blog: { "page_size" => 1 })
    assert_equal "Paper", page(plain, "/").data.dig("website", "theme_data", "archive_groups").first.fetch("posts").first.fetch("title")
    refute_equal archive["generation"], page(plain, "/").data.dig("website", "theme_data", "archive", "generation")
  end

  def test_hidden_aliases_share_a_canonical_policy_across_locales
    aliases = "tag_aliases:\n  topics/old: topics/research\n"
    [nil, { "enabled" => false }, { "enabled" => true, "locales" => %w[en zh-CN] }].each do |i18n|
      result = compile(*entries,
        locale_manifest("_locale.yml", "name: English\n#{aliases}hidden_tags: [topics/old, topics/research]\n"),
        locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n#{aliases}hidden_tags: [topics/research]\n"),
        home: { "layout" => "archive" }, i18n: i18n)
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      assert_equal ["topics/research"], page(result, "/").data.dig("website", "theme_data", "archive", "hidden_tags")
      next unless i18n && i18n["enabled"]

      assert_equal ["topics/research"], page(result, "/zh-CN/").data.dig("website", "theme_data", "archive", "hidden_tags")
    end
  end

  def test_tab_source_policy_uses_canonical_source_tags_without_inferring_topic_tab_sources
    ["topics/research", "source/missing", "source/papers"].each do |tag|
      tab = entries.fetch(1)
      input = entries.map { |entry| entry.path == tab.path ? note(tab.path, tab.bytes.sub("source/arxiv", tag)) : entry }
      result = compile(*input, locale_manifest("_locale.yml", "tag_aliases: {source/papers: source/arxiv}\n"),
        home: { "layout" => "archive", "hide_tab_sources" => true })
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      data = page(result, "/").data.dig("website", "theme_data")
      total = data.dig("archive", "default_view", "total") || data.dig("archive", "total")
      assert_equal tag == "source/papers" ? 1 : 2, total
    end
  end

  def test_single_locale_manifest_rejects_invalid_tag_policy
    ["hidden_tags: wrong", "tag_aliases: {topics/a: topics/b, topics/b: topics/c}", "[]", "hidden_tags: ["].each do |body|
      result = compile(*entries, locale_manifest("_locale.yml", body), home: { "layout" => "archive" })
      refute result.success?
      assert result.diagnostics.any? { |diagnostic| diagnostic.code == "invalid_locale_manifest" }
    end
  end

  def test_single_locale_policy_accepts_string_snapshot_kinds_like_the_indexer
    manifest = locale_manifest("_locale.yml", "hidden_tags: [topics/research]\n").with(kind: "locale_manifest")
    result = compile(*entries, manifest, home: { "layout" => "archive" })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal ["topics/research"], page(result, "/").data.dig("website", "theme_data", "archive", "hidden_tags")
  end

  def test_timeline_branches_render_with_strict_variables
    template = Liquid::Template.parse(File.read(File.expand_path("../../_includes/website/archive-timeline.html", __dir__)))
    %w[days months].each do |granularity|
      group = { "year" => "2026", "count" => 1, "days" => nil, "months" => nil,
        granularity => [0, 1].map { |count| { "count" => count, "key" => "2026-10-#{count + 1}", "label" => "Date #{count}" } } }
      html = template.render!({ "include" => { "timeline" => [group] }, "page" => { "website" => {
        "theme" => "minimal", "routes" => { "blog" => "/" }, "theme_data" => { "favorites" => false, "archive" => nil },
        "i18n" => { "messages" => { "chronology" => "Chronology" } } } } }, strict_variables: true)
      rows = Nokogiri::HTML.fragment(html).css("li")
      assert rows.first.key?("hidden")
      refute rows.last.key?("hidden")
    end
  end

  def test_tab_sources_require_an_explicit_source_facet
    result = compile(*entries, home: { "layout" => "archive", "hide_tab_sources" => true },
      blog: { "facets" => { "channel" => "source/", "topic" => "topics/" } })
    refute result.success?
    assert result.diagnostics.any? { |item| item.message.include?("source facet") }
  end

  def test_inactive_tab_source_policy_warns_without_blocking_theme_previews
    %w[minimal docs].product(%w[recent archive]).each do |theme, layout|
      [false, true].each do |enabled|
        result = compile(entries.first, theme: theme, home: { "layout" => layout, "hide_tab_sources" => enabled })
        assert result.success?, result.diagnostics.map(&:message).join("\n")
        warnings = result.diagnostics.select { |item| item.code == "ineffective_output_config" }
        if enabled && (theme != "minimal" || layout != "archive")
          assert_equal 1, warnings.length, "#{theme}/#{layout} should explain the inactive policy"
          assert_equal :warning, warnings.first.severity
          assert_includes warnings.first.message, "home.hide_tab_sources"
        else
          assert_empty warnings
        end
      end
    end
  end

  def test_unknown_policy_keys_fail_in_single_and_multi_language_builds
    [nil, { "enabled" => true, "locales" => ["en"] }].each do |i18n|
      result = compile(*entries, locale_manifest("_locale.yml", "name: English\nhidden_tag: [topics/research]\n"), i18n: i18n)
      refute result.success?
      assert result.diagnostics.any? { |item| item.message.include?("unknown locale setting") }
    end
  end

  def test_invalid_policy_does_not_suppress_other_locale_diagnostics
    result = compile(*entries, locale_manifest("_locale.yml", "name: ''\nhreflang: ''\ntag_aliases: wrong\nmessages: {unknown: bad}\n"),
      i18n: { "enabled" => true, "locales" => ["en"] })
    messages = result.diagnostics.map(&:message).join("\n")
    %w[tag_aliases name hreflang unknown].each { |key| assert_includes messages, key }
  end

  def test_default_scope_emits_one_combined_exclusion_posting
    result = compile(*entries, home: { "layout" => "archive", "hide_tab_sources" => true })
    archive = page(result, "/").data.dig("website", "theme_data", "archive")
    assert_equal "excluded.json", archive["excluded_posting"]
    prefix = archive.fetch("url").delete_suffix("manifest.json")
    posting = generated_json(result, prefix + archive.fetch("excluded_posting"))
    assert_equal [1], Base64.strict_decode64(posting.fetch("bitmap")).bytes
    plain = compile(*entries, home: { "layout" => "archive" })
    refute page(plain, "/").data.dig("website", "theme_data", "archive").key?("excluded_posting")
    refute page(plain, "/").data.dig("website", "theme_data", "archive").key?("default_view")
  end

  def test_empty_default_scope_still_keeps_index_and_restore_controls
    result = compile(*entries.reject { |entry| entry.path == "items/b.md" },
      home: { "layout" => "archive", "hide_tab_sources" => true })
    assert result.success?
    data = page(result, "/").data.dig("website", "theme_data")
    assert_equal 0, data.dig("archive", "default_view", "total")
    assert_equal 1, data.dig("archive", "total")
    assert_empty data.fetch("archive_groups")
  end

  def test_hidden_policy_must_match_across_locales_and_be_well_formed
    ["hidden_tags: [topics/a, topics/a]", "hidden_tags: wrong", "hidden_tags: ['']"].each do |policy|
      result = compile(note("index.md", "---\npublish: true\n---\n# Home"),
        locale_manifest("_locale.yml", "name: English\n#{policy}\n"),
        i18n: { "enabled" => true, "locales" => ["en"] })
      refute result.success?
      assert result.diagnostics.any? { |diagnostic| diagnostic.code == "invalid_locale_manifest" }
    end
    result = compile(note("index.md", "---\npublish: true\n---\n# Home"),
      locale_manifest("_locale.yml", "name: English\nhidden_tags: [topics/a]\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\nhidden_tags: []\n"),
      i18n: { "enabled" => true, "locales" => ["en", "zh-CN"] })
    refute result.success?
    assert result.diagnostics.any? { |diagnostic| diagnostic.message.include?("hidden_tags must share") }
  end
end
