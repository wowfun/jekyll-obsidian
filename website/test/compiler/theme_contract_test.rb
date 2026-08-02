# frozen_string_literal: true

require "test_helper"

class ThemeContractTest < Minitest::Test
  def test_default_theme_is_digital_garden_and_unknown_themes_fail_closed
    home = note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home")

    default_result = compile(home)
    assert default_result.success?, default_result.diagnostics.map(&:message).join("\n")
    assert_equal "digital-garden", default_result.theme
    assert_equal "obsidian-digital-garden", page(default_result, "/").data.fetch("layout")
    assert_equal "digital-garden", page(default_result, "/").data.dig("obsidian", "theme")
    assert_equal "https://github.com/example/garden", default_result.site_data.fetch("obsidian_repository_url")

    invalid_result = compile(home, theme: "magazine")
    refute invalid_result.success?
    assert invalid_result.diagnostics.any? { |item| item.code == "invalid_theme" }
  end

  def test_invalid_repository_does_not_publish_a_github_url
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      repository: "https://example.test/not-github"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    refute result.site_data.key?("obsidian_repository_url")
  end

  def test_public_root_index_is_required_in_development_too
    result = compile(
      note("docs/guide.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Guide"),
      theme: "docs",
      environment: "development"
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "missing_index" && item.path == "index.md" }
  end

  def test_note_routes_are_identical_across_all_built_in_themes
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ndate: 2026-07-01\n---\n# Post"),
      note("docs/guide.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Guide"),
      note("notes/Café.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Café")
    ]

    route_sets = %w[blog docs digital-garden].to_h do |theme|
      result = compile(*entries, theme: theme)
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      [theme, result.notes.map { |published_note| [published_note.id, published_note.route] }]
    end

    assert_equal route_sets.fetch("blog"), route_sets.fetch("docs")
    assert_equal route_sets.fetch("blog"), route_sets.fetch("digital-garden")
  end

  def test_content_type_uses_explicit_property_then_directory_then_default
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("blog/from-folder.md", "---\npublish: true\ndate: 2026-07-01\n---\n# Folder post"),
      note("blog/explicit-doc.md", "---\npublish: true\ncontent_type: doc\ncreated: 2026-07-02\nupdated: 2026-07-30\n---\n# Explicit doc"),
      note("misc.md", "---\npublish: true\ncreated: 2026-07-03\nupdated: 2026-07-30\n---\n# Default page"),
      theme: "blog",
      content: {
        "default_type" => "page",
        "directories" => { "post" => ["blog"], "doc" => ["docs"] }
      }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal "page", page(result, "/").data.dig("obsidian", "content_type")
    assert_equal "post", page(result, "/blog/from-folder/").data.dig("obsidian", "content_type")
    assert_equal "doc", page(result, "/blog/explicit-doc/").data.dig("obsidian", "content_type")
    assert_equal "page", page(result, "/misc/").data.dig("obsidian", "content_type")

    assert_equal "2026-07-01T00:00:00Z", page(result, "/blog/from-folder/").data.dig("obsidian", "published_at")
    assert_nil page(result, "/blog/explicit-doc/").data.dig("obsidian", "published_at")
    assert_nil page(result, "/misc/").data.dig("obsidian", "published_at")
  end

  def test_post_published_at_precedence_and_missing_date_mode_behavior
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("posts/dated.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-03\ncreated: 2026-07-02\n---\n# Dated", first_committed_at: "2026-07-01T00:00:00Z"),
      note("posts/created.md", "---\npublish: true\ncontent_type: post\ncreated: 2026-07-04\n---\n# Created", first_committed_at: "2026-07-01T00:00:00Z"),
      note("posts/git.md", "---\npublish: true\ncontent_type: post\n---\n# Git", first_committed_at: "2026-07-05T12:00:00Z")
    ]
    result = compile(*entries, theme: "blog")

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal "2026-07-03T00:00:00Z", page(result, "/posts/dated/").data.dig("obsidian", "published_at")
    assert_equal "2026-07-04T00:00:00Z", page(result, "/posts/created/").data.dig("obsidian", "published_at")
    assert_equal "2026-07-05T12:00:00Z", page(result, "/posts/git/").data.dig("obsidian", "published_at")
    feed = result.generated_files.find { |file| file.route == "/feed.xml" }
    refute_nil feed
    assert_includes feed.content, "<published>2026-07-03T00:00:00Z</published>"

    timeless = entries + [note("posts/timeless.md", "---\npublish: true\ncontent_type: post\n---\n# Timeless")]
    production = compile(*timeless, theme: "blog")
    refute production.success?
    assert production.diagnostics.any? { |item| item.code == "missing_post_date" && item.severity == :error }

    development = compile(*timeless, theme: "blog", environment: "development")
    assert development.success?
    assert development.diagnostics.any? { |item| item.code == "missing_post_date" && item.severity == :warning }
  end

  def test_each_theme_projects_only_its_pages_and_default_feature_files
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-01\nupdated: 2026-07-02\ntags: [release]\n---\n# Post"),
      note("docs/guide.md", "---\npublish: true\ncontent_type: doc\nupdated: 2026-07-30\n---\n# Guide")
    ]

    garden = compile(*entries)
    assert_equal %w[/ /404.html /blog/post/ /docs/guide/ /graph/ /notes/ /tags/], garden.pages.map(&:route)
    assert_equal %w[/assets/obsidian/catalog.v1.json /assets/obsidian/graph.v1.json /assets/obsidian/search.v1.json /feed.xml /sitemap.xml], garden.generated_files.map(&:route)

    blog = compile(*entries, theme: "blog")
    assert blog.success?, blog.diagnostics.map(&:message).join("\n")
    assert_equal %w[/ /404.html /archive/ /blog/post/ /docs/guide/ /tags/], blog.pages.map(&:route)
    assert_equal %w[/assets/obsidian/search.v1.json /feed.xml /sitemap.xml], blog.generated_files.map(&:route)
    assert_equal "obsidian-blog", page(blog, "/archive/").data.fetch("layout")

    docs = compile(*entries, theme: "docs")
    assert docs.success?, docs.diagnostics.map(&:message).join("\n")
    assert_equal %w[/ /404.html /blog/post/ /docs/guide/], docs.pages.map(&:route)
    assert_equal %w[/assets/obsidian/docs-navigation.html /assets/obsidian/search.v1.json /sitemap.xml], docs.generated_files.map(&:route)
    assert_equal "obsidian-docs", page(docs, "/").data.fetch("layout")
    assert_equal "/docs/guide/", page(docs, "/").data.dig("obsidian", "theme_data", "docs_home_url")

    stripped = compile(*entries, theme: "docs", features: { "search" => false, "graph" => true })
    assert_equal false, stripped.features.fetch("search")
    assert_equal true, stripped.features.fetch("graph")
    refute stripped.generated_files.any? { |file| file.route.end_with?("search.v1.json") }
    assert stripped.generated_files.any? { |file| file.route.end_with?("graph.v1.json") }
    refute_nil page(stripped, "/graph/")
  end

  def test_blog_aggregates_only_posts_and_exposes_stable_chronology
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\ntags: [private-page-tag]\n---\n# Home"),
      note("blog/older.md", "---\npublish: true\ncontent_type: post\ndate: 2026-06-01\nupdated: 2026-06-03\ntags: [journal]\n---\n# Older"),
      note("blog/newer.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-01\nupdated: 2026-07-03\ntags: [journal]\n---\n# Newer"),
      note("about.md", "---\npublish: true\nupdated: 2026-07-30\ntags: [private-page-tag]\n---\n# About"),
      theme: "blog"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    recent = page(result, "/").data.dig("obsidian", "theme_data", "recent_posts")
    assert_equal %w[blog/newer.md blog/older.md], recent.map { |item| item.fetch("id") }

    older = page(result, "/blog/older/").data.dig("obsidian", "theme_data")
    assert_nil older.fetch("previous")
    assert_equal "blog/newer.md", older.fetch("next").fetch("id")
    newer = page(result, "/blog/newer/").data.dig("obsidian", "theme_data")
    assert_equal "blog/older.md", newer.fetch("previous").fetch("id")
    assert_nil newer.fetch("next")

    archive = page(result, "/archive/")
    assert_equal %w[2026], archive.data.dig("obsidian", "theme_data", "archive_groups").map { |group| group.fetch("label") }
    tag_names = page(result, "/tags/").data.dig("obsidian", "theme_data", "tag_groups")
      .map { |group| group.fetch("name") }
    refute_includes tag_names, "private-page-tag"
    feed = result.generated_files.find { |file| file.route == "/feed.xml" }.content
    assert_includes feed, "Older"
    assert_includes feed, "Newer"
    refute_includes feed, "About"
    refute_includes feed, ">Home<"
  end

  def test_blog_uses_note_id_to_break_equal_dates_and_archives_undated_development_posts
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("blog/alpha.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-01\nupdated: 2026-07-02\n---\n# Alpha"),
      note("blog/zulu.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-01\nupdated: 2026-07-02\n---\n# Zulu"),
      note("blog/undated.md", "---\npublish: true\ncontent_type: post\n---\n# Undated")
    ]

    result = compile(*entries.reverse, theme: "blog", environment: "development")

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    recent = page(result, "/").data.dig("obsidian", "theme_data", "recent_posts")
    assert_equal %w[blog/zulu.md blog/alpha.md blog/undated.md], recent.map { |post| post.fetch("id") }

    archive = page(result, "/archive/").data.dig("obsidian", "theme_data", "archive_groups")
    assert_equal %w[2026 Undated], archive.map { |group| group.fetch("label") }
    assert_equal %w[blog/zulu.md blog/alpha.md], archive.first.fetch("posts").map { |post| post.fetch("id") }
    assert_equal ["blog/undated.md"], archive.last.fetch("posts").map { |post| post.fetch("id") }
  end

  def test_theme_projection_is_deeply_immutable_and_deterministic_through_compile
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n[[blog/post]]"),
      note("blog/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-01\nupdated: 2026-07-02\n---\n# Post")
    ]

    first = compile(*entries, theme: "blog")
    second = compile(*entries.reverse, theme: "blog")

    assert_equal first, second
    assert_raises(FrozenError) do
      page(first, "/").data.dig("obsidian", "theme_data", "recent_posts") << { "id" => "mutated.md" }
    end
    assert_raises(FrozenError) { first.relations.first.source_id.replace("mutated.md") }
  end

  def test_docs_builds_tree_breadcrumbs_and_navigation_from_visible_docs
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("docs/index.md", "---\npublish: true\nnav_order: 1\nupdated: 2026-07-30\n---\n# Manual"),
      note("docs/reference.md", "---\npublish: true\nnav_order: 20\nupdated: 2026-07-30\n---\n# Reference"),
      note("docs/install.md", "---\npublish: true\nnav_order: 10\nupdated: 2026-07-30\n---\n# Install"),
      note("docs/hidden.md", "---\npublish: true\nnav_order: 15\nnav_exclude: true\nupdated: 2026-07-30\n---\n# Hidden"),
      theme: "docs",
      content: { "directories" => { "doc" => ["docs"], "post" => [] } }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    tree = page(result, "/").data.dig("obsidian", "theme_data", "docs_tree")
    assert_equal ["docs/index.md"], tree.map { |node| node.fetch("id") }
    assert_equal %w[docs/install.md docs/reference.md], tree.first.fetch("children").map { |node| node.fetch("id") }
    assert_equal "/docs/", page(result, "/").data.dig("obsidian", "theme_data", "docs_home_url")

    reference_data = page(result, "/docs/reference/").data.dig("obsidian", "theme_data")
    assert_equal %w[docs/index.md docs/reference.md], reference_data.fetch("breadcrumbs").map { |item| item.fetch("id") }
    assert_equal "docs/install.md", reference_data.fetch("previous").fetch("id")
    assert_nil reference_data.fetch("next")

    manual_data = page(result, "/docs/").data.dig("obsidian", "theme_data")
    assert_nil manual_data.fetch("previous")
    assert_equal "docs/install.md", manual_data.fetch("next").fetch("id")
  end

  def test_docs_folders_without_landings_are_text_groups_and_hidden_landings_keep_children
    missing = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("docs/guides/install.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Install"),
      theme: "docs"
    )
    tree = page(missing, "/").data.dig("obsidian", "theme_data", "docs_tree")
    assert_nil tree.first.fetch("url")
    assert_nil tree.first.fetch("children").first.fetch("url")
    assert_equal "/docs/guides/install/", page(missing, "/").data.dig("obsidian", "theme_data", "docs_home_url")

    hidden = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("docs/index.md", "---\npublish: true\nnav_exclude: true\nupdated: 2026-07-30\n---\n# Hidden manual"),
      note("docs/child.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Child"),
      theme: "docs"
    )
    hidden_root = page(hidden, "/").data.dig("obsidian", "theme_data", "docs_tree").first
    assert_equal "docs/index.md", hidden_root.fetch("id")
    assert_nil hidden_root.fetch("url")
    assert_equal ["docs/child.md"], hidden_root.fetch("children").map { |node| node.fetch("id") }
    assert_equal "/docs/child/", page(hidden, "/").data.dig("obsidian", "theme_data", "docs_home_url")

    no_docs = compile(note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"), theme: "docs")
    assert_nil page(no_docs, "/").data.dig("obsidian", "theme_data", "docs_home_url")
  end

  def test_theme_content_and_feature_configuration_is_fail_closed
    home = note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home")

    invalid_features = compile(home, features: { "search" => "yes", "telepathy" => true })
    refute invalid_features.success?
    assert_equal 2, invalid_features.diagnostics.count { |item| item.code == "invalid_feature" }

    traversal = compile(home, content: { "directories" => { "post" => ["../posts"], "doc" => [] } })
    refute traversal.success?
    assert traversal.diagnostics.any? { |item| item.code == "invalid_content_directory" }

    overlap = compile(home, content: { "directories" => { "post" => ["content"], "doc" => ["content/docs"] } })
    refute overlap.success?
    assert overlap.diagnostics.any? { |item| item.code == "overlapping_content_directories" }
  end

  def test_new_frontmatter_properties_are_strictly_typed_and_root_stays_a_page
    invalid = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      content_type: article
      date: someday
      nav_order: first
      nav_exclude: 1
      ---
      # Home
    MARKDOWN

    refute invalid.success?
    assert_operator invalid.diagnostics.count { |item| item.code == "invalid_property" }, :>=, 4

    wrong_root = compile(note("index.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-01\n---\n# Home"))
    refute wrong_root.success?
    assert wrong_root.diagnostics.any? { |item| item.code == "invalid_root_content_type" }
    assert_instance_of JekyllObsidian::BuildFailure, wrong_root
  end

  def test_effective_features_include_content_bundles_and_public_dom_is_neutral
    result = compile(
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Home
        [[other]]
        ![[other]]

        $x^2$

        ```mermaid
        graph TD
          A --> B
        ```
      MARKDOWN
      note("other.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Other\n> [!tip] Note")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal true, result.features.fetch("math")
    assert_equal true, result.features.fetch("mermaid")
    html = result.pages.map(&:content).join("\n")
    assert_includes html, "obsidian-link"
    assert_includes html, "obsidian-transclusion"
    assert_includes html, "obsidian-callout"
    refute_match(/(?:class|data-[a-z-]+)=["'][^"']*garden-/, html)
  end

  def test_system_routes_are_reserved_only_when_the_active_theme_outputs_them
    home = note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home")
    candidates = %w[archive graph notes tags].map do |name|
      note("#{name}.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# #{name.capitalize}")
    end

    docs = compile(home, *candidates, theme: "docs")
    assert docs.success?, docs.diagnostics.map(&:message).join("\n")
    assert_equal %w[/archive/ /graph/ /notes/ /tags/], candidates.map { |entry| page(docs, "/#{File.basename(entry.path, '.md')}/").route }

    blog_available = compile(home, candidates[1], candidates[2], theme: "blog")
    assert blog_available.success?, blog_available.diagnostics.map(&:message).join("\n")
    assert page(blog_available, "/graph/")
    assert page(blog_available, "/notes/")
    %w[archive tags].each do |reserved|
      result = compile(home, note("#{reserved}.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Reserved"), theme: "blog")
      refute result.success?, "expected blog to reserve /#{reserved}/"
      assert result.diagnostics.any? { |item| item.code == "route_collision" }
    end

    garden_archive = compile(home, candidates[0], theme: "digital-garden")
    assert garden_archive.success?, garden_archive.diagnostics.map(&:message).join("\n")
    assert page(garden_archive, "/archive/")
    %w[notes tags graph].each do |reserved|
      result = compile(home, note("#{reserved}.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Reserved"), theme: "digital-garden")
      refute result.success?, "expected digital-garden to reserve /#{reserved}/"
      assert result.diagnostics.any? { |item| item.code == "route_collision" }
    end
  end

  def test_docs_pages_keep_only_the_current_branch_and_share_one_full_navigation_fragment
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("docs/index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Docs"),
      note("docs/a/one.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# One"),
      note("docs/b/two.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Two"),
      theme: "docs"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    branch = page(result, "/docs/a/one/").data.dig("obsidian", "theme_data", "docs_tree")
    ids = []
    collect_ids = lambda do |nodes|
      nodes.each do |node|
        ids << node.fetch("id")
        collect_ids.call(node.fetch("children"))
      end
    end
    collect_ids.call(branch)
    assert_includes ids, "docs/a/one.md"
    refute_includes ids, "docs/b/two.md"
    shared = result.generated_files.select { |file| file.route == "/assets/obsidian/docs-navigation.html" }
    assert_equal 1, shared.length
    assert_includes shared.first.content, "One"
    assert_includes shared.first.content, "Two"
  end

  def test_graph_switches_to_bounded_directory_above_the_interactive_node_budget
    entries = [note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home")]
    250.times do |index|
      entries << note("notes/#{index}.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Note #{index}")
    end

    result = compile(*entries)
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal false, result.site_data.fetch("obsidian_graph_interactive")
    refute result.generated_files.any? { |file| file.route == "/assets/obsidian/graph.v1.json" }
    graph_data = page(result, "/graph/").data.dig("obsidian", "theme_data")
    assert_equal false, graph_data.fetch("graph_interactive")
    assert_equal 251, graph_data.fetch("graph_notes").length
  end

  def test_feature_and_always_generated_namespaces_reserve_matching_directory_routes
    home = note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home")
    feed_directory = note("feed.xml.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Feed directory")

    feed_disabled = compile(home, feed_directory, theme: "docs")
    assert feed_disabled.success?, feed_disabled.diagnostics.map(&:message).join("\n")
    assert page(feed_disabled, "/feed.xml/")

    feed_enabled = compile(home, feed_directory, theme: "docs", features: { "feed" => true })
    refute feed_enabled.success?
    assert feed_enabled.diagnostics.any? { |item| item.code == "route_collision" }

    %w[404.html sitemap.xml assets/obsidian/private assets/vault/private].each do |path|
      result = compile(home, note("#{path}.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Reserved"), theme: "docs")
      refute result.success?, "expected /#{path}/ to remain reserved"
      assert result.diagnostics.any? { |item| item.code == "route_collision" }
    end
  end
end
