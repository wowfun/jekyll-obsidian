# frozen_string_literal: true

require "test_helper"

class NavigationConfigurationTest < Minitest::Test
  I18N = { "locales" => %w[en zh-CN] }.freeze

  def test_frontmatter_tab_is_an_explicit_strict_mapping
    parsed = JekyllObsidian::FrontMatter.parse("about/index.md", <<~MARKDOWN)
      ---
      publish: true
      tab:
        id: about
        label: About us
        order: 15
        topics:
          - profile
      ---
      # About
    MARKDOWN

    assert_empty parsed.diagnostics
    assert_equal(
      { "id" => "about", "label" => "About us", "order" => 15, "topics" => ["profile"] },
      parsed.properties.fetch("tab")
    )

    opted_in = JekyllObsidian::FrontMatter.parse(
      "projects/index.md",
      "---\npublish: true\ntab: {}\n---\n# Projects"
    )
    assert opted_in.properties.key?("tab")
    assert_equal({}, opted_in.properties.fetch("tab"))
  end

  def test_frontmatter_tab_rejects_unknown_keys_and_invalid_types
    parsed = JekyllObsidian::FrontMatter.parse("about/index.md", <<~MARKDOWN)
      ---
      publish: true
      tab:
        id: About!
        label: 7
        order: first
        topics: profile
        href: /elsewhere/
      ---
      # About
    MARKDOWN

    messages = parsed.diagnostics.select { |item| item.code == "invalid_property" }.map(&:message)
    assert_includes messages, 'unknown tab setting "href"'
    assert_includes messages, "tab.id must be a lowercase ASCII identifier"
    assert_includes messages, "tab.label must be a non-empty string containing only output-safe Unicode characters"
    assert_includes messages, "tab.order must be an integer"
    assert_includes messages, "tab.topics must be an array of non-empty strings"

    scalar = JekyllObsidian::FrontMatter.parse(
      "about/index.md",
      "---\npublish: true\ntab: About\n---\n# About"
    )
    assert scalar.diagnostics.any? { |item| item.message == "tab must be a YAML mapping with string keys" }
  end

  def test_site_navigation_defaults_are_fully_normalized_and_immutable
    navigation, diagnostics = normalized_navigation(nil)

    assert_empty diagnostics
    assert_equal(
      {
        "home" => { "order" => 0, "visible" => true },
        "blog" => { "order" => 10, "visible" => true },
        "docs" => { "order" => 20, "visible" => true },
        "portfolio" => { "path" => "portfolio", "order" => 30, "visible" => true }
      },
      navigation
    )
    assert navigation.frozen?
    assert navigation.fetch("home").frozen?
  end

  def test_site_navigation_normalizes_builtin_and_portfolio_overrides
    navigation, diagnostics = normalized_navigation(
      "home" => { "label" => "Start", "visible" => false },
      "blog" => { "order" => 30 },
      "portfolio" => { "path" => "selected-work", "label" => "Work", "visible" => false }
    )

    assert_empty diagnostics
    assert_equal({ "order" => 0, "visible" => false, "label" => "Start" }, navigation.fetch("home"))
    assert_equal({ "order" => 30, "visible" => true }, navigation.fetch("blog"))
    assert_equal({ "order" => 20, "visible" => true }, navigation.fetch("docs"))
    assert_equal(
      { "path" => "selected-work", "order" => 30, "visible" => false, "label" => "Work" },
      navigation.fetch("portfolio")
    )
  end

  def test_site_navigation_rejects_unknown_fields_invalid_types_and_unsafe_paths
    navigation, diagnostics = normalized_navigation(
      "unexpected" => {},
      "home" => { "label" => false, "order" => "first", "visible" => 1, "href" => "/" },
      "blog" => nil,
      "portfolio" => { "path" => "../work", "archive" => true },
      "folders" => []
    )

    messages = diagnostics.select { |item| item.code == "invalid_navigation_config" }.map(&:message)
    assert_includes messages, 'unknown website.navigation setting "unexpected"'
    assert_includes messages, 'unknown website.navigation.home setting "href"'
    assert_includes messages, "website.navigation.home.label must be a non-empty string containing only output-safe Unicode characters"
    assert_includes messages, "website.navigation.home.order must be an integer"
    assert_includes messages, "website.navigation.home.visible must be a YAML boolean"
    assert_includes messages, "website.navigation.blog must be a mapping with string keys"
    assert_includes messages, 'unknown website.navigation.portfolio setting "archive"'
    assert_includes messages, "website.navigation.portfolio.path must not contain empty or traversal segments"
    assert_includes messages, 'unknown website.navigation setting "folders"'
    assert_equal "portfolio", navigation.dig("portfolio", "path")
  end

  def test_translation_may_only_replace_a_default_tab_label
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("about/index.md", <<~MARKDOWN),
        ---
        publish: true
        tab:
          id: about
          label: About
          order: 30
        ---
        # About
      MARKDOWN
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("_translations/zh-CN/about/index.md", <<~MARKDOWN),
        ---
        publish: true
        tab:
          label: 关于
        ---
        # 关于
      MARKDOWN
      theme: "docs",
      i18n: I18N
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    translated = result.notes.find { |item| item.id == "zh-CN:about/index.md" }
    assert_equal(
      { "id" => "about", "label" => "关于", "order" => 30 },
      translated.properties.fetch("tab")
    )
  end

  def test_translation_cannot_opt_in_or_override_navigation_structure
    additions = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("about/index.md", "---\npublish: true\n---\n# About"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("_translations/zh-CN/about/index.md", "---\npublish: true\ntab:\n  label: 关于\n---\n# 关于"),
      theme: "docs",
      i18n: I18N
    )
    refute additions.success?
    assert(additions.diagnostics.any? do |item|
      item.code == "localized_structure_override" && item.message.include?("default-language note declares tab")
    end)

    overrides = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("about/index.md", "---\npublish: true\ntab:\n  id: about\n  label: About\n  order: 30\n  topics:\n    - profile\n---\n# About"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("_translations/zh-CN/about/index.md", "---\npublish: true\ntab:\n  label: 关于\n  order: 1\n  topics:\n    - other\n---\n# 关于"),
      theme: "docs",
      i18n: I18N
    )
    refute overrides.success?
    messages = overrides.diagnostics.select { |item| item.code == "localized_structure_override" }.map(&:message)
    assert_includes messages, "translation must inherit tab.order from the default language"
    assert_includes messages, "translation must inherit tab.topics from the default language"
  end

  def test_minimal_builtin_navigation_is_content_aware_ordered_and_overridable
    entries = [
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ndate: 2026-08-01\n---\n# Post"),
      note("docs/guide.md", "---\npublish: true\n---\n# Guide"),
      note("plain.md", "---\npublish: true\n---\n# Plain")
    ]
    result = compile(*entries, theme: "minimal")

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal %w[home blog docs], navigation_for(result, "/").map { |item| item.fetch("id") }
    assert_equal [0, 10, 20], navigation_for(result, "/").map { |item| item.fetch("order") }
    refute navigation_for(result, "/").any? { |item| item.fetch("url") == "/plain/" }

    overridden = compile(
      *entries,
      theme: "minimal",
      navigation: {
        "home" => { "label" => "Start", "order" => 30 },
        "blog" => { "visible" => false },
        "docs" => { "label" => "Handbook", "order" => 5 }
      }
    )
    assert overridden.success?, overridden.diagnostics.map(&:message).join("\n")
    assert_equal %w[docs home], navigation_for(overridden, "/").map { |item| item.fetch("id") }
    assert_equal %w[Handbook Start], navigation_for(overridden, "/").map { |item| item.fetch("label") }
    assert page(overridden, "/blog/")
    assert page(overridden, "/blog/post/")

    root_only = compile(entries.first, theme: "minimal")
    assert_equal ["home"], navigation_for(root_only, "/").map { |item| item.fetch("id") }

    post_only = compile(entries[1], theme: "minimal")
    assert_equal %w[home blog], navigation_for(post_only, "/").map { |item| item.fetch("id") }

    docs_only = compile(entries[2], theme: "minimal")
    assert_equal ["docs"], navigation_for(docs_only, "/").map { |item| item.fetch("id") }
  end

  def test_minimal_portfolio_claims_published_descendants_as_pages_and_adds_an_active_tab
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("portfolio/index.md", "---\npublish: true\n---\n# Selected work"),
      note("portfolio/alpha.md", "---\npublish: true\n---\n# Alpha"),
      note("portfolio/hidden.md", "---\npublish: true\nnav_exclude: true\n---\n# Hidden"),
      theme: "minimal",
      content: {
        "default_type" => "page",
        "directories" => { "post" => ["portfolio"], "doc" => [] }
      }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    portfolio = navigation_for(result, "/").find { |item| item.fetch("id") == "portfolio" }
    assert_equal({ "id" => "portfolio", "label" => "Portfolio", "url" => "/portfolio/", "order" => 30 }, portfolio)
    assert_equal "portfolio", current_navigation_id(result, "/portfolio/")
    assert_equal "portfolio", current_navigation_id(result, "/portfolio/alpha/")
    assert_equal "portfolio", current_navigation_id(result, "/portfolio/hidden/")
    assert_equal "page", page(result, "/portfolio/alpha/").data.dig("website", "content_type")
  end

  def test_minimal_portfolio_rejects_explicit_post_and_doc_content_types
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("portfolio/post.md", "---\npublish: true\ncontent_type: post\n---\n# Post"),
      note("portfolio/doc.md", "---\npublish: true\ncontent_type: doc\n---\n# Doc"),
      theme: "minimal"
    )

    refute result.success?
    conflicts = result.diagnostics.select { |item| item.code == "portfolio_content_type_conflict" }
    assert_equal %w[portfolio/doc.md portfolio/post.md], conflicts.map(&:path)
    refute result.diagnostics.any? { |item| item.code == "missing_post_date" }
  end

  def test_portfolio_index_at_the_public_root_owns_the_navigation_destination_when_posts_exist
    result = compile(
      note("portfolio/index.md", "---\npublish: true\npermalink: /\n---\n# Selected work"),
      note("portfolio/project.md", "---\npublish: true\n---\n# Project"),
      note("blog/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-08-07\n---\n# Post"),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal %w[blog portfolio], navigation_for(result, "/").map { |item| item.fetch("id") }
    assert_equal "portfolio", current_navigation_id(result, "/")
    assert_equal "/", page(result, "/").data.dig("website", "routes", "home")
  end

  def test_manual_empty_portfolio_path_is_ignored_and_visibility_only_hides_the_builtin_tab
    empty = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      theme: "minimal",
      navigation: { "portfolio" => { "path" => "work" } }
    )
    assert empty.success?, empty.diagnostics.map(&:message).join("\n")
    refute navigation_for(empty, "/").any? { |item| item.fetch("id") == "portfolio" }

    hidden = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("work/project.md", "---\npublish: true\n---\n# Project"),
      theme: "minimal",
      content: {
        "default_type" => "page",
        "directories" => { "post" => ["work"], "doc" => [] }
      },
      navigation: { "portfolio" => { "path" => "work", "visible" => false } }
    )
    assert hidden.success?, hidden.diagnostics.map(&:message).join("\n")
    refute navigation_for(hidden, "/").any? { |item| item.fetch("id") == "portfolio" }
    assert_equal "page", page(hidden, "/work/project/").data.dig("website", "content_type")
  end

  def test_custom_tab_uses_its_folder_index_and_marks_page_descendants_active
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("showcase/index.md", "---\npublish: true\ntitle: Selected work\ntab:\n  id: showcase\n  order: 30\n---\n# Showcase"),
      note("showcase/earlier.md", "---\npublish: true\nnav_order: 1\n---\n# Earlier"),
      note("projects/index.md", "---\npublish: true\ntab:\n  id: projects\n  order: 40\n---\n# Projects"),
      note("projects/hidden.md", "---\npublish: true\nnav_order: 0\nnav_exclude: true\n---\n# Hidden"),
      note("projects/zulu.md", "---\npublish: true\nnav_order: 10\n---\n# Alpha"),
      note("projects/alpha.md", "---\npublish: true\nnav_order: 10\n---\n# Alpha"),
      note("projects/unordered.md", "---\npublish: true\n---\n# Aardvark"),
      note("private-section/page.md", "---\npublish: true\n---\n# Private section"),
      theme: "minimal",
      baseurl: "/site"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    items = navigation_for(result, "/")
    portfolio = items.find { |item| item.fetch("id") == "showcase" }
    projects = items.find { |item| item.fetch("id") == "projects" }
    assert_equal "Selected work", portfolio.fetch("label")
    assert_equal "/site/showcase/", portfolio.fetch("url")
    assert_equal "Projects", projects.fetch("label")
    assert_equal "/site/projects/", projects.fetch("url")
    assert_equal "/site/", items.find { |item| item.fetch("id") == "home" }.fetch("url")
    refute items.any? { |item| item.fetch("id") == "private-section" }
    assert_equal "showcase", current_navigation_id(result, "/showcase/earlier/")
    assert_equal "projects", current_navigation_id(result, "/projects/zulu/")
    assert page(result, "/private-section/page/")
    refute_includes projects.fetch("url"), "/site/site/"
  end

  def test_custom_tab_scope_does_not_override_nested_posts
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("about.md", "---\npublish: true\n---\n# About"),
      note("section/index.md", "---\npublish: true\ntab:\n  id: section\n  order: 15\n---\n# Section"),
      note("section/alpha.md", "---\npublish: true\ntabs:\n  - section\n---\n# Alpha"),
      note("section/case-study.md", "---\npublish: true\n---\n# Case study"),
      note("section/dispatch.md", "---\npublish: true\ncontent_type: post\ndate: 2026-08-02\n---\n# Dispatch"),
      note("hidden.md", "---\npublish: true\n---\n# Hidden"),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    ids = navigation_for(result, "/").map { |item| item.fetch("id") }
    assert_equal %w[home blog section], ids
    assert_nil current_navigation_id(result, "/about/")
    assert_equal "section", current_navigation_id(result, "/section/case-study/")
    assert_equal "section", current_navigation_id(result, "/section/alpha/")
    assert_equal "blog", current_navigation_id(result, "/section/dispatch/")
    assert page(result, "/hidden/")
    assert_nil current_navigation_id(result, "/hidden/")
  end

  def test_navigation_projection_materializes_immutable_active_scopes
    root = published_note("index.md", "Home", "/", "page")
    post = published_note("blog/post.md", "Post", "/blog/post/", "post")
    doc = published_note("docs/guide.md", "Guide", "/docs/guide/", "doc")
    page_note = published_note(
      "about/index.md",
      "About",
      "/about/",
      "page",
      properties: { "tab" => { "id" => "about", "label" => "About" } }
    )
    model = JekyllObsidian::PublishedSiteModel.new(
      notes: [root, post, doc, page_note],
      notes_by_id: [root, post, doc, page_note].to_h { |item| [item.id, item] },
      relations: [],
      graph_edges: [],
      graph_degrees: {}
    )
    navigation, diagnostics = normalized_navigation(nil)
    projection = JekyllObsidian::SiteNavigation.build(
      model: model,
      settings: navigation,
      content: JekyllObsidian::ContentPolicy::DEFAULT_SETTINGS,
      url_builder: JekyllObsidian::UrlBuilder.new(origin: "https://example.test", baseurl: "/site"),
      theme: "minimal"
    )

    assert_empty diagnostics
    assert_empty projection.diagnostics
    home = projection.items.find { |item| item.fetch("id") == "home" }
    blog = projection.items.find { |item| item.fetch("id") == "blog" }
    docs = projection.items.find { |item| item.fetch("id") == "docs" }
    about = projection.items.find { |item| item.fetch("id") == "about" }
    assert_equal %w[active_scope id label order url], home.keys.sort
    assert_equal({ "note_ids" => ["index.md"], "routes" => ["/"] }, home.fetch("active_scope"))
    assert_equal({ "note_ids" => ["blog/post.md"], "routes" => ["/blog/"] }, blog.fetch("active_scope"))
    assert_equal({ "note_ids" => ["docs/guide.md"], "routes" => [] }, docs.fetch("active_scope"))
    assert_equal({ "note_ids" => ["about/index.md"], "routes" => [] }, about.fetch("active_scope"))
    assert_equal(
      {
        "index.md" => "home",
        "blog/post.md" => "blog",
        "docs/guide.md" => "docs",
        "about/index.md" => "about"
      },
      projection.active_by_note_id
    )
    assert projection.frozen?
    assert projection.items.frozen?
    assert home.fetch("active_scope").fetch("note_ids").frozen?
    assert_raises(FrozenError) { home.fetch("active_scope").fetch("routes") << "/elsewhere/" }
  end

  def test_portfolio_projection_uses_the_authored_index_route_and_sorts_visible_projects
    index = published_note("work/index.md", "Selected work", "/selected/", "page")
    ordered = published_note("work/ordered.md", "Later", "/work/ordered/", "page", nav_order: 5)
    alpha = published_note("work/alpha.md", "Alpha", "/work/alpha/", "page")
    zulu = published_note("work/zulu.md", "Zulu", "/work/zulu/", "page")
    hidden = published_note("work/hidden.md", "Hidden", "/work/hidden/", "page", nav_exclude: true)
    notes = [index, zulu, hidden, alpha, ordered]
    model = JekyllObsidian::PublishedSiteModel.new(
      notes: notes,
      notes_by_id: notes.to_h { |note| [note.id, note] },
      relations: [],
      graph_edges: [],
      graph_degrees: {}
    )
    navigation, diagnostics = normalized_navigation(
      "portfolio" => { "path" => "work", "visible" => false }
    )

    projection = JekyllObsidian::SiteNavigation.build(
      model: model,
      settings: navigation,
      content: JekyllObsidian::ContentPolicy::DEFAULT_SETTINGS,
      url_builder: JekyllObsidian::UrlBuilder.new(origin: "https://example.test", baseurl: "/site"),
      theme: "minimal"
    )

    assert_empty diagnostics
    assert_empty projection.diagnostics
    assert_equal "work", projection.portfolio.path
    assert_equal "/selected/", projection.portfolio.route
    assert_equal "work/index.md", projection.portfolio.index_note_id
    assert_equal %w[work/ordered.md work/alpha.md work/zulu.md], projection.portfolio.project_note_ids
    refute projection.items.any? { |item| item.fetch("id") == "portfolio" }
    refute projection.active_by_note_id.key?("work/alpha.md")
    assert projection.portfolio.frozen?
  end

  def test_portfolio_without_an_index_projects_a_generated_landing_route_and_all_descendant_active_ids
    project = published_note("selected/work.md", "Work", "/selected/work/", "page")
    hidden = published_note("selected/hidden.md", "Hidden", "/selected/hidden/", "page", nav_exclude: true)
    notes = [hidden, project]
    model = JekyllObsidian::PublishedSiteModel.new(
      notes: notes,
      notes_by_id: notes.to_h { |note| [note.id, note] },
      relations: [],
      graph_edges: [],
      graph_degrees: {}
    )
    navigation, diagnostics = normalized_navigation("portfolio" => { "path" => "selected" })

    projection = JekyllObsidian::SiteNavigation.build(
      model: model,
      settings: navigation,
      content: JekyllObsidian::ContentPolicy::DEFAULT_SETTINGS,
      url_builder: JekyllObsidian::UrlBuilder.new(origin: "https://example.test", baseurl: "/site"),
      theme: "minimal"
    )

    assert_empty diagnostics
    assert_equal "/selected/", projection.portfolio.route
    assert_nil projection.portfolio.index_note_id
    assert_equal ["selected/work.md"], projection.portfolio.project_note_ids
    item = projection.items.find { |candidate| candidate.fetch("id") == "portfolio" }
    assert_equal "/site/selected/", item.fetch("url")
    assert_equal "portfolio", projection.active_by_note_id.fetch("selected/work.md")
    assert_equal "portfolio", projection.active_by_note_id.fetch("selected/hidden.md")
  end

  def test_portfolio_index_without_a_visible_project_does_not_trigger_the_projection
    index = published_note("portfolio/index.md", "Portfolio", "/portfolio/", "page")
    hidden = published_note("portfolio/hidden.md", "Hidden", "/portfolio/hidden/", "page", nav_exclude: true)
    navigation, diagnostics = normalized_navigation(nil)

    [
      [index],
      [index, hidden]
    ].each do |notes|
      model = JekyllObsidian::PublishedSiteModel.new(
        notes: notes,
        notes_by_id: notes.to_h { |note| [note.id, note] },
        relations: [],
        graph_edges: [],
        graph_degrees: {}
      )
      projection = JekyllObsidian::SiteNavigation.build(
        model: model,
        settings: navigation,
        content: JekyllObsidian::ContentPolicy::DEFAULT_SETTINGS,
        url_builder: JekyllObsidian::UrlBuilder.new(origin: "https://example.test", baseurl: ""),
        theme: "minimal"
      )

      assert_nil projection.portfolio
      refute projection.items.any? { |item| item.fetch("id") == "portfolio" }
    end
    assert_empty diagnostics
  end

  def test_navigation_reports_duplicate_unpublished_excluded_and_portfolio_tab_sources
    duplicate = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("one/index.md", "---\npublish: true\ntab:\n  id: work\n---\n# One"),
      note("two/index.md", "---\npublish: true\ntab:\n  id: work\n---\n# Two"),
      theme: "minimal"
    )
    assert_diagnostic duplicate, "duplicate_tab_id", "two/index.md"

    unpublished = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("private/index.md", "---\npublish: false\ntab:\n  id: private\n---\n# Private"),
      theme: "minimal"
    )
    assert_diagnostic unpublished, "unpublished_tab_declaration", "private/index.md"

    excluded = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("work/index.md", "---\npublish: true\ntab:\n  id: work\n---\n# Work"),
      note("hidden.md", "---\npublish: true\nnav_exclude: true\ntabs:\n  - work\n---\n# Hidden"),
      theme: "minimal"
    )
    assert_diagnostic excluded, "invalid_tab_membership", "hidden.md"

    portfolio = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("portfolio/index.md", "---\npublish: true\ntab:\n  id: selected\n---\n# Selected"),
      note("portfolio/project.md", "---\npublish: true\n---\n# Project"),
      theme: "minimal"
    )
    assert_diagnostic portfolio, "tab_conflicts_with_portfolio", "portfolio/index.md"
  end

  def test_localized_custom_tab_changes_only_its_label_and_keeps_order_and_scope
    entries = [
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("about/index.md", "---\npublish: true\ntab:\n  id: about\n  label: About\n  order: 15\n---\n# About"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest(
        "_translations/zh-CN/_locale.yml",
        "name: 简体中文\nmessages:\n  home: 首页\n  blog: 博客\n  docs: 文档\n"
      ),
      note("_translations/zh-CN/index.md", "---\npublish: true\n---\n# 首页"),
      note("_translations/zh-CN/about/index.md", "---\npublish: true\ntab:\n  label: 关于\n---\n# 关于")
    ]
    result = compile(
      *entries,
      theme: "minimal",
      baseurl: "/site",
      i18n: I18N.merge("enabled" => true)
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    default_item = navigation_for(result, "/about/").find { |item| item.fetch("id") == "about" }
    translated_item = navigation_for(result, "/zh-CN/about/").find { |item| item.fetch("id") == "about" }
    assert_equal "About", default_item.fetch("label")
    assert_equal "关于", translated_item.fetch("label")
    assert_equal default_item.fetch("order"), translated_item.fetch("order")
    assert_equal "about", page(result, "/about/").data.dig("website", "active_navigation_id")
    assert_equal "about", page(result, "/zh-CN/about/").data.dig("website", "active_navigation_id")
    refute default_item.key?("active_scope")
    refute translated_item.key?("active_scope")
    assert_equal "/site/about/", default_item.fetch("url")
    assert_equal "/site/zh-CN/about/", translated_item.fetch("url")
  end

  def test_localized_labels_do_not_reorder_items_with_the_same_default_order
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("alpha/index.md", "---\npublish: true\ntab:\n  id: alpha\n  label: Alpha\n  order: 30\n---\n# Alpha"),
      note("beta/index.md", "---\npublish: true\ntab:\n  id: beta\n  label: Beta\n  order: 30\n---\n# Beta"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("_translations/zh-CN/index.md", "---\npublish: true\n---\n# 首页"),
      note("_translations/zh-CN/alpha/index.md", "---\npublish: true\ntab:\n  label: Zulu\n---\n# 甲"),
      note("_translations/zh-CN/beta/index.md", "---\npublish: true\ntab:\n  label: Able\n---\n# 乙"),
      theme: "minimal",
      i18n: I18N.merge("enabled" => true)
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    default_items = navigation_for(result, "/").select { |item| %w[alpha beta].include?(item.fetch("id")) }
    translated_items = navigation_for(result, "/zh-CN/").select { |item| %w[alpha beta].include?(item.fetch("id")) }
    assert_equal %w[alpha beta], default_items.map { |item| item.fetch("id") }
    assert_equal default_items.map { |item| item.fetch("id") }, translated_items.map { |item| item.fetch("id") }
    assert_equal %w[Zulu Able], translated_items.map { |item| item.fetch("label") }
  end

  def test_localized_root_redirect_uses_the_default_language_navigation_order
    result = compile(
      note("alpha/index.md", "---\npublish: true\ntab:\n  id: alpha\n  label: Alpha\n  order: 30\n---\n# Alpha"),
      note("beta/index.md", "---\npublish: true\ntab:\n  id: beta\n  label: Beta\n  order: 30\n---\n# Beta"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("_translations/zh-CN/alpha/index.md", "---\npublish: true\ntab:\n  label: Zulu\n---\n# 甲"),
      note("_translations/zh-CN/beta/index.md", "---\npublish: true\ntab:\n  label: Able\n---\n# 乙"),
      theme: "minimal",
      i18n: I18N.merge("enabled" => true)
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal "/alpha/", page(result, "/").data.dig("website", "redirect_url")
    assert_equal "/zh-CN/alpha/", page(result, "/zh-CN/").data.dig("website", "redirect_url")
  end

  def test_localized_builtin_labels_are_revalidated_after_message_projection
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ndate: 2026-08-01\n---\n# Post"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest(
        "_translations/zh-CN/_locale.yml",
        "name: 简体中文\nmessages:\n  home: Content\n  blog: Content\n"
      ),
      theme: "minimal",
      i18n: I18N.merge("enabled" => true)
    )

    assert_diagnostic result, "duplicate_navigation_label", "_translations/zh-CN/_locale.yml"

    blank = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest(
        "_translations/zh-CN/_locale.yml",
        "name: 简体中文\nmessages:\n  home: \"  \"\n"
      ),
      theme: "minimal",
      i18n: I18N.merge("enabled" => true)
    )

    assert_diagnostic blank, "invalid_navigation_label", "_translations/zh-CN/_locale.yml"
  end

  private

  def navigation_for(result, route)
    page(result, route).data.dig("website", "navigation")
  end

  def current_navigation_id(result, route)
    page(result, route).data.dig("website", "active_navigation_id")
  end

  def assert_diagnostic(result, code, path)
    refute result.success?
    assert result.diagnostics.any? { |item| item.code == code && item.path == path },
      result.diagnostics.map { |item| "#{item.code}: #{item.path}: #{item.message}" }.join("\n")
  end

  def published_note(id, title, route, content_type, properties: {}, nav_order: nil, nav_exclude: false)
    JekyllObsidian::PublishedNote.new(
      id: id,
      title: title,
      route: route,
      content_type: content_type,
      properties: properties,
      nav_order: nav_order,
      nav_exclude: nav_exclude
    )
  end

  def normalized_navigation(raw)
    config = JekyllObsidian::BuildConfig.new(**DEFAULT_CONFIG.merge(navigation: raw))
    compiler = JekyllObsidian::VaultCompiler.new(
      JekyllObsidian::BuildRequest.new(snapshot: JekyllObsidian::Snapshot.new(entries: []), config: config)
    )
    compiler.send(:resolve_navigation_config)
    [compiler.instance_variable_get(:@navigation_config), compiler.instance_variable_get(:@diagnostics)]
  end
end
