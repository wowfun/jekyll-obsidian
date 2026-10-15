# frozen_string_literal: true

require "test_helper"

class CustomTabTest < Minitest::Test
  I18N = { "locales" => %w[en zh-CN] }.freeze

  def test_frontmatter_accepts_strict_tab_definitions_and_memberships
    parsed = JekyllObsidian::FrontMatter.parse("favorites/index.md", <<~MARKDOWN)
      ---
      publish: true
      tab:
        id: favorites
        label: Favorites
        order: 40
        topics:
          - favorite
          - reference
      tabs:
        - reading
      ---
      # Favorites
    MARKDOWN

    assert_empty parsed.diagnostics
    assert_equal(
      {
        "id" => "favorites",
        "label" => "Favorites",
        "order" => 40,
        "topics" => %w[favorite reference]
      },
      parsed.properties.fetch("tab")
    )
    assert_equal ["reading"], parsed.properties.fetch("tabs")
  end

  def test_frontmatter_rejects_invalid_tab_shapes
    parsed = JekyllObsidian::FrontMatter.parse("favorites/index.md", <<~MARKDOWN)
      ---
      publish: true
      tab:
        id: Favorites!
        label: 7
        order: first
        topics: favorite
        layout: grid
        visible: false
      tabs:
        - favorites
        - Favorites!
        - favorites
      ---
      # Favorites
    MARKDOWN

    messages = parsed.diagnostics.select { |item| item.code == "invalid_property" }.map(&:message)
    assert_includes messages, 'unknown tab setting "visible"'
    assert_includes messages, "tab.id must be a lowercase ASCII identifier"
    assert_includes messages, "tab.label must be a non-empty string containing only output-safe Unicode characters"
    assert_includes messages, "tab.order must be an integer"
    assert_includes messages, "tab.topics must be an array of non-empty strings"
    assert_includes messages, "tab.layout must be collection or archive"
    assert_includes messages, "tabs entries must be unique lowercase ASCII identifiers"
  end

  def test_custom_tab_unions_root_explicit_and_topic_members_without_changing_builtin_active_tabs
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("favorites/index.md", <<~MARKDOWN),
        ---
        publish: true
        tab:
          id: favorites
          order: 15
          topics:
            - favorite
        ---
        # Favorites
      MARKDOWN
      note("favorites/root-member.md", "---\npublish: true\nnav_order: 2\n---\n# Root member"),
      note("external.md", "---\npublish: true\nnav_order: 1\ntabs:\n  - favorites\n---\n# External"),
      note("blog/post.md", "---\npublish: true\ndate: 2026-08-01\npinned: true\ntags:\n  - favorite\ntabs:\n  - favorites\n---\n# Post"),
      note("docs/guide.md", "---\npublish: true\ncategories:\n  - favorite\n---\n# Guide"),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    favorites = navigation_for(result, "/").find { |item| item.fetch("id") == "favorites" }
    assert_equal({ "id" => "favorites", "label" => "Favorites", "url" => "/favorites/", "order" => 15 }, favorites)
    assert_equal "favorites", active_id(result, "/favorites/")
    assert_equal "favorites", active_id(result, "/favorites/root-member/")
    assert_nil active_id(result, "/external/")
    assert_equal "blog", active_id(result, "/blog/post/")
    assert_equal "docs", active_id(result, "/docs/guide/")

    landing = page(result, "/favorites/")
    cards = landing.data.dig("website", "theme_data", "tab_members")
    assert_equal %w[blog/post.md external.md favorites/root-member.md docs/guide.md], cards.map { |card| card.fetch("id") }
    assert_equal ["favorite"], cards.first.fetch("topics").map { |topic| topic.fetch("name") }
    assert_equal "favorites", landing.data.dig("website", "theme_data", "tab_id")
  end

  def test_custom_tabs_are_available_in_docs_theme
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("collections/index.md", "---\npublish: true\ntab:\n  id: collections\n---\n# Collections"),
      note("collections/alpha.md", "---\npublish: true\n---\n# Alpha"),
      theme: "docs"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert navigation_for(result, "/").any? { |item| item.fetch("id") == "collections" }
    assert_equal "collections", active_id(result, "/collections/alpha/")
    assert_equal ["collections/alpha.md"], page(result, "/collections/").data.dig("website", "theme_data", "tab_members").map { |card| card.fetch("id") }
  end

  def test_unknown_memberships_and_invalid_root_definitions_fail_closed
    unknown = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("orphan.md", "---\npublish: true\ntabs:\n  - missing\n---\n# Orphan")
    )
    assert_diagnostic unknown, "unknown_tab", "orphan.md"

    reserved = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("blog/index.md", "---\npublish: true\ntab:\n  id: blog\n---\n# Other blog")
    )
    assert_diagnostic reserved, "reserved_tab_id", "blog/index.md"

    non_index = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("favorites.md", "---\npublish: true\ntab:\n  id: favorites\n---\n# Favorites")
    )
    assert_diagnostic non_index, "invalid_tab_root", "favorites.md"
  end

  def test_portfolio_keeps_active_ownership_when_nested_below_a_custom_root
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("work/index.md", "---\npublish: true\ntab:\n  id: work\n---\n# Work"),
      note("work/portfolio/index.md", "---\npublish: true\n---\n# Portfolio"),
      note("work/portfolio/project.md", "---\npublish: true\n---\n# Project"),
      theme: "minimal",
      navigation: { "portfolio" => { "path" => "work/portfolio" } }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal "work", active_id(result, "/work/")
    assert_equal "portfolio", active_id(result, "/work/portfolio/")
    assert_equal "portfolio", active_id(result, "/work/portfolio/project/")
    assert_includes page(result, "/work/").data.dig("website", "theme_data", "tab_member_ids"),
      "work/portfolio/project.md"
  end

  def test_localized_tab_label_is_translatable_while_membership_uses_default_topics
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("favorites/index.md", "---\npublish: true\ntab:\n  id: favorites\n  topics:\n    - favorite\n---\n# Favorites"),
      note("docs/guide.md", "---\npublish: true\ntags:\n  - favorite\n---\n# Guide"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("_translations/zh-CN/favorites/index.md", "---\npublish: true\ntab:\n  label: 收藏\n---\n# 收藏"),
      note("_translations/zh-CN/docs/guide.md", "---\npublish: true\ntags:\n  - 其他\n---\n# 指南"),
      theme: "docs",
      baseurl: "/site",
      i18n: I18N
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    translated_tab = navigation_for(result, "/zh-CN/favorites/").find { |item| item.fetch("id") == "favorites" }
    assert_equal "收藏", translated_tab.fetch("label")
    assert_equal ["docs/guide.md"], page(result, "/zh-CN/favorites/").data.dig("website", "theme_data", "tab_members").map { |card| card.fetch("id") }
    assert_equal "指南", page(result, "/zh-CN/favorites/").data.dig("website", "theme_data", "tab_members", 0, "title")
    assert_equal "/site/zh-CN/docs/guide/", page(result, "/zh-CN/favorites/").data.dig("website", "theme_data", "tab_members", 0, "url")
  end

  def test_custom_tab_cards_use_localized_tag_labels_without_changing_membership
    %w[minimal docs].each do |theme|
      result = compile(
        note("podcast/index.md", "---\npublish: true\ncontent_type: page\ntab:\n  id: podcasts\n  topics: [source/podcast]\n---\n# Podcasts"),
        note("episodes/one.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-15\ntags: [source/podcast, topics/agents, other]\n---\n# Episode"),
        locale_manifest("_locale.yml", "name: English\ntag_labels:\n  source/podcast: Podcasts\n  topics/agents: Agents\n"),
        locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\ntag_labels:\n  source/podcast: 播客\n  topics/agents: 智能体\n"),
        theme: theme, i18n: I18N.merge("enabled" => true)
      )
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      { "/podcast/" => %w[Podcasts Agents other], "/zh-CN/podcast/" => %w[播客 智能体 other] }.each do |route, names|
        cards = page(result, route).data.dig("website", "theme_data", "tab_members")
        assert_equal ["episodes/one.md"], cards.map { |card| card.fetch("id") }, theme
        assert_equal names.sort, cards.first.fetch("topics").map { |topic| topic.fetch("name") }.sort, theme
      end
    end
  end

  def test_archive_tabs_have_independent_localized_dates_facets_and_current_descriptors
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("podcast/index.md", "---\npublish: true\ncontent_type: page\ntab:\n  id: podcasts\n  layout: archive\n  topics: [source/podcast]\n---\n# Podcasts\n\nIntroduction."),
      note("mirror/index.md", "---\npublish: true\ncontent_type: page\ntab:\n  id: mirror\n  layout: archive\n  topics: [source/podcast]\n---\n# Mirror"),
      note("empty/index.md", "---\npublish: true\ncontent_type: page\ntab:\n  id: empty\n  layout: archive\n---\n# Empty"),
      note("episodes/a.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-14T18:00:00Z\ntags: [source/podcast, topics/agents]\n---\n# A newest"),
      note("episodes/z.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-14T10:00:00Z\ntags: [source/podcast, topics/tools]\n---\n# Z older"),
      note("github/outside.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-16\ntags: [source/github, topics/outside]\n---\n# Outside"),
      locale_manifest("_locale.yml", "name: English\ntag_labels:\n  topics/agents: Agents\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\ntag_labels:\n  topics/agents: 智能体\n"),
      note("_translations/zh-CN/podcast/index.md", "---\npublish: true\ntab:\n  label: 播客\n---\n# 播客"),
      theme: "minimal", baseurl: "/garden", i18n: I18N.merge("enabled" => true),
      home: { "layout" => "archive" }, features: { "favorites" => true },
      blog: { "page_size" => 1, "utc_offset" => "+08:00", "timeline_granularity" => "day", "ledger_group_by" => "day" }
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    %w[/ /zh-CN/].each do |prefix|
      landing = page(result, "#{prefix}podcast/")
      data = landing.data.fetch("website")
      archive = data.dig("theme_data", "archive")
      assert_equal "podcasts", data.fetch("active_navigation_id")
      assert_equal "blog-index", data.fetch("kind")
      assert_equal 2, archive.fetch("total")
      assert_equal 2, archive.fetch("chunks").length
      assert_equal %w[2026-10-15 2026-10-14], archive.fetch("days").keys
      assert_equal %w[agents tools], archive.dig("facets", "topic").map { |item| item.fetch("id") }.sort
      assert_equal prefix == "/" ? "Agents" : "智能体", archive.dig("facets", "topic").find { |item| item.fetch("id") == "agents" }.fetch("name")
      assert_equal "A newest", data.dig("theme_data", "archive_groups", 0, "posts", 0, "title")
      current_route = "/assets/website/#{prefix == '/' ? '' : 'i18n/zh-CN/'}archive/tabs/podcasts/current.json"
      assert_equal "/garden#{current_route}", archive.fetch("current_url")
      descriptor = generated_json(result, current_route)
      assert_equal archive.fetch("url"), descriptor.fetch("url")
      mirror = page(result, "#{prefix}mirror/").data.dig("website", "theme_data", "archive")
      assert_equal data.dig("theme_data", "tab_member_ids"), page(result, "#{prefix}mirror/").data.dig("website", "theme_data", "tab_member_ids")
      refute_equal archive.fetch("generation"), mirror.fetch("generation")
      assert_equal 3, page(result, prefix).data.dig("website", "theme_data", "archive", "total")
      assert_equal 3, page(result, "#{prefix}favorites/").data.dig("website", "theme_data", "archive", "total")
      assert_equal 0, page(result, "#{prefix}empty/").data.dig("website", "theme_data", "archive", "total")
    end
    assert_includes page(result, "/podcast/").content, "Introduction."
    assert_equal result.generated_files.map(&:route).uniq, result.generated_files.map(&:route)
  end

  def test_suppressed_tab_heading_preserves_inline_markup_and_does_not_hide_transclusions
    %w[minimal docs].each do |theme|
      result = compile(
        note("collections/index.md", "---\npublish: true\ncontent_type: page\ntab:\n  id: collections\n---\n# **Collect**ions\n"),
        note("host.md", "---\npublish: true\n---\n# Host\n\n![[collections/index]]"),
        theme: theme)
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      landing = page(result, "/collections/")
      heading = Nokogiri::HTML5.fragment(landing.content).at_css("h1.visually-hidden")
      assert_equal "Collect", heading.at_css("strong")&.text, theme
      assert_empty heading.css("a"), theme
      assert_empty landing.data.dig("website", "outline"), theme
      embedded = Nokogiri::HTML5.fragment(page(result, "/host/").content).at_css(".website-transclusion h1")
      refute_includes embedded["class"].to_s.split, "visually-hidden", theme
      assert_equal "Collect", embedded.at_css("strong")&.text, theme
    end
  end

  def test_tag_labels_are_consistent_in_articles_ledgers_and_taxonomy_without_changing_anchors
    %w[minimal docs].each do |theme|
      result = compile(
        note("posts/a.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-15\ntags: [topics/agents]\n---\n# Post"),
        locale_manifest("_locale.yml", "name: English\ntag_labels:\n  topics/agents: Agents\n"),
        locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\ntag_labels:\n  topics/agents: 智能体\n"),
        theme: theme, features: { "tags" => true }, i18n: I18N.merge("enabled" => true))
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      website = page(result, "/zh-CN/posts/a/").data.fetch("website")
      assert_equal ["智能体"], website.fetch("topic_links").map { |link| link.fetch("name") }, theme
      assert_equal ["智能体"], website.fetch("tag_links").map { |link| link.fetch("name") }, theme
      assert_equal page(result, "/posts/a/").data.dig("website", "topic_links", 0, "anchor"), website.fetch("topic_links").first.fetch("anchor"), theme
      if theme == "minimal"
        card = page(result, "/zh-CN/blog/").data.dig("website", "theme_data", "archive_groups", 0, "posts", 0)
        assert_equal "智能体", card.fetch("topics").first.fetch("name")
      else
        assert_equal "智能体", page(result, "/zh-CN/tags/").data.dig("website", "theme_data", "tag_groups", 0, "name")
      end
    end
  end

  def test_archive_tab_layout_cannot_be_overridden_by_translations_or_ignored_by_docs
    root = note("podcast/index.md", "---\npublish: true\ncontent_type: page\ntab:\n  id: podcasts\n  layout: archive\n---\n# Podcasts")
    result = compile(root, theme: "docs")
    assert_diagnostic result, "invalid_tab_layout", "podcast/index.md"
    result = compile(root,
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("_translations/zh-CN/podcast/index.md", "---\npublish: true\ntab:\n  layout: collection\n---\n# 播客"),
      theme: "minimal", i18n: I18N.merge("enabled" => true))
    assert_diagnostic result, "localized_structure_override", "_translations/zh-CN/podcast/index.md"
  end

  private

  def navigation_for(result, route)
    page(result, route).data.dig("website", "navigation")
  end

  def active_id(result, route)
    page(result, route).data.dig("website", "active_navigation_id")
  end

  def assert_diagnostic(result, code, path)
    refute result.success?
    assert result.diagnostics.any? { |item| item.code == code && item.path == path },
      result.diagnostics.map { |item| "#{item.code}: #{item.path}: #{item.message}" }.join("\n")
  end
end
