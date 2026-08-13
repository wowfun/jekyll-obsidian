# frozen_string_literal: true

require "test_helper"

class LocalizedCompilerTest < Minitest::Test
  I18N = { "locales" => %w[en zh-CN] }.freeze

  def manifests(zh_messages = "")
    [
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest(
        "_translations/zh-CN/_locale.yml",
        "name: 简体中文\nhreflang: zh-Hans\ndir: ltr\nmessages:\n  search: 搜索\n#{zh_messages}"
      )
    ]
  end

  def default_notes
    [
      note("index.md", "---\npublish: true\ntitle: Home\nupdated: 2026-08-01\n---\n# Home\n[[docs/Guide]]"),
      note("docs/Guide.md", "---\npublish: true\ncontent_type: doc\nnav_order: 1\nupdated: 2026-08-01\n---\n# Guide\n[[docs/Fallback]]"),
      note("docs/Fallback.md", "---\npublish: true\ncontent_type: doc\nnav_order: 2\nupdated: 2026-08-01\n---\n# Default only")
    ]
  end

  def translations
    [
      note("_translations/zh-CN/index.md", "---\npublish: true\ntitle: 首页\n---\n# 首页\n[[docs/Guide]]"),
      note("_translations/zh-CN/docs/Guide.md", "---\npublish: true\ntitle: 指南\n---\n# 指南\n[[docs/Fallback]]")
    ]
  end

  def test_missing_translations_are_nonfatal_and_locale_outputs_remain_partitioned
    result = compile(
      *default_notes,
      *manifests,
      *translations,
      theme: "docs",
      i18n: I18N,
      content: { "directories" => { "doc" => ["docs"], "post" => [] } }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal %w[/ /404.html /docs/Fallback/ /docs/Guide/ /zh-CN/ /zh-CN/404.html /zh-CN/docs/Fallback/ /zh-CN/docs/Guide/], result.pages.map(&:route)

    translated = page(result, "/zh-CN/docs/Guide/")
    assert_equal "指南", translated.data.fetch("title")
    assert_equal "zh-CN", translated.data.dig("website", "i18n", "locale")
    assert_equal "zh-CN", translated.data.dig("website", "i18n", "content_lang")
    assert_includes translated.content, 'href="/zh-CN/docs/Fallback/"'
    assert_equal "/assets/website/i18n/zh-CN/search.v1.json", translated.data.dig("website", "resources", "search")
    translated_tree = translated.data.dig("website", "theme_data", "docs_tree")
    assert_equal %w[docs/Guide.md docs/Fallback.md], translated_tree.map { |node| node.fetch("id") }
    assert_equal %w[docs/Fallback.md docs/Guide.md index.md], translated.data.dig("website", "local_graph", "nodes").map { |node| node.fetch("id") }
    assert translated.data.dig("website", "local_graph", "nodes").all? { |node| node.fetch("url").start_with?("/zh-CN/") }

    fallback = page(result, "/zh-CN/docs/Fallback/")
    assert_equal true, fallback.data.dig("website", "i18n", "fallback")
    assert_equal "en", fallback.data.dig("website", "i18n", "content_lang")
    assert_equal "noindex", fallback.data.dig("website", "robots")
    assert_equal "https://example.test/docs/Fallback/", fallback.data.dig("website", "canonical_url")
    assert_empty fallback.data.dig("website", "alternates")
    assert_equal "docs/Fallback.md", URI.decode_uri_component(fallback.data.dig("website", "source_links", "source").split("/blob/main/vault/").last)

    source = translated.data.dig("website", "source_links", "source")
    assert_includes URI.decode_uri_component(source), "vault/_translations/zh-CN/docs/Guide.md"
    assert_equal %w[/docs/Fallback.md /docs/Guide.md /index.md /zh-CN/docs/Fallback.md /zh-CN/docs/Guide.md /zh-CN/index.md],
      result.generated_files.select { |file| file.media_type == "text/markdown" }.map(&:route)
    artifacts = result.generated_files.reject { |file| file.media_type == "text/markdown" }
    assert_equal %w[/assets/website/catalog.v1.json /assets/website/graph.v1.json /assets/website/i18n/zh-CN/catalog.v1.json /assets/website/i18n/zh-CN/graph.v1.json /assets/website/i18n/zh-CN/search.v1.json /assets/website/search.v1.json /sitemap.xml], artifacts.map(&:route)
    assert_equal "# 指南\n[[docs/Fallback]]\n", result.generated_files.find { |file| file.route == "/zh-CN/docs/Guide.md" }.content
    assert_equal "# Default only\n", result.generated_files.find { |file| file.route == "/zh-CN/docs/Fallback.md" }.content
    assert_equal "/zh-CN/docs/Guide.md", translated.data.dig("website", "markdown_url")
    localized_graph = generated_json(result, "/assets/website/i18n/zh-CN/graph.v1.json")
    assert localized_graph.fetch("nodes").all? { |node| node.fetch("url").start_with?("/zh-CN/") }
    assert_equal %w[en zh-CN], result.site_data.dig("website_i18n", "locales").map { |locale| locale.fetch("code") }
  end

  def test_translation_tree_is_reserved_when_i18n_is_disabled
    result = compile(*default_notes, *manifests, *translations, theme: "docs", i18n: nil)

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    refute result.pages.any? { |output| output.route.start_with?("/_translations/") }
    refute result.notes.any? { |output| output.id.start_with?("_translations/") }
    assert_nil page(result, "/zh-CN/")
  end

  def test_minimal_authored_home_uses_the_same_translation_fallback_contract_as_notes
    result = compile(
      note("index.md", "---\npublish: true\ntitle: Home\nupdated: 2026-08-01\n---\n# Home\nDefault-language copy."),
      *manifests,
      theme: "minimal",
      i18n: I18N.merge("enabled" => true)
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    fallback = page(result, "/zh-CN/")
    assert_equal true, fallback.data.dig("website", "i18n", "fallback")
    assert_equal "en", fallback.data.dig("website", "i18n", "content_lang")
    assert_equal "noindex", fallback.data.dig("website", "robots")
    assert_equal "https://example.test/", fallback.data.dig("website", "canonical_url")
    assert_empty fallback.data.dig("website", "alternates")
    assert_includes fallback.data.dig("website", "source_links", "source"), "vault/index.md"
    refute_includes result.generated_files.find { |file| file.route == "/sitemap.xml" }.content,
      "https://example.test/zh-CN/"
  end

  def test_minimal_blog_heading_localizes_unless_configuration_supplies_a_label
    entries = [
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ndate: 2026-08-01\n---\n# Post"),
      *manifests("  blog: 博客\n")
    ]
    localized = compile(*entries, theme: "minimal", i18n: I18N.merge("enabled" => true))
    assert localized.success?, localized.diagnostics.map(&:message).join("\n")
    assert_equal "Blog", page(localized, "/blog/").data.fetch("title")
    assert_equal "博客", page(localized, "/zh-CN/blog/").data.fetch("title")

    configured = compile(
      *entries,
      theme: "minimal",
      i18n: I18N.merge("enabled" => true),
      navigation: { "blog" => { "label" => "Writing" } }
    )
    assert configured.success?, configured.diagnostics.map(&:message).join("\n")
    assert_equal "Writing", page(configured, "/blog/").data.fetch("title")
    assert_equal "Writing", page(configured, "/zh-CN/blog/").data.fetch("title")
  end

  def test_minimal_portfolio_localizes_the_generated_index_and_preserves_its_hidden_route
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("work/alpha.md", "---\npublish: true\n---\n# Alpha"),
      *manifests("  portfolio: 作品集\n  projects: 项目\n"),
      note("_translations/zh-CN/work/alpha.md", "---\npublish: true\ntitle: 甲\n---\n# 甲"),
      theme: "minimal",
      i18n: I18N.merge("enabled" => true),
      baseurl: "/manual",
      navigation: { "portfolio" => { "path" => "work", "visible" => false } },
      content: {
        "default_type" => "doc",
        "directories" => { "doc" => ["work"], "post" => [] }
      }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    default_index = page(result, "/work/")
    localized_index = page(result, "/zh-CN/work/")
    assert_equal "portfolio-index", default_index.data.dig("website", "kind")
    assert_equal "Portfolio", default_index.data.fetch("title")
    assert_equal "作品集", localized_index.data.fetch("title")
    assert_equal "/manual/zh-CN/work/", localized_index.data.dig("website", "routes", "portfolio")
    assert_equal "项目", localized_index.data.dig("website", "i18n", "messages", "projects")
    assert_equal "page", page(result, "/zh-CN/work/alpha/").data.dig("website", "content_type")
  end

  def test_minimal_portfolio_uses_each_locales_title_as_the_stable_ordering_tiebreaker
    result = compile(
      note("portfolio/a.md", "---\npublish: true\ntitle: Alpha\n---\n# Alpha"),
      note("portfolio/b.md", "---\npublish: true\ntitle: Beta\n---\n# Beta"),
      *manifests,
      note("_translations/zh-CN/portfolio/a.md", "---\npublish: true\ntitle: Zulu\n---\n# Zulu"),
      note("_translations/zh-CN/portfolio/b.md", "---\npublish: true\ntitle: Alpha\n---\n# Alpha"),
      theme: "minimal",
      i18n: I18N.merge("enabled" => true)
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal %w[portfolio/a.md portfolio/b.md], page(result, "/portfolio/").data.dig(
      "website", "theme_data", "portfolio_projects"
    ).map { |project| project.fetch("id") }
    assert_equal %w[portfolio/b.md portfolio/a.md], page(result, "/zh-CN/portfolio/").data.dig(
      "website", "theme_data", "portfolio_projects"
    ).map { |project| project.fetch("id") }
  end

  def test_minimal_portfolio_detail_topics_follow_physical_translations_and_fallbacks
    result = compile(
      note(
        "portfolio/translated.md",
        "---\npublish: true\ncategories: [Rust, TypeScript]\n---\n# Translated project"
      ),
      note(
        "portfolio/fallback.md",
        "---\npublish: true\ncategories: [Ruby]\n---\n# Fallback project"
      ),
      *manifests,
      note(
        "_translations/zh-CN/portfolio/translated.md",
        "---\npublish: true\ntitle: 已翻译项目\n---\n# 已翻译项目"
      ),
      theme: "minimal",
      i18n: I18N.merge("enabled" => true)
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal %w[Rust TypeScript], page(result, "/zh-CN/portfolio/translated/").data.dig(
      "website", "theme_data", "portfolio_topics"
    ).map { |topic| topic.fetch("name") }

    fallback = page(result, "/zh-CN/portfolio/fallback/")
    assert_equal true, fallback.data.dig("website", "i18n", "fallback")
    assert_equal ["Ruby"], fallback.data.dig(
      "website", "theme_data", "portfolio_topics"
    ).map { |topic| topic.fetch("name") }
  end

  def test_hidden_indexless_portfolio_redirect_uses_its_localized_route_and_title
    result = compile(
      note("work/alpha.md", "---\npublish: true\n---\n# Alpha"),
      *manifests("  portfolio: 作品集\n"),
      theme: "minimal",
      i18n: I18N.merge("enabled" => true),
      baseurl: "/manual",
      navigation: { "portfolio" => { "path" => "work", "visible" => false } }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    default_redirect = page(result, "/")
    localized_redirect = page(result, "/zh-CN/")
    assert_equal "redirect", default_redirect.data.dig("website", "kind")
    assert_equal "Portfolio", default_redirect.data.fetch("title")
    assert_equal "portfolio", localized_redirect.data.dig("website", "redirect_navigation_id")
    assert_equal "作品集", localized_redirect.data.fetch("title")
    assert_equal "/manual/zh-CN/work/", localized_redirect.data.dig("website", "redirect_url")
    assert_equal "/manual/zh-CN/work/", localized_redirect.data.dig("website", "routes", "portfolio")
  end

  def test_portfolio_translation_keeps_builtin_active_while_joining_a_custom_tab
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note(
        "featured/index.md",
        "---\npublish: true\ntab:\n  id: featured\n  label: Featured\n---\n# Featured"
      ),
      note(
        "work/alpha.md",
        "---\npublish: true\ntabs:\n  - featured\n---\n# Alpha"
      ),
      *manifests,
      note(
        "_translations/zh-CN/featured/index.md",
        "---\npublish: true\ntab:\n  label: 特选\n---\n# 特选"
      ),
      note(
        "_translations/zh-CN/work/alpha.md",
        "---\npublish: true\ntitle: 甲\n---\n# 甲"
      ),
      theme: "minimal",
      i18n: I18N.merge("enabled" => true),
      navigation: { "portfolio" => { "path" => "work" } },
      content: {
        "default_type" => "page",
        "directories" => { "doc" => ["work"], "post" => [] }
      }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    translated = page(result, "/zh-CN/work/alpha/")
    assert_equal "page", translated.data.dig("website", "content_type")
    assert_equal "portfolio", translated.data.dig("website", "active_navigation_id")
    item = translated.data.dig("website", "navigation").find { |entry| entry.fetch("id") == "featured" }
    assert_equal "特选", item.fetch("label")
    cards = page(result, "/zh-CN/featured/").data.dig("website", "theme_data", "tab_members")
    assert_equal ["甲"], cards.map { |card| card.fetch("title") }
  end

  def test_real_translations_have_reciprocal_hreflang_and_fallbacks_are_omitted_from_sitemap
    result = compile(*default_notes, *manifests, *translations, theme: "docs", i18n: I18N)
    assert result.success?, result.diagnostics.map(&:message).join("\n")

    default = page(result, "/docs/Guide/")
    translated = page(result, "/zh-CN/docs/Guide/")
    assert_equal %w[en zh-Hans x-default], default.data.dig("website", "alternates").map { |item| item.fetch("hreflang") }
    assert_equal default.data.dig("website", "alternates"), translated.data.dig("website", "alternates")
    assert_equal "https://example.test/zh-CN/docs/Guide/", translated.data.dig("website", "canonical_url")

    sitemap = result.generated_files.find { |file| file.route == "/sitemap.xml" }.content
    assert_includes sitemap, "https://example.test/zh-CN/docs/Guide/"
    assert_includes sitemap, 'hreflang="zh-Hans"'
    refute_includes sitemap, "https://example.test/zh-CN/docs/Fallback/"
  end

  def test_baseurl_is_applied_once_to_locale_pages_links_and_resources
    result = compile(*default_notes, *manifests, *translations, theme: "docs", i18n: I18N, baseurl: "/manual")
    assert result.success?, result.diagnostics.map(&:message).join("\n")

    translated = page(result, "/zh-CN/docs/Guide/")
    assert_equal "/manual/zh-CN/docs/Guide/", translated.data.dig("website", "href")
    assert_includes translated.content, 'href="/manual/zh-CN/docs/Fallback/"'
    assert_equal "/manual/assets/website/i18n/zh-CN/search.v1.json", translated.data.dig("website", "resources", "search")
    assert_equal "/manual/zh-CN/docs/Guide.md", translated.data.dig("website", "markdown_url")
    refute_includes translated.content, "/manual/manual/"
  end

  def test_indexless_locale_roots_redirect_to_each_locales_first_ordered_page
    result = compile(
      note("docs/Later.md", "---\npublish: true\ncontent_type: doc\nnav_order: 20\n---\n# Later"),
      note("docs/Start.md", "---\npublish: true\ncontent_type: doc\nnav_order: 10\n---\n# Start"),
      *manifests,
      note("_translations/zh-CN/docs/Start.md", "---\npublish: true\ntitle: 开始\n---\n# 开始"),
      theme: "docs",
      i18n: I18N,
      baseurl: "/manual",
      content: { "directories" => { "doc" => ["docs"], "post" => [] } }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    default_redirect = page(result, "/")
    translated_redirect = page(result, "/zh-CN/")
    assert_equal "/manual/docs/Start/", default_redirect.data.dig("website", "redirect_url")
    assert_equal "https://example.test/manual/docs/Start/", default_redirect.data.dig("website", "canonical_url")
    assert_equal "/manual/zh-CN/docs/Start/", translated_redirect.data.dig("website", "redirect_url")
    assert_equal "https://example.test/manual/zh-CN/docs/Start/", translated_redirect.data.dig("website", "canonical_url")
    assert_equal "/manual/zh-CN/docs/Start/", page(result, "/zh-CN/docs/Later/").data.dig("website", "routes", "home")

    sitemap = result.generated_files.find { |file| file.route == "/sitemap.xml" }.content
    refute_includes sitemap, "<loc>https://example.test/manual/</loc>"
    refute_includes sitemap, "<loc>https://example.test/manual/zh-CN/</loc>"
    assert_includes sitemap, "https://example.test/manual/zh-CN/docs/Start/"
  end

  def test_minimal_blog_topics_keep_the_localized_baseurl_filter_route
    result = compile(
      note(
        "blog/post.md",
        "---\npublish: true\ncontent_type: post\ndate: 2026-08-01\ntags: [release]\ncategories: [Architecture]\n---\n# Post"
      ),
      *manifests,
      note(
        "_translations/zh-CN/blog/post.md",
        "---\npublish: true\ntitle: 文章\ncategories: [架构]\n---\n# 文章"
      ),
      theme: "minimal",
      i18n: I18N.merge("enabled" => true),
      baseurl: "/manual"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    translated = page(result, "/zh-CN/blog/post/").data.fetch("website")
    assert_equal "/manual/zh-CN/blog/", translated.dig("routes", "blog")
    assert_equal ["release", "架构"], translated.fetch("topic_links").map { |topic| topic.fetch("name") }
    assert_equal ["release", "架构"], page(result, "/zh-CN/blog/").data.dig(
      "website", "theme_data", "archive_groups", 0, "posts", 0, "topics"
    ).map { |topic| topic.fetch("name") }
  end

  def test_minimal_blog_topic_metadata_keeps_ui_and_fallback_content_languages_distinct
    result = compile(
      note(
        "blog/post.md",
        "---\npublish: true\ncontent_type: post\ndate: 2026-08-01\ncategories: [Architecture]\n---\n# Post"
      ),
      *manifests("  topics: 主题\n"),
      theme: "minimal",
      i18n: I18N.merge("enabled" => true)
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    fallback = page(result, "/zh-CN/blog/post/").data.fetch("website")
    assert_equal true, fallback.dig("i18n", "fallback")
    assert_equal "zh-CN", fallback.dig("i18n", "locale")
    assert_equal "ltr", fallback.dig("i18n", "dir")
    assert_equal "en", fallback.dig("i18n", "content_lang")
    assert_equal "ltr", fallback.dig("i18n", "content_dir")
    assert_equal "主题", fallback.dig("i18n", "messages", "topics")
    assert_equal ["Architecture"], fallback.fetch("topic_links").map { |topic| topic.fetch("name") }
  end

  def test_locale_manifests_are_closed_and_i18n_defaults_are_theme_specific
    unknown_message = manifests("  invented: nope\n")
    result = compile(*default_notes, *unknown_message, theme: "docs", i18n: I18N)
    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "invalid_locale_message" }

    minimal = compile(*default_notes, *manifests, theme: "minimal", i18n: I18N)
    assert minimal.success?, minimal.diagnostics.map(&:message).join("\n")
    assert_nil page(minimal, "/zh-CN/")

    localized = compile(
      *default_notes,
      *manifests,
      *translations,
      theme: "minimal",
      i18n: I18N.merge("enabled" => true)
    )
    assert localized.success?, localized.diagnostics.map(&:message).join("\n")
    assert_equal "指南", page(localized, "/zh-CN/docs/Guide/").data.fetch("title")

    disabled_docs = compile(*default_notes, *manifests, *translations, theme: "docs", i18n: { "enabled" => false })
    assert disabled_docs.success?, disabled_docs.diagnostics.map(&:message).join("\n")
    assert_nil page(disabled_docs, "/zh-CN/")

    invalid_enabled = compile(*default_notes, theme: "minimal", i18n: { "enabled" => "true" })
    refute invalid_enabled.success?
    assert invalid_enabled.diagnostics.any? { |item| item.code == "invalid_i18n_config" && item.message.include?("YAML boolean") }

    missing_default = compile(*default_notes, *manifests, theme: "docs", lang: "fr", i18n: I18N)
    refute missing_default.success?
    assert missing_default.diagnostics.any? { |item| item.code == "missing_default_locale" }

    duplicate = compile(*default_notes, locale_manifest("_locale.yml", "name: English\n"), theme: "docs", i18n: { "locales" => %w[en EN] })
    refute duplicate.success?
    assert duplicate.diagnostics.any? { |item| item.code == "duplicate_locale" }

    reserved = compile(*default_notes, locale_manifest("_locale.yml", "name: English\n"), theme: "docs", i18n: { "locales" => %w[en assets] })
    refute reserved.success?
    assert reserved.diagnostics.any? { |item| item.code == "reserved_locale" }
  end

  def test_manifest_direction_controls_page_direction_and_rejects_invalid_values
    rtl_manifests = [
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\ndir: rtl\n")
    ]
    result = compile(*default_notes, *rtl_manifests, *translations, theme: "docs", i18n: I18N)
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal "rtl", page(result, "/zh-CN/docs/Guide/").data.dig("website", "i18n", "dir")

    invalid = [
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\ndir: sideways\n")
    ]
    failed = compile(*default_notes, *invalid, theme: "docs", i18n: I18N)
    refute failed.success?
    assert failed.diagnostics.any? { |item| item.code == "invalid_locale_manifest" }
  end

  def test_translations_cannot_create_or_change_structure_or_add_private_assets
    structure = note("_translations/zh-CN/docs/Guide.md", "---\npublish: true\npermalink: /different/\npinned: true\n---\n# 指南")
    orphan = note("_translations/zh-CN/docs/Orphan.md", "---\npublish: true\n---\n# 孤儿")
    asset = attachment("_translations/zh-CN/image.png")
    result = compile(*default_notes, *manifests, structure, orphan, asset, theme: "docs", i18n: I18N)

    refute result.success?
    codes = result.diagnostics.map(&:code)
    assert_includes codes, "localized_structure_override"
    assert result.diagnostics.any? { |item| item.code == "localized_structure_override" && item.message.include?("pinned") }
    assert_includes codes, "orphan_translation"
    assert_includes codes, "localized_asset_unsupported"
  end

  def test_translation_inherits_publication_and_paths_must_be_normalized
    inherited = note("_translations/zh-CN/docs/Guide.md", "---\ntitle: 指南\n---\n# 指南")
    translated = compile(*default_notes, *manifests, inherited, theme: "docs", i18n: I18N)

    assert translated.success?, translated.diagnostics.map(&:message).join("\n")
    refute page(translated, "/zh-CN/docs/Guide/").data.dig("website", "i18n", "fallback")
    assert_equal "指南", page(translated, "/zh-CN/docs/Guide/").data.fetch("title")

    disabled = note("_translations/zh-CN/docs/Guide.md", "---\npublish: false\n---\n# 不发布")
    fallback = compile(*default_notes, *manifests, disabled, theme: "docs", i18n: I18N)

    assert fallback.success?, fallback.diagnostics.map(&:message).join("\n")
    assert_equal true, page(fallback, "/zh-CN/docs/Guide/").data.dig("website", "i18n", "fallback")

    invalid_path = note("_translations/zh-CN/docs/../Fallback.md", "---\npublish: true\n---\n# 错误")
    result = compile(*default_notes, *manifests, invalid_path, theme: "docs", i18n: I18N)

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "invalid_translation_path" }
  end

  def test_translations_inherit_and_can_override_custom_property_links_and_related
    result = compile(
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        project: "[[docs/Target]]"
        related:
          - "[[docs/Target]]"
        ---
        # Home
      MARKDOWN
      note("docs/Target.md", "---\npublish: true\ncontent_type: doc\n---\n# Target"),
      note("docs/Other.md", "---\npublish: true\ncontent_type: doc\n---\n# Other"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("_translations/zh-CN/index.md", <<~MARKDOWN),
        ---
        title: 首页
        project: "[[docs/Other]]"
        related:
          - "[[docs/Other|另读]]"
        ---
        # 首页
      MARKDOWN
      note("_translations/zh-CN/docs/Other.md", "---\ntitle: 其他\n---\n# 其他"),
      theme: "docs",
      i18n: I18N
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal ["docs/Target.md"], page(result, "/").data.dig("website", "related_articles").map { |item| item.fetch("id") }
    translated_related = page(result, "/zh-CN/").data.dig("website", "related_articles")
    assert_equal [{ "id" => "docs/Other.md", "title" => "另读", "url" => "/zh-CN/docs/Other/" }],
      translated_related.map { |item| item.slice("id", "title", "url") }
    assert_equal %w[index.md index.md],
      result.relations.select { |relation| relation.target_id == "docs/Target.md" }.map(&:source_id)
    assert_equal ["zh-CN:index.md", "zh-CN:index.md"],
      result.relations.select { |relation| relation.target_id == "zh-CN:docs/Other.md" }.map(&:source_id)
  end

  def test_translated_property_link_diagnostics_point_to_the_physical_translation
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("_translations/zh-CN/index.md", <<~MARKDOWN),
        ---
        title: 首页
        project: "[[docs/missing-custom]]"
        related:
          - "[[docs/missing-related]]"
        ---
        # 首页
      MARKDOWN
      theme: "docs",
      i18n: I18N
    )

    refute result.success?
    custom = result.diagnostics.find { |item| item.code == "unresolved_property_link" }
    related = result.diagnostics.find { |item| item.code == "unresolved_related" }
    refute_nil custom
    refute_nil related
    assert_equal "_translations/zh-CN/index.md", custom.path
    assert_equal 3, custom.span.start_line
    assert_equal "_translations/zh-CN/index.md", related.path
    assert_equal 5, related.span.start_line
  end

  def test_translated_body_diagnostics_do_not_collide_with_inherited_property_links
    result = compile(
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        project: "[[dup]]"
        ---
        # Home
      MARKDOWN
      note("a/dup.md", "---\npublish: true\n---\n# First duplicate"),
      note("b/dup.md", "---\npublish: true\n---\n# Second duplicate"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("_translations/zh-CN/index.md", <<~MARKDOWN),
        ---
        title: 首页
        ---
        # 首页

        xxxxxxxxx[[dup|xx]]
      MARKDOWN
      theme: "docs",
      i18n: I18N,
      environment: "development"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    ambiguous = result.diagnostics.select { |item| item.code == "ambiguous_target" }
    assert_equal 3, ambiguous.length
    assert_equal 2, ambiguous.count { |item| item.path == "index.md" && item.property == "project" }
    translated_body = ambiguous.find do |item|
      item.path == "_translations/zh-CN/index.md" && item.property.nil?
    end
    refute_nil translated_body
    assert_equal 3, translated_body.span.start_line
  end

  def test_locale_routes_are_checked_against_default_routes
    collision = note("collision.md", "---\npublish: true\npermalink: /zh-CN/docs/Guide/\n---\n# Collision")
    result = compile(*default_notes, collision, *manifests, *translations, theme: "docs", i18n: I18N)

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "route_collision" }
  end

  def test_translation_overlay_inherits_default_git_publication_date_without_synthesizing_updated
    first_committed_at = "2025-02-03T04:05:06Z"
    translated_first_committed_at = "2026-06-07T08:09:10Z"
    notes = [
      note("index.md", "---\npublish: true\n---\n# Home"),
      note(
        "posts/git-dated.md",
        "---\npublish: true\ncontent_type: post\n---\n# Git dated",
        first_committed_at: first_committed_at
      )
    ]
    localized = note(
      "_translations/zh-CN/posts/git-dated.md",
      "---\npublish: true\n---\n# Git 日期",
      first_committed_at: translated_first_committed_at
    )

    result = compile(
      *notes,
      *manifests,
      localized,
      theme: "minimal",
      i18n: I18N.merge("enabled" => true),
      content: { "directories" => { "doc" => [], "post" => ["posts"] } }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    translated = page(result, "/zh-CN/posts/git-dated/")
    assert_equal first_committed_at, translated.data.dig("website", "published_at")
    assert_equal first_committed_at, translated.data.dig("website", "created")
    assert_nil translated.data.dig("website", "updated")
  end

  def test_locale_routes_reject_file_and_directory_ancestor_conflicts
    collision = note(
      "localized-feed.md",
      "---\npublish: true\ncontent_type: post\ndate: 2026-08-01\npermalink: /zh-CN/feed.xml/\n---\n# Collision"
    )
    result = compile(
      *default_notes,
      collision,
      *manifests,
      theme: "minimal",
      i18n: I18N.merge("enabled" => true)
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "route_collision" }
  end

  def test_localization_only_rewrites_schema_url_fields
    notes = [
      note(
        "index.md",
        "---\npublish: true\ntitle: /literal-title\nsubtitle: /literal-subtitle\ndescription: /literal-description\ntags:\n  - /literal-tag\nauthor:\n  - /literal-author\ncategories:\n  - /literal-category\n---\n# Home\n/literal-body"
      )
    ]
    localized = note(
      "_translations/zh-CN/index.md",
      "---\npublish: true\ntitle: /translated-title\nsubtitle: /translated-subtitle\ndescription: /translated-description\ntags:\n  - /translated-tag\nauthor:\n  - /translated-author\ncategories:\n  - /translated-category\n---\n# 首页\n/translated-body"
    )
    result = compile(*notes, *manifests, localized, theme: "docs", i18n: I18N)

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    translated = page(result, "/zh-CN/")
    assert_equal "/translated-title", translated.data.fetch("title")
    assert_equal "/translated-description", translated.data.fetch("description")
    assert_equal "/translated-subtitle", translated.data.dig("website", "subtitle")
    assert_equal ["/translated-tag"], translated.data.dig("website", "tags")
    assert_equal [
      { "kind" => "author", "name" => "/translated-author" }
    ], translated.data.dig("website", "authors")
    refute translated.data.dig("website").key?("author")
    assert_equal ["/translated-category"], translated.data.dig("website", "categories")
    assert_includes translated.content, "/translated-body"

    search_entry = generated_json(result, "/assets/website/i18n/zh-CN/search.v1.json").fetch("documents").first
    assert_equal "/translated-title", search_entry.fetch("title")
    assert_equal ["/translated-tag"], search_entry.fetch("tags")
    assert_equal "/zh-CN/", search_entry.fetch("url")
  end

  def test_fallback_content_uses_default_locale_direction
    locale_manifests = [
      locale_manifest("_locale.yml", "name: English\ndir: ltr\n"),
      locale_manifest("_translations/ar/_locale.yml", "name: العربية\ndir: rtl\n")
    ]
    result = compile(
      *default_notes,
      *locale_manifests,
      theme: "docs",
      i18n: { "locales" => %w[en ar] }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    fallback = page(result, "/ar/docs/Guide/")
    assert_equal "rtl", fallback.data.dig("website", "i18n", "dir")
    assert_equal "en", fallback.data.dig("website", "i18n", "content_lang")
    assert_equal "ltr", fallback.data.dig("website", "i18n", "content_dir")
  end

  def test_translated_embeds_resolve_locale_first_while_attachments_remain_shared
    notes = [
      note("index.md", "---\npublish: true\n---\n# Home\n![[docs/Target]]\n![[shared.png]]"),
      note("docs/Target.md", "---\npublish: true\n---\n# Default target")
    ]
    localized = [
      note("_translations/zh-CN/index.md", "---\npublish: true\n---\n# 首页\n![[docs/Target]]\n![[shared.png]]"),
      note("_translations/zh-CN/docs/Target.md", "---\npublish: true\n---\n# 中文目标")
    ]
    result = compile(
      *notes,
      attachment("shared.png", "png", media_type: "image/png"),
      *manifests("  embedded_from: 来自 {title}\n"),
      *localized,
      theme: "docs",
      i18n: I18N
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    translated = page(result, "/zh-CN/")
    assert_includes translated.content, "中文目标"
    assert_includes translated.content, 'lang="zh-CN">来自 中文目标'
    assert_includes translated.content, 'src="/assets/vault/shared.png"'
    assert_equal ["/assets/vault/shared.png"], result.copied_assets.map(&:route)
  end

  def test_localized_compile_is_deterministic_across_snapshot_order
    entries = [*default_notes, *manifests, *translations]
    first = compile(*entries, theme: "docs", i18n: I18N)
    second = compile(*entries.reverse, theme: "docs", i18n: I18N)

    assert first.success?, first.diagnostics.map(&:message).join("\n")
    assert second.success?, second.diagnostics.map(&:message).join("\n")
    assert_equal first.pages, second.pages
    assert_equal first.generated_files, second.generated_files
    assert_equal first.copied_assets, second.copied_assets
    assert_equal first.notes, second.notes
    assert_equal first.relations, second.relations
    assert_equal first.site_data, second.site_data
  end
end
