# frozen_string_literal: true

require "test_helper"

class CommentsTest < Minitest::Test
  COMMENT_IDS = {
    "repository_id" => "R_kgDOExample",
    "category" => "Blog comments",
    "category_id" => "DIC_kwDOExample"
  }.freeze
  COMMENTS = COMMENT_IDS.merge("enabled" => true).freeze

  def test_blog_projects_comments_only_for_enabled_posts
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-08-03\n---\n# Home"),
      note("blog/open.md", "---\npublish: true\ncontent_type: post\ndate: 2026-08-01\n---\n# Open"),
      note("blog/closed.md", "---\npublish: true\ncontent_type: post\ndate: 2026-08-02\ncomments: false\n---\n# Closed"),
      note("about.md", "---\npublish: true\nupdated: 2026-08-03\ncomments: true\n---\n# About"),
      theme: "minimal",
      lang: "zh-CN",
      comments: COMMENT_IDS
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal(
      {
        "configured" => true,
        "repository" => "example/garden",
        "repository_id" => "R_kgDOExample",
        "category" => "Blog comments",
        "category_id" => "DIC_kwDOExample",
        "term" => "website:post:blog/open",
        "language" => "zh-CN",
        "load" => true,
        "repository_url" => "https://github.com/example/garden",
        "discussion_url" => "https://github.com/example/garden/discussions"
      },
      page(result, "/blog/open/").data.dig("website", "comments")
    )
    assert_nil page(result, "/blog/closed/").data.dig("website", "comments")
    assert_nil page(result, "/about/").data.dig("website", "comments")
    assert_nil page(result, "/").data.dig("website", "comments")
    assert_nil page(result, "/blog/").data.dig("website", "comments")
  end

  def test_theme_defaults_can_be_overridden_for_every_theme
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-08-03\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-08-01\n---\n# Post")
    ]

    %w[docs].each do |theme|
      disabled = compile(*entries, theme: theme, comments: COMMENT_IDS)
      assert disabled.success?, disabled.diagnostics.map(&:message).join("\n")
      assert_nil page(disabled, "/blog/post/").data.dig("website", "comments"), theme

      enabled = compile(*entries, theme: theme, comments: COMMENTS)
      assert enabled.success?, enabled.diagnostics.map(&:message).join("\n")
      assert_equal "website:post:blog/post", page(enabled, "/blog/post/").data.dig("website", "comments", "term"), theme
    end

    blog = compile(*entries, theme: "minimal", comments: COMMENT_IDS.merge("enabled" => false))
    assert blog.success?, blog.diagnostics.map(&:message).join("\n")
    assert_nil page(blog, "/blog/post/").data.dig("website", "comments")
  end

  def test_comments_repository_override_language_fallback_and_development_state
    configured = COMMENTS.merge("repository" => "example/community")
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-08-03\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-08-01\n---\n# Post"),
      theme: "minimal",
      lang: "en-GB",
      environment: "development",
      comments: configured
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    comments = page(result, "/blog/post/").data.dig("website", "comments")
    assert_equal "example/community", comments.fetch("repository")
    assert_equal "https://github.com/example/community/discussions", comments.fetch("discussion_url")
    assert_equal "en", comments.fetch("language")
    assert_equal false, comments.fetch("load")
  end

  def test_enabled_comments_degrade_when_github_setup_is_incomplete
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-08-03\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-08-01\n---\n# Post"),
      theme: "minimal",
      comments: { "enabled" => true }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert result.diagnostics.any? { |item| item.code == "comments_unconfigured" && item.severity == :warning }
    comments = page(result, "/blog/post/").data.dig("website", "comments")
    assert_equal false, comments.fetch("configured")
    assert_equal false, comments.fetch("load")
    assert_equal "https://github.com/example/garden/discussions", comments.fetch("discussion_url")
  end

  def test_localized_comment_pages_use_their_locale_language_and_shared_thread
    entries = [
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-08-01\n---\n# Post"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("_translations/zh-CN/blog/post.md", "---\npublish: true\n---\n# 文章")
    ]
    result = compile(
      *entries,
      theme: "docs",
      comments: COMMENTS,
      i18n: { "locales" => %w[en zh-CN] }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    default_comments = page(result, "/blog/post/").data.dig("website", "comments")
    localized_comments = page(result, "/zh-CN/blog/post/").data.dig("website", "comments")
    assert_equal "en", default_comments.fetch("language")
    assert_equal "zh-CN", localized_comments.fetch("language")
    assert_equal default_comments.fetch("term"), localized_comments.fetch("term")
  end

  def test_thread_term_is_independent_of_origin_and_baseurl
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-08-03\n---\n# Home"),
      note("blog/中文.md", "---\npublish: true\ncontent_type: post\ndate: 2026-08-01\n---\n# 中文")
    ]
    first = compile(*entries, theme: "minimal", comments: COMMENTS)
    second = compile(
      *entries,
      theme: "minimal",
      url: "https://other.example",
      baseurl: "/manual",
      comments: COMMENTS
    )

    assert first.success?
    assert second.success?
    assert_equal(
      "website:post:blog/中文",
      page(first, "/blog/%E4%B8%AD%E6%96%87/").data.dig("website", "comments", "term")
    )
    assert_equal(
      page(first, "/blog/%E4%B8%AD%E6%96%87/").data.dig("website", "comments", "term"),
      page(second, "/blog/%E4%B8%AD%E6%96%87/").data.dig("website", "comments", "term")
    )
  end

  def test_comments_config_fails_closed
    home = note("index.md", "---\npublish: true\nupdated: 2026-08-03\n---\n# Home")
    cases = [
      ["mapping", "must be a mapping", theme: "minimal", comments: true],
      ["unknown setting", "unknown comments setting", theme: "minimal", comments: { "surprise" => true }],
      ["boolean", "YAML boolean", theme: "minimal", comments: COMMENTS.merge("enabled" => "true")],
      ["repository", "owner/repository", theme: "minimal", repository: "", comments: COMMENTS],
      ["repository id type", "repository_id must be a string", theme: "minimal", comments: COMMENTS.merge("repository_id" => true)],
      ["category type", "category must be a string", theme: "minimal", comments: COMMENTS.merge("category" => true)],
      ["category id type", "category_id must be a string", theme: "minimal", comments: COMMENTS.merge("category_id" => true)]
    ]

    cases.each do |label, message, overrides|
      result = compile(home, **overrides)
      refute result.success?, "#{label} unexpectedly compiled"
      assert result.diagnostics.any? { |item| item.code == "invalid_comments" && item.message.include?(message) }, label
    end
  end

  def test_comments_frontmatter_must_be_a_yaml_boolean
    invalid = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-08-03\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-08-01\ncomments: \"yes\"\n---\n# Post"),
      theme: "minimal",
      comments: COMMENTS
    )

    refute invalid.success?
    assert invalid.diagnostics.any? { |item| item.code == "invalid_comments" && item.path == "blog/post.md" }
  end
end
