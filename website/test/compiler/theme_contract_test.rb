# frozen_string_literal: true

require "test_helper"

class ThemeContractTest < Minitest::Test
  def test_default_theme_is_minimal_and_unknown_themes_fail_closed
    home = note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home")

    default_result = compile(home)
    assert default_result.success?, default_result.diagnostics.map(&:message).join("\n")
    assert_equal "minimal", default_result.theme
    assert_equal "website-minimal", page(default_result, "/").data.fetch("layout")
    assert_equal "minimal", page(default_result, "/").data.dig("website", "theme")
    assert_empty default_result.site_data

    invalid_result = compile(home, theme: "magazine")
    refute invalid_result.success?
    assert invalid_result.diagnostics.any? { |item| item.code == "invalid_theme" }
  end

  def test_missing_root_index_keeps_recent_posts_home_or_redirects_to_first_visible_section
    docs = compile(
      note("later.md", "---\npublish: true\nnav_order: 20\nupdated: 2026-07-30\n---\n# Later"),
      note("first.md", "---\npublish: true\nnav_order: 10\nupdated: 2026-07-30\n---\n# First"),
      theme: "docs",
      environment: "development",
      content: { "default_type" => "doc", "directories" => { "doc" => [], "post" => [] } }
    )
    assert docs.success?, docs.diagnostics.map(&:message).join("\n")
    docs_redirect = page(docs, "/")
    assert_equal "redirect", docs_redirect.data.dig("website", "kind")
    assert_equal "website-redirect", docs_redirect.data.fetch("layout")
    assert_equal "/first/", docs_redirect.data.dig("website", "redirect_url")
    assert_equal "https://example.test/first/", docs_redirect.data.dig("website", "canonical_url")
    assert_equal "/first/", page(docs, "/later/").data.dig("website", "routes", "home")
    sitemap = docs.generated_files.find { |file| file.route == "/sitemap.xml" }.content
    refute_includes sitemap, "<loc>https://example.test/</loc>"
    assert_includes sitemap, "<loc>https://example.test/first/</loc>"

    minimal = compile(
      note("posts/older.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-01\n---\n# Older"),
      note("posts/newer.md", "---\npublish: true\ncontent_type: post\ndate: 2026-08-01\n---\n# Newer"),
      theme: "minimal"
    )
    assert minimal.success?, minimal.diagnostics.map(&:message).join("\n")
    assert_equal "home", page(minimal, "/").data.dig("website", "kind")
    assert_equal %w[posts/newer.md posts/older.md], page(minimal, "/").data.dig("website", "theme_data", "recent_posts").map { |post| post.fetch("id") }
    assert_equal "/", page(minimal, "/posts/newer/").data.dig("website", "routes", "home")

    custom = compile(
      note("zulu.md", "---\npublish: true\nnavigation:\n  order: 20\n---\n# Zulu"),
      note("alpha.md", "---\npublish: true\nnavigation:\n  order: 10\n---\n# Alpha"),
      theme: "minimal"
    )
    assert custom.success?, custom.diagnostics.map(&:message).join("\n")
    assert_equal "/alpha/", page(custom, "/").data.dig("website", "redirect_url")
  end

  def test_content_directory_without_public_notes_fails_once
    result = compile(note("private.md", "---\npublish: false\n---\n# Private"), theme: "docs")

    refute result.success?
    assert_equal 1, result.diagnostics.count { |item| item.code == "missing_public_notes" }
    refute result.diagnostics.any? { |item| item.code == "invalid_index_count" }
  end

  def test_note_routes_are_identical_across_all_built_in_themes
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ndate: 2026-07-01\n---\n# Post"),
      note("docs/guide.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Guide"),
      note("notes/Café.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Café")
    ]

    route_sets = %w[minimal docs].to_h do |theme|
      result = compile(*entries, theme: theme)
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      [theme, result.notes.map { |published_note| [published_note.id, published_note.route] }]
    end

    assert_equal route_sets.fetch("minimal"), route_sets.fetch("docs")
  end

  def test_content_type_uses_explicit_property_then_directory_then_default
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("blog/from-folder.md", "---\npublish: true\ndate: 2026-07-01\n---\n# Folder post"),
      note("blog/explicit-doc.md", "---\npublish: true\ncontent_type: doc\ncreated: 2026-07-02\nupdated: 2026-07-30\n---\n# Explicit doc"),
      note("misc.md", "---\npublish: true\ncreated: 2026-07-03\nupdated: 2026-07-30\n---\n# Default page"),
      theme: "minimal",
      content: {
        "default_type" => "page",
        "directories" => { "post" => ["blog"], "doc" => ["docs"] }
      }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal "home", page(result, "/").data.dig("website", "kind")
    assert_equal "post", page(result, "/blog/from-folder/").data.dig("website", "content_type")
    assert_equal "doc", page(result, "/blog/explicit-doc/").data.dig("website", "content_type")
    assert_equal "page", page(result, "/misc/").data.dig("website", "content_type")

    assert_equal "2026-07-01T00:00:00Z", page(result, "/blog/from-folder/").data.dig("website", "published_at")
    assert_nil page(result, "/blog/explicit-doc/").data.dig("website", "published_at")
    assert_nil page(result, "/misc/").data.dig("website", "published_at")
  end

  def test_post_published_at_precedence_and_missing_date_mode_behavior
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("posts/dated.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-03\ncreated: 2026-07-02\n---\n# Dated", first_committed_at: "2026-07-01T00:00:00Z"),
      note("posts/created.md", "---\npublish: true\ncontent_type: post\ncreated: 2026-07-04\n---\n# Created", first_committed_at: "2026-07-01T00:00:00Z"),
      note("posts/git.md", "---\npublish: true\ncontent_type: post\n---\n# Git", first_committed_at: "2026-07-05T12:00:00Z")
    ]
    result = compile(*entries, theme: "minimal")

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal "2026-07-03T00:00:00Z", page(result, "/posts/dated/").data.dig("website", "published_at")
    assert_equal "2026-07-04T00:00:00Z", page(result, "/posts/created/").data.dig("website", "published_at")
    assert_equal "2026-07-05T12:00:00Z", page(result, "/posts/git/").data.dig("website", "published_at")
    feed = result.generated_files.find { |file| file.route == "/feed.xml" }
    refute_nil feed
    assert_includes feed.content, "<published>2026-07-03T00:00:00Z</published>"

    timeless = entries + [note("posts/timeless.md", "---\npublish: true\ncontent_type: post\n---\n# Timeless")]
    production = compile(*timeless, theme: "minimal")
    refute production.success?
    assert production.diagnostics.any? { |item| item.code == "missing_post_date" && item.severity == :error }

    development = compile(*timeless, theme: "minimal", environment: "development")
    assert development.success?
    assert development.diagnostics.any? { |item| item.code == "missing_post_date" && item.severity == :warning }
  end

  def test_each_theme_projects_only_its_pages_and_default_feature_files
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-01\nupdated: 2026-07-02\ntags: [release]\n---\n# Post"),
      note("docs/guide.md", "---\npublish: true\ncontent_type: doc\nupdated: 2026-07-30\n---\n# Guide")
    ]

    minimal = compile(*entries, theme: "minimal")
    assert minimal.success?, minimal.diagnostics.map(&:message).join("\n")
    assert_equal %w[/ /404.html /blog/ /blog/post/ /docs/guide/], minimal.pages.map(&:route)
    minimal_artifacts = minimal.generated_files.reject { |file| file.media_type == "text/markdown" }
    assert_equal %w[/assets/website/catalog.v1.json /assets/website/graph.v1.json /assets/website/search.v1.json /feed.xml /sitemap.xml], minimal_artifacts.map(&:route)
    assert_equal true, minimal.features.fetch("previews")
    assert_equal true, minimal.features.fetch("outline")
    assert_equal true, minimal.features.fetch("relations")
    assert_equal true, minimal.features.fetch("graph")
    assert_equal "website-minimal", page(minimal, "/blog/").data.fetch("layout")
    assert_nil page(minimal, "/tags/")

    docs = compile(*entries, theme: "docs")
    assert docs.success?, docs.diagnostics.map(&:message).join("\n")
    assert_equal %w[/ /404.html /blog/post/ /docs/guide/], docs.pages.map(&:route)
    docs_artifacts = docs.generated_files.reject { |file| file.media_type == "text/markdown" }
    assert_equal %w[/assets/website/catalog.v1.json /assets/website/graph.v1.json /assets/website/search.v1.json /sitemap.xml], docs_artifacts.map(&:route)
    assert_equal true, docs.features.fetch("previews")
    assert_equal true, docs.features.fetch("outline")
    assert_equal true, docs.features.fetch("relations")
    assert_equal true, docs.features.fetch("graph")
    assert_equal "website-docs", page(docs, "/").data.fetch("layout")
    assert_equal "/docs/guide/", page(docs, "/").data.dig("website", "theme_data", "docs_home_url")

    stripped = compile(*entries, theme: "docs", features: {
      "search" => false,
      "graph" => false,
      "previews" => false,
      "outline" => false,
      "relations" => false
    })
    assert_equal false, stripped.features.fetch("search")
    assert_equal false, stripped.features.fetch("graph")
    assert_equal false, stripped.features.fetch("previews")
    assert_equal false, stripped.features.fetch("outline")
    assert_equal false, stripped.features.fetch("relations")
    refute stripped.generated_files.any? { |file| file.route.end_with?("search.v1.json") }
    refute stripped.generated_files.any? { |file| file.route.end_with?("graph.v1.json") }
    refute stripped.generated_files.any? { |file| file.route.end_with?("catalog.v1.json") }
    assert_nil page(stripped, "/").data.dig("website", "local_graph")
    assert_equal false, page(stripped, "/").data.dig("website", "has_context")
  end

  def test_blog_aggregates_only_posts_and_exposes_stable_chronology
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\ntags: [private-page-tag]\n---\n# Home"),
      note("blog/older.md", "---\npublish: true\ncontent_type: post\ndate: 2026-06-01\nupdated: 2026-06-03\ntags: [journal]\n---\n# Older"),
      note("blog/newer.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-01\nupdated: 2026-07-03\ntags: [journal]\n---\n# Newer"),
      note("about.md", "---\npublish: true\nupdated: 2026-07-30\ntags: [private-page-tag]\n---\n# About"),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    recent = page(result, "/").data.dig("website", "theme_data", "recent_posts")
    assert_equal %w[blog/newer.md blog/older.md], recent.map { |item| item.fetch("id") }

    older = page(result, "/blog/older/").data.dig("website", "theme_data")
    assert_nil older.fetch("previous")
    assert_equal "blog/newer.md", older.fetch("next").fetch("id")
    newer = page(result, "/blog/newer/").data.dig("website", "theme_data")
    assert_equal "blog/older.md", newer.fetch("previous").fetch("id")
    assert_nil newer.fetch("next")

    archive = page(result, "/blog/")
    assert_equal %w[2026], archive.data.dig("website", "theme_data", "archive_groups").map { |group| group.fetch("label") }
    assert_equal [
      {
        "year" => "2026",
        "count" => 2,
        "months" => [
          { "key" => "2026-07", "label" => "07", "count" => 1 },
          { "key" => "2026-06", "label" => "06", "count" => 1 }
        ]
      }
    ], archive.data.dig("website", "theme_data", "timeline")
    assert_equal ["journal"], archive.data.dig("website", "theme_data", "archive_groups", 0, "posts", 0, "topic_anchors")
    assert_equal "2026-07", archive.data.dig("website", "theme_data", "archive_groups", 0, "posts", 0, "filter_month")
    assert_equal [
      { "name" => "journal", "anchor" => "journal", "count" => 2 }
    ], page(result, "/").data.dig("website", "theme_data", "topic_summaries")
    refute_includes page(result, "/blog/").data.dig("website", "theme_data", "topic_summaries").map { |topic| topic.fetch("name") }, "private-page-tag"
    assert_nil page(result, "/tags/")
    refute page(result, "/blog/newer/").data.fetch("website").key?("tag_summaries")
    assert_equal true, page(result, "/blog/newer/").data.dig("website", "has_context")
    feed = result.generated_files.find { |file| file.route == "/feed.xml" }.content
    assert_includes feed, "Older"
    assert_includes feed, "Newer"
    refute_includes feed, "About"
    refute_includes feed, ">Home<"
  end

  def test_blog_topics_support_author_categories_and_quoted_frontmatter_wiki_links
    result = compile(
      note("AI.md", "---\npublish: true\ntitle: Artificial Intelligence\n---\n# Artificial Intelligence"),
      note("people/Ada.md", "---\npublish: true\ntitle: Ada Lovelace\n---\n# Ada Lovelace"),
      note("blog/post.md", <<~MARKDOWN),
        ---
        publish: true
        title: Dreamers among programmers
        subtitle: A field note about software
        content_type: post
        date: 2026-08-05
        author:
          - "[[people/Ada|Ada]]"
          - Editorial team
        categories:
          - "[[AI]]"
          - Engineering
        tags:
          - essays
        ---
        The opening paragraph becomes the Home excerpt when description is omitted.
      MARKDOWN
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    output = result.notes.find { |note_output| note_output.id == "blog/post.md" }
    assert_equal ["[[people/Ada|Ada]]", "Editorial team"], output.properties.fetch("author")
    assert_equal ["[[AI]]", "Engineering"], output.properties.fetch("categories")
    assert_equal "A field note about software", output.properties.fetch("subtitle")

    post = page(result, "/").data.dig("website", "theme_data", "recent_posts", 0)
    assert_equal "A field note about software", post.fetch("subtitle")
    assert_includes post.fetch("summary"), "opening paragraph"
    assert_equal [
      { "kind" => "author", "name" => "Ada", "url" => "/people/Ada/" },
      { "kind" => "author", "name" => "Editorial team" }
    ], post.fetch("authors")

    topics = page(result, "/").data.dig("website", "theme_data", "topic_summaries")
    assert_equal ["Ada", "Artificial Intelligence", "Editorial team", "Engineering", "essays"].sort,
      topics.map { |topic| topic.fetch("name") }.sort
    assert_equal "/people/Ada/", topics.find { |topic| topic.fetch("name") == "Ada" }.fetch("url")
    assert_equal "/AI/", topics.find { |topic| topic.fetch("name") == "Artificial Intelligence" }.fetch("url")
    assert_equal %w[AI.md people/Ada.md], result.relations
      .select { |relation| relation.source_id == "blog/post.md" }
      .map(&:target_id)
      .sort

    note_page = page(result, "/blog/post/").data.fetch("website")
    assert_equal "A field note about software", note_page.fetch("subtitle")
    assert_equal [
      { "kind" => "author", "name" => "Ada", "url" => "/people/Ada/" },
      { "kind" => "author", "name" => "Editorial team" }
    ], note_page.fetch("authors")
    refute note_page.key?("author")
    assert_equal ["[[AI]]", "Engineering"], note_page.fetch("categories")
  end

  def test_frontmatter_topic_fields_are_arrays_and_wiki_links_require_double_quotes
    scalar = compile(note("index.md", "---\npublish: true\nauthor: Ada\ncategories: Engineering\n---\n# Home"))
    refute scalar.success?
    assert_equal 2, scalar.diagnostics.count { |item| item.code == "invalid_property" }

    single_quoted = compile(note("index.md", "---\npublish: true\nauthor:\n  - '[[Ada]]'\n---\n# Home"))
    refute single_quoted.success?
    assert(single_quoted.diagnostics.any? do |item|
      item.code == "invalid_property" && item.message == "author wiki link entries must use double-quoted YAML strings"
    end)

    malformed = compile(note("index.md", "---\npublish: true\ncategories:\n  - \"[[AI|]]\"\n---\n# Home"))
    refute malformed.success?
    assert malformed.diagnostics.any? { |item| item.message == "categories wiki links must use [[target]] or [[target|label]] syntax" }
  end

  def test_blog_uses_note_id_to_break_equal_dates_and_archives_undated_development_posts
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("blog/alpha.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-01\nupdated: 2026-07-02\n---\n# Alpha"),
      note("blog/zulu.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-01\nupdated: 2026-07-02\n---\n# Zulu"),
      note("blog/undated.md", "---\npublish: true\ncontent_type: post\n---\n# Undated")
    ]

    result = compile(*entries.reverse, theme: "minimal", environment: "development")

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    recent = page(result, "/").data.dig("website", "theme_data", "recent_posts")
    assert_equal %w[blog/zulu.md blog/alpha.md blog/undated.md], recent.map { |post| post.fetch("id") }

    archive = page(result, "/blog/").data.dig("website", "theme_data", "archive_groups")
    assert_equal %w[2026 Undated], archive.map { |group| group.fetch("label") }
    assert_equal %w[blog/zulu.md blog/alpha.md], archive.first.fetch("posts").map { |post| post.fetch("id") }
    assert_equal ["blog/undated.md"], archive.last.fetch("posts").map { |post| post.fetch("id") }
  end

  def test_minimal_pins_post_cards_before_reverse_chronology
    entries = (1..7).map do |day|
      pinned = day == 1 ? "pinned: true\n" : ""
      note(
        "blog/post-#{day}.md",
        "---\npublish: true\ncontent_type: post\ndate: 2026-07-#{format('%02d', day)}\n#{pinned}---\n# Post #{day}"
      )
    end

    result = compile(*entries.reverse, theme: "minimal")

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    recent = page(result, "/").data.dig("website", "theme_data", "recent_posts")
    assert_equal %w[blog/post-1.md blog/post-7.md blog/post-6.md blog/post-5.md blog/post-4.md blog/post-3.md],
      recent.map { |post| post.fetch("id") }
    archive = page(result, "/blog/").data.dig("website", "theme_data", "archive_groups")
    assert_equal "blog/post-1.md", archive.first.fetch("posts").first.fetch("id")
    assert_nil page(result, "/blog/post-1/").data.dig("website", "theme_data", "previous")
    assert_equal "blog/post-2.md", page(result, "/blog/post-1/").data.dig("website", "theme_data", "next", "id")
    feed = result.generated_files.find { |file| file.route == "/feed.xml" }.content
    assert_operator feed.index("<title>Post 7</title>"), :<, feed.index("<title>Post 1</title>")
  end

  def test_minimal_home_combines_authored_content_six_recent_posts_and_contacts
    entries = [
      note(
        "index.md",
        "---\npublish: true\nupdated: 2026-07-30\nimage: media/cover.png\ncssclasses: [authored-home]\n---\n# Hidden landing copy\n\n## Start here\n\n[[blog/post-12]]"
      ),
      attachment("media/cover.png", "cover", media_type: "image/png")
    ]
    entries.concat((1..12).map do |day|
      note(
        "blog/post-#{day}.md",
        "---\npublish: true\ncontent_type: post\ndate: 2026-07-#{format('%02d', day)}\ndescription: Summary #{day}\n---\n# Post #{day}"
      )
    end)
    contacts = [
      { "label" => "GitHub", "url" => "https://github.com/example" },
      { "label" => "Email", "url" => "mailto:hello@example.test" }
    ]

    result = compile(*entries, theme: "minimal", contacts: contacts)

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    home = page(result, "/")
    assert_equal "home", home.data.dig("website", "kind")
    assert_includes home.content, "Hidden landing copy"
    assert_equal 6, home.data.dig("website", "theme_data", "recent_posts").length
    assert_equal %w[blog/post-12.md blog/post-11.md], home.data.dig("website", "theme_data", "recent_posts").first(2).map { |post| post.fetch("id") }
    assert_equal "Summary 12", home.data.dig("website", "theme_data", "recent_posts", 0, "summary")
    assert_equal [
      { "label" => "GitHub", "url" => "https://github.com/example", "icon" => "github" },
      { "label" => "Email", "url" => "mailto:hello@example.test", "icon" => "email" }
    ], home.data.dig("website", "theme_data", "contacts")
    assert_equal "https://example.test/assets/vault/media/cover.png", home.data.fetch("image")
    assert_equal ["authored-home"], home.data.dig("website", "cssclasses")
    assert_equal "index.md", home.data.dig("website", "local_graph", "current_id")
    assert home.data.dig("website", "outline").any? { |item| item.fetch("label") == "Start here" }
    assert home.data.dig("website", "links").any? { |item| item.fetch("id") == "blog/post-12.md" }
    assert_equal true, home.data.dig("website", "has_context")
    assert_includes home.data.dig("website", "source_links", "source"), "vault/index.md"
    assert_equal 12, page(result, "/blog/").data.dig("website", "theme_data", "archive_groups", 0, "posts").length
    assert_nil page(result, "/page/2/")
    assert_nil page(result, "/archive/")
    refute_includes result.pages.map(&:route), "/index/"
  end

  def test_minimal_authored_portfolio_keeps_the_note_and_projects_cards_after_its_intro
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note(
        "portfolio/index.md",
        "---\npublish: true\n---\n# Selected work\n\nAn authored introduction."
      ),
      note(
        "portfolio/featured.md",
        "---\npublish: true\nnav_order: 1\ndescription: Front matter summary\nimage: media/demo.gif\n---\n# Featured project\n\nThis preview must not replace the description."
      ),
      note(
        "portfolio/preview.md",
        "---\npublish: true\ntitle: Preview project\nnav_order: 2\npinned: true\n---\nPreview from the project body."
      ),
      note("portfolio/hidden.md", "---\npublish: true\nnav_exclude: true\n---\n# Hidden project"),
      attachment("media/demo.gif", "GIF89a", media_type: "image/gif"),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    portfolio = page(result, "/portfolio/")
    assert_equal "note", portfolio.data.dig("website", "kind")
    assert_includes portfolio.content, "An authored introduction."
    assert portfolio.data.dig("website", "source_links", "edit")
    assert_equal [
      {
        "id" => "portfolio/preview.md",
        "title" => "Preview project",
        "url" => "/portfolio/preview/",
        "image" => nil,
        "summary" => "Preview from the project body."
      },
      {
        "id" => "portfolio/featured.md",
        "title" => "Featured project",
        "url" => "/portfolio/featured/",
        "image" => "https://example.test/assets/vault/media/demo.gif",
        "summary" => "Front matter summary"
      }
    ], portfolio.data.dig("website", "theme_data", "portfolio_projects")
  end

  def test_minimal_generates_a_portfolio_index_without_exposing_note_actions
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("work/alpha.md", "---\npublish: true\ndescription: Alpha summary\n---\n# Alpha"),
      note("work/beta.md", "---\npublish: true\n---\n# Beta"),
      theme: "minimal",
      baseurl: "/site",
      navigation: {
        "portfolio" => { "path" => "work", "label" => "Case studies", "visible" => false }
      }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    portfolio = page(result, "/work/")
    assert_equal "portfolio-index", portfolio.data.dig("website", "kind")
    assert_equal "Case studies", portfolio.data.fetch("title")
    assert_equal "/site/work/", portfolio.data.dig("website", "routes", "portfolio")
    refute portfolio.data.fetch("website").key?("id")
    refute portfolio.data.fetch("website").key?("markdown_url")
    refute portfolio.data.fetch("website").key?("source_links")
    refute portfolio.data.fetch("website").key?("comments")
    refute portfolio.data.dig("website", "navigation").any? { |item| item.fetch("id") == "portfolio" }
    assert_equal %w[work/alpha.md work/beta.md], portfolio.data.dig(
      "website", "theme_data", "portfolio_projects"
    ).map { |project| project.fetch("id") }
    assert_equal "/site/work/alpha/", portfolio.data.dig(
      "website", "theme_data", "portfolio_projects", 0, "url"
    )
  end

  def test_minimal_root_fallback_reaches_a_hidden_portfolio_without_replacing_an_authored_root_route
    hidden_portfolio = compile(
      note("work/alpha.md", "---\npublish: true\n---\n# Alpha"),
      theme: "minimal",
      navigation: {
        "portfolio" => { "path" => "work", "label" => "Case studies", "visible" => false }
      }
    )

    assert hidden_portfolio.success?, hidden_portfolio.diagnostics.map(&:message).join("\n")
    redirect = page(hidden_portfolio, "/")
    assert_equal "redirect", redirect.data.dig("website", "kind")
    assert_equal "portfolio", redirect.data.dig("website", "redirect_navigation_id")
    assert_equal "/work/", redirect.data.dig("website", "redirect_url")
    assert_equal "https://example.test/work/", redirect.data.dig("website", "canonical_url")

    authored_root = compile(
      note(
        "landing.md",
        "---\npublish: true\npermalink: /\n---\n# Authored landing"
      ),
      note("blog/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-08-07\n---\n# Post"),
      theme: "minimal"
    )

    assert authored_root.success?, authored_root.diagnostics.map(&:message).join("\n")
    assert_equal 1, authored_root.pages.count { |candidate| candidate.route == "/" }
    assert_equal "note", page(authored_root, "/").data.dig("website", "kind")
  end

  def test_contacts_reject_unknown_shapes_and_unsafe_urls
    home = note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home")

    invalid_list = compile(home, theme: "minimal", contacts: "https://example.test")
    refute invalid_list.success?
    assert invalid_list.diagnostics.any? { |item| item.code == "invalid_contacts" }

    unsafe_url = compile(home, theme: "minimal", contacts: [{ "label" => "Run", "url" => "javascript:alert(1)" }])
    refute unsafe_url.success?
    assert unsafe_url.diagnostics.any? { |item| item.code == "invalid_contacts" }
  end

  def test_contacts_project_stable_icons_without_expanding_the_configuration_shape
    home = note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home")
    contacts = [
      { "label" => "Phone", "url" => "tel:+12025550123" },
      { "label" => "LinkedIn", "url" => "https://www.linkedin.com/in/example" },
      { "label" => "X", "url" => "https://twitter.com/example" },
      { "label" => "Mastodon", "url" => "https://social.example/@example" },
      { "label" => "Bluesky", "url" => "https://bsky.app/profile/example.test" },
      { "label" => "Instagram", "url" => "https://instagram.com/example" },
      { "label" => "YouTube", "url" => "https://youtu.be/example" },
      { "label" => "Telegram", "url" => "https://t.me/example" },
      { "label" => "Syndication", "url" => "https://example.test/feed.xml" },
      { "label" => "Website", "url" => "https://example.test" },
      { "label" => "Community", "url" => "https://community.example.test" }
    ]

    result = compile(home, theme: "minimal", contacts: contacts)

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    projected = page(result, "/").data.dig("website", "theme_data", "contacts").map do |contact|
      [contact.fetch("label"), contact["icon"]]
    end
    assert_equal [
      ["Phone", "phone"],
      ["LinkedIn", "linkedin"],
      ["X", "x"],
      ["Mastodon", "mastodon"],
      ["Bluesky", "bluesky"],
      ["Instagram", "instagram"],
      ["YouTube", "youtube"],
      ["Telegram", "telegram"],
      ["Syndication", "rss"],
      ["Website", "website"],
      ["Community", nil]
    ], projected
  end

  def test_theme_projection_is_deeply_immutable_and_deterministic_through_compile
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n[[blog/post]]"),
      note("blog/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-01\nupdated: 2026-07-02\n---\n# Post")
    ]

    first = compile(*entries, theme: "minimal")
    second = compile(*entries.reverse, theme: "minimal")

    assert_equal first, second
    assert_raises(FrozenError) do
      page(first, "/").data.dig("website", "theme_data", "recent_posts") << { "id" => "mutated.md" }
    end
    assert_raises(FrozenError) { first.relations.first.source_id.replace("mutated.md") }
  end

  def test_docs_builds_flat_root_tree_and_navigation_from_visible_docs
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
    tree = page(result, "/").data.dig("website", "theme_data", "docs_tree")
    assert_equal %w[docs/install.md docs/reference.md], tree.map { |node| node.fetch("id") }
    assert_equal "/docs/", page(result, "/").data.dig("website", "theme_data", "docs_home_url")

    reference_data = page(result, "/docs/reference/").data.dig("website", "theme_data")
    refute reference_data.key?("breadcrumbs")
    assert_equal "docs/install.md", reference_data.fetch("previous").fetch("id")
    assert_nil reference_data.fetch("next")

    manual_data = page(result, "/docs/").data.dig("website", "theme_data")
    assert_nil manual_data.fetch("previous")
    assert_equal "docs/install.md", manual_data.fetch("next").fetch("id")
  end

  def test_docs_folders_without_landings_link_to_their_first_ordered_page
    missing = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("docs/guides/later.md", "---\npublish: true\nnav_order: 20\nupdated: 2026-07-30\n---\n# Later"),
      note("docs/guides/first.md", "---\npublish: true\nnav_order: 10\nupdated: 2026-07-30\n---\n# First"),
      theme: "docs"
    )
    tree = page(missing, "/").data.dig("website", "theme_data", "docs_tree")
    assert_equal "folder:guides", tree.first.fetch("id")
    assert_equal "/docs/guides/first/", tree.first.fetch("url")
    assert_equal %w[docs/guides/first.md docs/guides/later.md], tree.first.fetch("children").map { |node| node.fetch("id") }
    assert_equal "/docs/guides/first/", page(missing, "/").data.dig("website", "theme_data", "docs_home_url")

    hidden = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("docs/index.md", "---\npublish: true\nnav_exclude: true\nupdated: 2026-07-30\n---\n# Hidden manual"),
      note("docs/child.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Child"),
      theme: "docs"
    )
    hidden_root = page(hidden, "/").data.dig("website", "theme_data", "docs_tree").first
    assert_equal "docs/child.md", hidden_root.fetch("id")
    assert_equal "/docs/child/", hidden_root.fetch("url")
    assert_equal "/docs/child/", page(hidden, "/").data.dig("website", "theme_data", "docs_home_url")

    no_docs = compile(note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"), theme: "docs")
    assert_nil page(no_docs, "/").data.dig("website", "theme_data", "docs_home_url")
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
      pinned: "true"
      ---
      # Home
    MARKDOWN

    refute invalid.success?
    assert_operator invalid.diagnostics.count { |item| item.code == "invalid_property" }, :>=, 5

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
    assert_includes html, "website-link"
    assert_includes html, "website-transclusion"
    assert_includes html, "website-callout"
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

    minimal = compile(
      home,
      *candidates,
      note("page/3.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Page three"),
      theme: "minimal"
    )
    assert minimal.success?, minimal.diagnostics.map(&:message).join("\n")
    assert_equal %w[/archive/ /graph/ /notes/ /tags/], candidates.map { |entry| page(minimal, "/#{File.basename(entry.path, '.md')}/").route }
    assert page(minimal, "/page/3/")
    assert_nil page(minimal, "/blog/")

    collision = compile(
      home,
      note("blog.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Authored blog"),
      note("posts/entry.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-30\n---\n# Entry"),
      theme: "minimal"
    )
    refute collision.success?
    assert collision.diagnostics.any? { |item| item.code == "route_collision" }
  end

  def test_docs_pages_embed_the_complete_navigation_tree
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("docs/index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Docs"),
      note("docs/a/one.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# One"),
      note("docs/b/two.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Two"),
      theme: "docs"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    branch = page(result, "/docs/a/one/").data.dig("website", "theme_data", "docs_tree")
    ids = []
    collect_ids = lambda do |nodes|
      nodes.each do |node|
        ids << node.fetch("id")
        collect_ids.call(node.fetch("children"))
      end
    end
    collect_ids.call(branch)
    assert_includes ids, "docs/a/one.md"
    assert_includes ids, "docs/b/two.md"
    refute result.generated_files.any? { |file| file.route.end_with?("/docs-navigation.html") }
  end

  def test_graph_projects_complete_global_data_and_one_hop_local_graphs
    %w[minimal docs].each do |theme|
      result = compile(
        note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n[[a]]\n[[b]]"),
        note("a.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Alpha\n[[b]]"),
        note("b.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Beta"),
        note("isolated.md", "---\npublish: true\ntitle: Isolated\nupdated: 2026-07-30\n---\nIsolated body."),
        note("private.md", "---\npublish: false\n---\n# Private\n[[index]]"),
        theme: theme
      )
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      assert_nil page(result, "/graph/")

      graph = generated_json(result, "/assets/website/graph.v1.json")
      assert_equal %w[a.md b.md index.md isolated.md], graph.fetch("nodes").map { |node| node.fetch("id") }
      assert_equal({ "a.md" => 2, "b.md" => 2, "index.md" => 2, "isolated.md" => 0 }, graph.fetch("nodes").to_h { |node| [node.fetch("id"), node.fetch("degree")] })

      home_graph = page(result, "/").data.dig("website", "local_graph")
      assert_equal "index.md", home_graph.fetch("current_id")
      assert_equal %w[a.md b.md index.md], home_graph.fetch("nodes").map { |node| node.fetch("id") }
      assert_equal 2, home_graph.fetch("edges").length

      alpha_graph = page(result, "/a/").data.dig("website", "local_graph")
      assert_equal %w[a.md b.md index.md], alpha_graph.fetch("nodes").map { |node| node.fetch("id") }
      assert_equal 2, alpha_graph.fetch("edges").length

      isolated = page(result, "/isolated/")
      assert_nil isolated.data.dig("website", "local_graph"), theme
      assert_equal false, isolated.data.dig("website", "has_context"), theme
    end
  end

  def test_embed_relations_enable_local_graphs_but_self_links_do_not
    %w[minimal docs].each do |theme|
      result = compile(
        note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
        note("embed-source.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Embed source\n![[embed-target]]"),
        note("embed-target.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Embed target"),
        note("self.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Self\n[[self]]"),
        theme: theme
      )
      assert result.success?, result.diagnostics.map(&:message).join("\n")

      source_graph = page(result, "/embed-source/").data.dig("website", "local_graph")
      target_graph = page(result, "/embed-target/").data.dig("website", "local_graph")
      assert_equal "embed-source.md", source_graph.fetch("current_id")
      assert_equal "embed-target.md", target_graph.fetch("current_id")
      assert_equal %w[embed-source.md embed-target.md], source_graph.fetch("nodes").map { |node| node.fetch("id") }
      assert_equal %w[embed-source.md embed-target.md], target_graph.fetch("nodes").map { |node| node.fetch("id") }
      assert_equal ["embed"], source_graph.fetch("edges").map { |edge| edge.fetch("kind") }
      assert_equal source_graph.fetch("edges"), target_graph.fetch("edges"), theme

      self_page = page(result, "/self/")
      assert_nil self_page.data.dig("website", "local_graph"), theme

      graph = generated_json(result, "/assets/website/graph.v1.json")
      assert_includes graph.fetch("nodes").map { |node| node.fetch("id") }, "self.md", theme
      assert graph.fetch("edges").any? { |edge| edge.fetch("source") == "self.md" && edge.fetch("target") == "self.md" }, theme
    end
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

    %w[404.html sitemap.xml assets/website/private assets/vault/private].each do |path|
      result = compile(home, note("#{path}.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Reserved"), theme: "docs")
      refute result.success?, "expected /#{path}/ to remain reserved"
      assert result.diagnostics.any? { |item| item.code == "route_collision" }
    end
  end
end
