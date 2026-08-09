# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "test_helper"

class GitHubMarkdownCompilationTest < Minitest::Test
  COMMIT = "0123456789abcdef0123456789abcdef01234567"

  def setup
    @temporary_root = Dir.mktmpdir("github-markdown-compilation")
    @transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(commits: {}, files: {})
  end

  def teardown
    FileUtils.remove_entry(@temporary_root) if File.exist?(@temporary_root)
  end

  def test_imported_markdown_replaces_the_wrapper_body_and_uses_a_safe_remote_profile
    remote = <<~MARKDOWN
      # Imported project

      <script>alert("unsafe")</script>

      [[Local note]]

      [Guide](guide.md), [license](../LICENSE), [version docs](v1.0/), and [section](#details).

      ![Screenshot](assets/screen.gif)

      ## Details

      Remote details.
    MARKDOWN
    @transport = transport_for(
      { ["acme/widget", "main"] => COMMIT },
      { ["acme/widget", COMMIT, "docs/README.md"] => remote }
    )

    result = compile_site(
      note(
        "portfolio/widget.md",
        <<~MARKDOWN
          ---
          publish: true
          title: Local card title
          description: Local card description
          categories: [Rust, TypeScript]
          github_markdown:
            repository: acme/widget
            ref: main
            path: docs/README.md
          ---
        MARKDOWN
      ),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    detail = page(result, "/portfolio/widget/")
    assert_equal 1, detail.content.scan("<h1").length
    assert_includes detail.content, "Imported project"
    assert_includes detail.content, "[[Local note]]"
    refute_includes detail.content, "<script"
    assert_includes detail.content, "https://github.com/acme/widget/blob/#{COMMIT}/docs/guide.md"
    assert_includes detail.content, "https://github.com/acme/widget/blob/#{COMMIT}/LICENSE"
    assert_includes detail.content, "https://github.com/acme/widget/tree/#{COMMIT}/docs/v1.0"
    assert_includes detail.content, 'href="#details"'
    assert_includes detail.content, "https://raw.githubusercontent.com/acme/widget/#{COMMIT}/docs/assets/screen.gif"
    assert_empty result.relations
    assert_equal "https://github.com/acme/widget/blob/#{COMMIT}/docs/README.md",
      detail.data.dig("website", "source_links", "imported")
    assert_equal "https://github.com/acme/widget",
      detail.data.dig("website", "source_links", "repository")
    assert_includes detail.data.dig("website", "source_links", "edit"), "portfolio/widget.md"
    assert_equal %w[Rust TypeScript], detail.data.dig(
      "website", "theme_data", "portfolio_topics"
    ).map { |topic| topic.fetch("name") }

    card = page(result, "/portfolio/").data.dig("website", "theme_data", "portfolio_projects").fetch(0)
    assert_equal "Local card title", card.fetch("title")
    assert_equal "Local card description", card.fetch("summary")
    assert_equal "https://github.com/acme/widget", card.fetch("repository_url")
    markdown = result.generated_files.find { |file| file.route == "/portfolio/widget.md" }.content
    assert_includes markdown, "https://github.com/acme/widget/blob/#{COMMIT}/docs/guide.md"
    assert_includes markdown, "https://raw.githubusercontent.com/acme/widget/#{COMMIT}/docs/assets/screen.gif"
  end

  def test_imported_wrapper_frontmatter_can_publish_related_articles
    @transport = transport_for(
      { ["acme/widget", "main"] => COMMIT },
      { ["acme/widget", COMMIT, "README.md"] => "# Imported project\n" }
    )

    result = compile_site(
      note(
        "portfolio/widget.md",
        <<~MARKDOWN
          ---
          publish: true
          github_markdown: https://github.com/acme/widget/blob/main/README.md
          related:
            - "[[blog/launch|Launch story]]"
          ---
        MARKDOWN
      ),
      note(
        "blog/launch.md",
        "---\npublish: true\ncontent_type: post\ndate: 2026-08-09\n---\n# Launch\n"
      ),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    related = page(result, "/portfolio/widget/").data.dig("website", "related_articles")
    assert_equal [{ "id" => "blog/launch.md", "title" => "Launch story", "url" => "/blog/launch/" }],
      related.map { |article| article.slice("id", "title", "url") }
    relation = result.relations.find do |item|
      item.source_id == "portfolio/widget.md" && item.target_id == "blog/launch.md"
    end
    refute_nil relation
    assert_equal :link, relation.kind
    assert_equal "related", relation.property
    assert_equal ["portfolio/widget.md"],
      page(result, "/blog/launch/").data.dig("website", "backlinks").map { |link| link.fetch("id") }
  end

  def test_scope_and_body_conflicts_fail_before_network_access_while_drafts_are_ignored
    cases = {
      "outside.md" => [
        <<~MARKDOWN,
          ---
          publish: true
          github_markdown: https://github.com/acme/widget/blob/main/README.md
          ---
        MARKDOWN
        "github_markdown_scope"
      ],
      "portfolio/index.md" => [
        <<~MARKDOWN,
          ---
          publish: true
          github_markdown: https://github.com/acme/widget/blob/main/README.md
          ---
        MARKDOWN
        "github_markdown_scope"
      ],
      "portfolio/body.md" => [
        <<~MARKDOWN,
          ---
          publish: true
          github_markdown: https://github.com/acme/widget/blob/main/README.md
          ---
          Local body is not allowed.
        MARKDOWN
        "github_markdown_body_conflict"
      ]
    }

    cases.each do |path, (bytes, code)|
      @transport = transport_for({}, {})
      result = compile_site(
        note("index.md", "---\npublish: true\n---\n# Home\n"),
        note(path, bytes),
        theme: "minimal"
      )

      refute result.success?, path
      assert result.diagnostics.any? { |item| item.code == code && item.path == path }, path
      assert_empty @transport.resolve_calls, path
      assert_empty @transport.fetch_calls, path
    end

    @transport = transport_for({}, {})
    draft = compile_site(
      note("index.md", "---\npublish: true\n---\n# Home\n"),
      note(
        "portfolio/draft.md",
        "---\npublish: false\ngithub_markdown: https://github.com/acme/widget/blob/main/README.md\n---\n"
      ),
      theme: "minimal"
    )
    assert draft.success?, draft.diagnostics.map(&:message).join("\n")
    assert_empty @transport.resolve_calls
    assert_nil page(draft, "/portfolio/draft/")
  end

  def test_docs_theme_can_render_an_import_without_claiming_portfolio_navigation
    @transport = transport_for(
      { ["acme/widget", "release/v2"] => COMMIT },
      { ["acme/widget", COMMIT, "README.markdown"] => "# Docs project\n" }
    )
    result = compile_site(
      note(
        "work/widget.md",
        <<~MARKDOWN
          ---
          publish: true
          github_markdown:
            repository: acme/widget
            ref: release/v2
            path: README.markdown
          ---
        MARKDOWN
      ),
      theme: "docs",
      navigation: { "portfolio" => { "path" => "work" } },
      content: { "default_type" => "doc", "directories" => { "doc" => ["work"], "post" => [] } }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    detail = page(result, "/work/widget/")
    assert_includes detail.content, "Docs project"
    refute detail.data.dig("website", "routes").key?("portfolio")
    refute detail.data.dig("website", "navigation").any? { |item| item.fetch("id") == "portfolio" }
    assert_equal "doc", detail.data.dig("website", "content_type")
  end

  def test_relative_paths_must_remain_inside_the_remote_repository
    @transport = transport_for(
      { ["acme/widget", "main"] => COMMIT },
      { ["acme/widget", COMMIT, "docs/README.md"] => "[Escape](../../outside.md)\n" }
    )
    result = compile_site(
      note(
        "portfolio/widget.md",
        <<~MARKDOWN
          ---
          publish: true
          github_markdown:
            repository: acme/widget
            ref: main
            path: docs/README.md
          ---
        MARKDOWN
      ),
      theme: "minimal"
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "invalid_github_markdown_link" }
  end

  def test_imported_duplicate_headings_keep_github_fragment_ids
    @transport = transport_for(
      { ["acme/widget", "main"] => COMMIT },
      {
        ["acme/widget", COMMIT, "README.md"] => <<~MARKDOWN
          # Widget

          [Second setup](#setup-1)

          ## Setup

          First.

          ## Setup

          Second.
        MARKDOWN
      }
    )

    result = compile_site(
      note(
        "portfolio/widget.md",
        "---\npublish: true\ngithub_markdown: https://github.com/acme/widget/blob/main/README.md\n---\n"
      ),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    content = page(result, "/portfolio/widget/").content
    assert_includes content, 'href="#setup-1"'
    assert_includes content, 'id="setup"'
    assert_includes content, 'id="setup-1"'
    refute_includes content, 'id="setup-2"'
  end

  def test_imported_images_must_use_https
    @transport = transport_for(
      { ["acme/widget", "main"] => COMMIT },
      { ["acme/widget", COMMIT, "README.md"] => "![Insecure](http://example.test/image.png)\n" }
    )

    result = compile_site(
      note(
        "portfolio/widget.md",
        "---\npublish: true\ngithub_markdown: https://github.com/acme/widget/blob/main/README.md\n---\n"
      ),
      theme: "minimal"
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "invalid_github_markdown_image" }
  end

  def test_imported_absolute_https_links_can_use_unicode_fragments
    url = "https://docs.github.com/zh/pages/quickstart#谁可以使用此功能"
    rendered_url = "https://docs.github.com/zh/pages/quickstart#%E8%B0%81%E5%8F%AF%E4%BB%A5%E4%BD%BF%E7%94%A8%E6%AD%A4%E5%8A%9F%E8%83%BD"
    @transport = transport_for(
      { ["acme/widget", "main"] => COMMIT },
      { ["acme/widget", COMMIT, "README.md"] => "[中文指南](#{url})\n" }
    )

    result = compile_site(
      note(
        "portfolio/widget.md",
        "---\npublish: true\ngithub_markdown: https://github.com/acme/widget/blob/main/README.md\n---\n"
      ),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_includes page(result, "/portfolio/widget/").content, %(href="#{rendered_url}")
  end

  def test_locales_use_their_own_import_and_missing_translations_reuse_the_default_document
    @transport = transport_for(
      { ["acme/widget", "main"] => COMMIT },
      {
        ["acme/widget", COMMIT, "README.md"] => "# English import\n",
        ["acme/widget", COMMIT, "README.zh-CN.md"] => "# 中文导入\n",
        ["acme/widget", COMMIT, "FALLBACK.md"] => "# Default fallback\n"
      }
    )
    entries = [
      note(
        "portfolio/widget.md",
        "---\npublish: true\ngithub_markdown: https://github.com/acme/widget/blob/main/README.md\n---\n"
      ),
      note(
        "portfolio/fallback.md",
        "---\npublish: true\ngithub_markdown: https://github.com/acme/widget/blob/main/FALLBACK.md\n---\n"
      ),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest(
        "_translations/zh-CN/_locale.yml",
        "name: 简体中文\nhreflang: zh-Hans\ndir: ltr\n"
      ),
      note(
        "_translations/zh-CN/portfolio/widget.md",
        "---\npublish: true\ngithub_markdown: https://github.com/acme/widget/blob/main/README.zh-CN.md\n---\n"
      )
    ]

    result = compile_site(
      *entries,
      theme: "minimal",
      i18n: { "enabled" => true, "locales" => %w[en zh-CN] }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    default = page(result, "/portfolio/widget/")
    translated = page(result, "/zh-CN/portfolio/widget/")
    fallback = page(result, "/zh-CN/portfolio/fallback/")
    assert_includes default.content, "English import"
    assert_includes translated.content, "中文导入"
    assert_equal "https://github.com/acme/widget/blob/#{COMMIT}/README.zh-CN.md",
      translated.data.dig("website", "source_links", "imported")
    assert_equal "https://github.com/acme/widget",
      translated.data.dig("website", "source_links", "repository")
    assert_includes translated.data.dig("website", "source_links", "edit"),
      "_translations/zh-CN/portfolio/widget.md"
    assert_includes fallback.content, "Default fallback"
    assert_equal true, fallback.data.dig("website", "i18n", "fallback")
    assert_equal "noindex", fallback.data.dig("website", "robots")
    assert_equal "https://github.com/acme/widget/blob/#{COMMIT}/FALLBACK.md",
      fallback.data.dig("website", "source_links", "imported")
    assert_equal "https://github.com/acme/widget",
      fallback.data.dig("website", "source_links", "repository")
    assert_equal [["acme/widget", "main"]], @transport.resolve_calls
    assert_equal 3, @transport.fetch_calls.length
  end

  def test_a_physical_translation_can_replace_a_default_import_with_local_markdown
    @transport = transport_for(
      { ["acme/widget", "main"] => COMMIT },
      { ["acme/widget", COMMIT, "README.md"] => "# English import\n" }
    )
    result = compile_site(
      note(
        "portfolio/widget.md",
        "---\npublish: true\ngithub_markdown: https://github.com/acme/widget/blob/main/README.md\n---\n"
      ),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\ndir: ltr\n"),
      note(
        "_translations/zh-CN/portfolio/widget.md",
        "---\npublish: true\ntitle: 本地译文\n---\n# 本地译文\n"
      ),
      theme: "minimal",
      i18n: { "enabled" => true, "locales" => %w[en zh-CN] }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    translated = page(result, "/zh-CN/portfolio/widget/")
    assert_includes translated.content, "本地译文"
    refute translated.data.dig("website", "source_links").key?("imported")
    refute translated.data.dig("website", "source_links").key?("repository")
    assert_equal 1, @transport.fetch_calls.length
  end

  def test_a_replayed_manifest_must_match_an_empty_reference_plan
    stale_manifest = {
      "version" => 1,
      "documents" => [
        {
          "repository" => "acme/widget",
          "requested_ref" => "main",
          "path" => "README.md",
          "resolved_commit" => COMMIT,
          "digest" => Digest::SHA256.hexdigest("# Stale\n"),
          "markdown" => "# Stale\n"
        }
      ]
    }

    result = compile_site(
      note("index.md", "---\npublish: true\n---\n# Home\n"),
      theme: "minimal",
      manifest: stale_manifest
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "github_markdown_manifest_invalid" }
    assert_empty @transport.resolve_calls
    assert_empty @transport.fetch_calls
  end

  private

  def transport_for(commits, files)
    JekyllObsidian::GitHubMarkdown::MemoryTransport.new(commits: commits, files: files)
  end

  def compile_site(*entries, manifest: nil, **overrides)
    snapshot = JekyllObsidian::Snapshot.new(entries: entries)
    config = JekyllObsidian::BuildConfig.new(**CompilerTestHelpers::DEFAULT_CONFIG.merge(overrides))
    request = JekyllObsidian::BuildRequest.new(snapshot: snapshot, config: config)
    JekyllObsidian::SiteCompilation.compile(
      request,
      transport: @transport,
      cache_root: @temporary_root,
      manifest: manifest
    )
  end
end
