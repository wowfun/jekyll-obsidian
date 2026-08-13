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
