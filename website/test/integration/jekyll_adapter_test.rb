# frozen_string_literal: true

require "digest"
require "fileutils"
require "test_helper"
require "jekyll"
require "open3"
require "tmpdir"
require "jekyll_obsidian/adapter"

class JekyllAdapterTest < Minitest::Test
  def setup
    @previous_jekyll_env = ENV["JEKYLL_ENV"]
    @previous_github_repository = ENV.delete("GITHUB_REPOSITORY")
    @previous_github_markdown_manifest_in = ENV["JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_IN"]
    @previous_github_markdown_manifest_out = ENV["JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_OUT"]
    ENV["JEKYLL_ENV"] = "production"
    @temporary_root = Dir.mktmpdir("jekyll-obsidian-integration")
    @site_root = File.join(@temporary_root, "website")
    FileUtils.mkdir_p(File.join(@site_root, "_layouts"))
    FileUtils.mkdir_p(File.join(@site_root, "docs"))
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "media"))
    FileUtils.mkdir_p(File.join(@temporary_root, "src"))
    File.write(File.join(@temporary_root, "src", "private.rb"), "Host source leak marker")
    File.write(File.join(@site_root, "docs", "private.md"), "Bundled example leak marker")
    %w[website-minimal website-docs].each do |layout|
      File.write(File.join(@site_root, "_layouts", "#{layout}.html"), <<~LIQUID)
        <!doctype html><html data-theme="#{layout.delete_prefix("website-")}"><body><div data-layout="once">{{ content }}</div></body></html>
      LIQUID
    end
    File.write(File.join(@temporary_root, "vault", "index.md"), <<~MARKDOWN)
      ---
      publish: true
      title: Integration
      updated: 2026-07-30
      ---
      # Integration
      Literal {{ site.secret }}.
      ![[media/public.png]]
    MARKDOWN
    File.write(File.join(@temporary_root, "vault", "private.md"), "Private leak marker")
    File.binwrite(File.join(@temporary_root, "vault", "media", "public.png"), "public-image")
    File.binwrite(File.join(@temporary_root, "vault", "media", "unused.png"), "unused-private-image")
    write_empty_asset_manifest
  end

  def teardown
    @previous_jekyll_env.nil? ? ENV.delete("JEKYLL_ENV") : ENV["JEKYLL_ENV"] = @previous_jekyll_env
    if @previous_github_repository.nil?
      ENV.delete("GITHUB_REPOSITORY")
    else
      ENV["GITHUB_REPOSITORY"] = @previous_github_repository
    end
    if @previous_github_markdown_manifest_in.nil?
      ENV.delete("JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_IN")
    else
      ENV["JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_IN"] = @previous_github_markdown_manifest_in
    end
    if @previous_github_markdown_manifest_out.nil?
      ENV.delete("JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_OUT")
    else
      ENV["JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_OUT"] = @previous_github_markdown_manifest_out
    end
    FileUtils.remove_entry(@temporary_root) if @temporary_root && File.exist?(@temporary_root)
  end

  def test_real_site_process_isolates_vault_and_renders_layout_once
    site = build_site("exclude" => [])
    assert_includes site.config.fetch("exclude"), "docs"
    site.process

    index = File.read(File.join(destination, "index.html"))
    assert_equal 1, index.scan('data-layout="once"').length
    assert_includes index, "Literal {{ site.secret }}."
    assert_includes index, "/assets/vault/media/public.png"
    assert File.file?(File.join(destination, "assets", "vault", "media", "public.png"))
    refute File.exist?(File.join(destination, "assets", "vault", "media", "unused.png"))
    refute File.exist?(File.join(destination, "vault"))
    refute File.exist?(File.join(destination, "src"))

    generated = Dir.glob(File.join(destination, "**", "*")).select { |path| File.file?(path) }.map { |path| File.binread(path) }.join("\n")
    refute_includes generated, "Private leak marker"
    refute_includes generated, "Host source leak marker"
    refute_includes generated, "Bundled example leak marker"
    refute_includes generated, "unused-private-image"

    catalog = File.read(File.join(destination, "assets", "website", "catalog.v1.json"))
    assert catalog.start_with?("{\"schema_version\":1")
    refute_includes catalog, "<!doctype html>"

    markdown = File.read(File.join(destination, "index.md"))
    assert_equal "# Integration\nLiteral {{ site.secret }}.\n![[media/public.png]]\n", markdown

    homepage = site.pages.find { |page| page.respond_to?(:website_route) && page.website_route == "/" }
    assert_equal(
      "https://github.com/example/obsidian/edit/main/vault/index.md",
      homepage.data.dig("website", "source_links", "edit")
    )
    assert_equal "/index.md", homepage.data.dig("website", "markdown_url")
  end

  def test_portfolio_apng_is_copied_to_the_built_site_byte_for_byte
    project_root = File.join(@temporary_root, "vault", "portfolio")
    FileUtils.mkdir_p(project_root)
    File.write(
      File.join(project_root, "animated.md"),
      "---\npublish: true\nimage: media/animated.apng\n---\n# Animated project"
    )
    bytes = "\x89PNG\r\n\x1A\n\x00\xFFAPNG\x00payload".b
    File.binwrite(File.join(@temporary_root, "vault", "media", "animated.apng"), bytes)

    build_site.process

    published = File.join(destination, "assets", "vault", "media", "animated.apng")
    assert File.file?(published)
    assert_equal bytes, File.binread(published)
  end

  def test_github_markdown_manifest_drives_an_offline_build_and_is_exported_for_deployment
    install_project_layout
    project_root = File.join(@temporary_root, "vault", "portfolio")
    FileUtils.mkdir_p(project_root)
    File.write(
      File.join(project_root, "remote.md"),
      <<~MARKDOWN
        ---
        publish: true
        title: Remote project
        description: Local card metadata
        github_markdown: https://github.com/acme/widget/blob/main/README.md
        ---
      MARKDOWN
    )
    markdown = "# Imported README\n\nRemote body.\n"
    document = JekyllObsidian::GitHubMarkdown::Document.new(
      repository: "acme/widget",
      requested_ref: "main",
      path: "README.md",
      resolved_commit: "0123456789abcdef0123456789abcdef01234567",
      source_url: "https://github.com/acme/widget/blob/0123456789abcdef0123456789abcdef01234567/README.md",
      digest: Digest::SHA256.hexdigest(markdown),
      markdown: markdown
    )
    cache_root = File.join(@site_root, ".jekyll-obsidian-cache")
    input_path = File.join(cache_root, "github-markdown-input.json")
    output_path = File.join(cache_root, "github-markdown-output.json")
    File.write(input_path, JekyllObsidian::GitHubMarkdown.dump_manifest([document]))
    ENV["JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_IN"] = ".jekyll-obsidian-cache/github-markdown-input.json"
    ENV["JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_OUT"] = ".jekyll-obsidian-cache/github-markdown-output.json"

    build_site("website" => website_config.merge("repository" => "")).process

    html = File.read(File.join(destination, "portfolio", "remote", "index.html"))
    assert_includes html, "Imported README"
    assert_includes html, "View imported Markdown"
    assert_includes html, document.source_url
    source_actions = Nokogiri::HTML5.parse(html).at_css(".source-actions")
    assert_equal "View imported Markdown", source_actions["aria-label"]
    assert_nil source_actions.at_css("a[href*='/edit/']")
    assert_equal "# Imported README\n\nRemote body.\n",
      File.read(File.join(destination, "portfolio", "remote.md"))
    assert_equal JSON.parse(File.read(input_path)), JSON.parse(File.read(output_path))
  end

  def test_indexless_source_renders_a_verified_root_redirect_to_the_first_page
    FileUtils.rm(File.join(@temporary_root, "vault", "index.md"))
    File.write(File.join(@temporary_root, "vault", "Later.md"), "---\npublish: true\nnav_order: 20\n---\n# Later")
    File.write(File.join(@temporary_root, "vault", "Start.md"), "---\npublish: true\nnav_order: 10\n---\n# Start")
    install_project_layout
    content = {
      "default_type" => "doc",
      "directories" => { "post" => [], "doc" => [] }
    }

    build_site(
      "baseurl" => "/manual",
      "website" => website_config.merge("theme" => "docs", "content" => content)
    ).process

    redirect = File.read(File.join(destination, "index.html"))
    assert_includes redirect, 'http-equiv="refresh"'
    assert_includes redirect, 'content="0; url=/manual/Start/"'
    assert_includes redirect, 'rel="canonical" href="https://example.test/manual/Start/"'
    assert File.file?(File.join(destination, "Start", "index.html"))
    assert_includes File.read(File.join(destination, "Later", "index.html")), 'class="site-mark" href="/manual/Start/"'

    verifier = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
    stdout, stderr, status = Open3.capture3(Gem.ruby, verifier, destination, "https://example.test", "/manual")
    assert status.success?, "#{stdout}\n#{stderr}"
  end

  def test_indexless_minimal_home_keeps_system_modules_in_the_first_content_row
    FileUtils.rm(File.join(@temporary_root, "vault", "index.md"))
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "blog"))
    File.write(File.join(@temporary_root, "vault", "blog", "dispatch.md"), <<~MARKDOWN)
      ---
      publish: true
      title: One dispatch
      date: 2026-07-01
      tags: [Engineering]
      ---
      # One dispatch
    MARKDOWN
    install_project_layout

    build_site("website" => website_config.merge("theme" => "minimal")).process

    document = Nokogiri::HTML5.parse(File.read(File.join(destination, "index.html")))
    recent = document.at_css(".minimal-reading-column .note-content > .minimal-recent")
    refute_nil recent
    refute_nil document.at_css(".minimal-home-context")
    assert_nil document.at_css(".minimal-home-modules")
    refute_includes document.at_css("main")["class"], "minimal-shell--authored-home"
  end

  def test_real_footer_always_links_to_the_jekyll_obsidian_repository
    install_project_layout
    site = build_site

    site.process

    index = File.read(File.join(destination, "index.html"))
    assert_includes index, 'class="site-footer__github"'
    assert_includes index, 'href="https://github.com/wowfun/jekyll-obsidian"'
    refute_includes index, 'class="site-footer__github" href="https://github.com/example/obsidian"'
    assert_includes index, 'aria-label="Jekyll Obsidian on GitHub"'
    assert_match(/Built by.*Jekyll Obsidian.*·.*MIT License.*·.*#{site.time.strftime("%Y")}/m, index)
  end

  def test_real_themes_render_graph_ui_only_for_cross_note_relations
    File.write(File.join(@temporary_root, "vault", "index.md"), <<~MARKDOWN)
      ---
      publish: true
      title: Isolated
      updated: 2026-07-30
      ---
      Isolated body.
    MARKDOWN
    File.write(File.join(@temporary_root, "vault", "connected.md"), <<~MARKDOWN)
      ---
      publish: true
      title: Connected
      updated: 2026-07-30
      ---
      [[target]]
    MARKDOWN
    File.write(File.join(@temporary_root, "vault", "target.md"), <<~MARKDOWN)
      ---
      publish: true
      title: Target
      updated: 2026-07-30
      ---
      Target body.
    MARKDOWN
    File.write(File.join(@temporary_root, "vault", "self.md"), <<~MARKDOWN)
      ---
      publish: true
      title: Self
      updated: 2026-07-30
      ---
      [[self]]
    MARKDOWN
    install_project_layout

    %w[minimal docs].each do |theme|
      themed_destination = File.join(@site_root, "_site-#{theme}")
      build_site(
        "destination" => themed_destination,
        "website" => website_config.merge("theme" => theme)
      ).process

      isolated = File.read(File.join(themed_destination, "index.html"))
      refute_includes isolated, "data-local-graph-section", theme
      refute_includes isolated, 'data-dialog="graph-global"', theme
      refute_includes isolated, 'data-dialog="graph-local"', theme

      self_linked = File.read(File.join(themed_destination, "self", "index.html"))
      refute_includes self_linked, "data-local-graph-section", theme
      refute_includes self_linked, 'data-dialog="graph-global"', theme
      refute_includes self_linked, 'data-dialog="graph-local"', theme

      connected = File.read(File.join(themed_destination, "connected", "index.html"))
      assert_includes connected, "data-local-graph-section", theme
      assert_includes connected, 'data-dialog="graph-global"', theme
      assert_includes connected, 'data-dialog="graph-local"', theme
    end
  end

  def test_real_themes_render_related_articles_at_the_end_of_the_authored_page
    File.write(File.join(@temporary_root, "vault", "index.md"), <<~MARKDOWN)
      ---
      publish: true
      title: Integration
      related:
        - "[[target|Read next]]"
      ---
      # Integration
      Authored body.
    MARKDOWN
    File.write(File.join(@temporary_root, "vault", "target.md"), <<~MARKDOWN)
      ---
      publish: true
      title: Target
      description: A related page summary.
      ---
      # Target
    MARKDOWN
    install_project_layout

    %w[minimal docs].each do |theme|
      themed_destination = File.join(@site_root, "_site-related-#{theme}")
      config = website_config.merge(
        "theme" => theme,
        "features" => { "relations" => false, "graph" => false }
      )
      build_site("destination" => themed_destination, "website" => config).process

      document = Nokogiri::HTML5.parse(File.read(File.join(themed_destination, "index.html")))
      related = document.at_css("nav.related-articles")
      refute_nil related, theme
      assert_equal "Related articles", related.at_css("h2")&.text&.strip, theme
      card = related.at_css("article.minimal-post-card")
      refute_nil card, theme
      assert_equal "Read next", card.at_css("h3 a")&.text&.strip, theme
      assert_equal "/target/", card.at_css("h3 a")&.[]("href"), theme
      assert_equal "A related page summary.", card.at_css(".minimal-post-card__excerpt")&.text&.strip, theme
      source_actions = document.at_css(".source-actions")
      article_children = source_actions.parent.element_children
      assert_operator article_children.index(source_actions), :<, article_children.index(related), theme
      assert_nil Nokogiri::HTML5.parse(File.read(File.join(themed_destination, "target", "index.html"))).at_css("nav.related-articles"), theme
    end
  end

  def test_obsidian_trash_is_not_compiled_as_public_content
    trash_root = File.join(@temporary_root, "vault", ".trash")
    FileUtils.mkdir_p(trash_root)
    File.write(File.join(trash_root, "deleted.md"), <<~MARKDOWN)
      ---
      publish: true
      title: Deleted
      ---
      Deleted trash marker
    MARKDOWN

    site = build_site
    site.process

    refute File.exist?(File.join(destination, ".trash"))
    generated = Dir.glob(File.join(destination, "**", "*"), File::FNM_DOTMATCH)
      .select { |path| File.file?(path) }
      .map { |path| File.binread(path) }
      .join("\n")
    refute_includes generated, "Deleted trash marker"
  end

  def test_render_failure_cleans_staged_vault_assets
    File.write(
      File.join(@site_root, "_layouts", "website-minimal.html"),
      "{% include missing-staging-cleanup-fixture.html %}"
    )
    site = build_site

    2.times do
      error = assert_expected_failure(StandardError) { site.process }
      assert_includes error.message, "missing-staging-cleanup-fixture.html"

      staging = Dir.glob(File.join(@site_root, ".jekyll-obsidian-cache", "vault-assets.*"))
      assert_empty staging
    end
  end

  def test_write_failure_cleans_staged_vault_assets
    site = build_site
    site.define_singleton_method(:write) { raise IOError, "intentional write failure" }

    error = assert_raises(IOError) { site.process }

    assert_equal "intentional write failure", error.message
    staging = Dir.glob(File.join(@site_root, ".jekyll-obsidian-cache", "vault-assets.*"))
    assert_empty staging
  end

  def test_minimal_blog_index_renders_each_entry_once
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "blog"))
    File.write(File.join(@temporary_root, "vault", "blog", "dispatch.md"), <<~MARKDOWN)
      ---
      publish: true
      title: One dispatch
      date: 2026-07-01
      updated: 2026-07-02
      ---
      # One dispatch
    MARKDOWN
    File.write(File.join(@site_root, "_layouts", "website-minimal.html"), <<~LIQUID)
      <!doctype html><html><body>{{ content }}{% if page.website.kind == 'blog-index' %}{% for group in page.website.theme_data.archive_groups %}{% for post in group.posts %}<a data-blog-entry href="{{ post.url }}">{{ post.title }}</a>{% endfor %}{% endfor %}{% endif %}</body></html>
    LIQUID

    site = build_site("website" => website_config.merge("theme" => "minimal"))
    site.process

    blog = File.read(File.join(destination, "blog", "index.html"))
    assert_equal 1, blog.scan(">One dispatch<").length
  end

  def test_blog_home_renders_post_summaries_and_configured_contacts
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "blog"))
    File.write(File.join(@temporary_root, "vault", "blog", "dispatch.md"), <<~MARKDOWN)
      ---
      publish: true
      title: One dispatch
      subtitle: A field note
      date: 2026-07-01
      author:
        - Ada
      tags:
        - Engineering
        - release-notes
      categories:
        - Engineering
        - AI Agent
      ---
      # One dispatch
      A concise dispatch summary from the authored body.
    MARKDOWN
    install_project_layout
    contacts = [
      { "label" => "GitHub", "url" => "https://github.com/example" },
      { "label" => "Email", "url" => "mailto:hello@example.test" },
      { "label" => "Community", "url" => "https://community.example.test" }
    ]

    build_site("website" => website_config.merge("theme" => "minimal", "contacts" => contacts)).process

    home = File.read(File.join(destination, "index.html"))
    assert_includes home, 'class="minimal-recent__grid"'
    assert_includes home, 'class="minimal-post-card__subtitle">A field note'
    assert_includes home, "A concise dispatch summary from the authored body."
    assert_includes home, "Posted by Ada on"
    assert_includes home, 'class="minimal-contacts"'
    assert_includes home, 'href="https://github.com/example"'
    assert_includes home, 'href="mailto:hello@example.test"'
    document = Nokogiri::HTML(home)
    github = document.at_css('.minimal-contacts a[href="https://github.com/example"]')
    assert_equal "minimal-contact minimal-contact--icon", github["class"]
    assert_equal "GitHub", github["aria-label"]
    assert_equal "GitHub", github["title"]
    assert_equal "true", github.at_css("svg")["aria-hidden"]
    assert_includes github.at_css("svg")["class"], "minimal-contact__icon--brand"
    assert_equal document.at_css(".site-footer__github svg path")["d"], github.at_css("svg path")["d"]
    assert_empty github.text.strip
    community = document.at_css('.minimal-contacts a[href="https://community.example.test"]')
    assert_equal "minimal-contact minimal-contact--text", community["class"]
    assert_equal "Community", community.text.strip
    assert_nil community["aria-label"]
    assert_includes home, "Literal {{ site.secret }}."
    refute_includes home, '<header class="note-header"'

    blog = File.read(File.join(destination, "blog", "index.html"))
    assert_includes blog, '<time datetime="2026-07-01T00:00:00Z">2026-07-01</time>'
    assert_includes blog, 'class="blog-ledger__meta"'
    assert_includes blog, 'class="blog-ledger__description"'
    assert_includes blog, "A concise dispatch summary from the authored body."
    blog_document = Nokogiri::HTML5.parse(blog)
    topics = blog_document.at_css(".blog-ledger__content .blog-ledger__topics")
    topic_links = topics.css("a[data-topic-filter-option]")
    assert_equal ["Engineering", "release-notes", "AI Agent"], topic_links.map { |link| link.text.strip }
    assert_equal [
      "/blog/?topic=engineering",
      "/blog/?topic=release-notes",
      "/blog/?topic=ai-agent"
    ], topic_links.map { |link| link["href"] }
    assert_equal "blog-ledger__main", topics.previous_element["class"]
    assert_nil blog_document.at_css(".blog-ledger__meta .blog-ledger__topics")

    post = Nokogiri::HTML5.parse(File.read(File.join(destination, "blog", "dispatch", "index.html")))
    topic_links = post.css(".note-meta .tag-chip")
    assert_equal ["Engineering", "release-notes", "AI Agent"], topic_links.map { |link| link.text.strip }
    assert_equal [
      "/blog/?topic=engineering",
      "/blog/?topic=release-notes",
      "/blog/?topic=ai-agent"
    ], topic_links.map { |link| link["href"] }
  end

  def test_post_byline_uses_resolved_authors_and_preserves_each_title_owner
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "blog"))
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "people"))
    File.write(File.join(@temporary_root, "vault", "people", "Ada.md"), <<~MARKDOWN)
      ---
      publish: true
      title: Ada Lovelace
      ---
      # Ada Lovelace
    MARKDOWN
    File.write(File.join(@temporary_root, "vault", "blog", "template-title.md"), <<~MARKDOWN)
      ---
      publish: true
      title: Template title
      subtitle: Field notes
      date: 2026-08-02
      author:
        - "[[people/Ada|Ada]]"
        - Editorial team
      ---
      A post without an authored level-one heading.
    MARKDOWN
    File.write(File.join(@temporary_root, "vault", "blog", "authored-heading.md"), <<~MARKDOWN)
      ---
      publish: true
      title: Frontmatter title
      date: 2026-08-01
      author:
        - Editorial team
      ---
      # Authored heading
    MARKDOWN
    install_project_layout

    build_site.process

    template = Nokogiri::HTML(File.read(File.join(destination, "blog", "template-title", "index.html")))
    template_header = template.at_css(".note-header")
    assert_equal %w[note-title note-byline note-subtitle note-meta],
      template_header.element_children.map { |element| element["class"] }
    assert_equal "Posted by Ada, Editorial team", template_header.at_css(".note-byline").text.strip
    assert_equal "/people/Ada/", template_header.at_css(".note-byline a")["href"]

    authored = Nokogiri::HTML(File.read(File.join(destination, "blog", "authored-heading", "index.html")))
    assert_nil authored.at_css(".note-header .note-title")
    byline = authored.at_css(".note-header .note-byline")
    heading = authored.at_css(".note-content h1")
    assert_equal "Posted by Editorial team", byline.text.strip
    document_order = authored.css(".minimal-entry *")
    assert_operator document_order.index(byline), :<, document_order.index(heading)
  end

  def test_search_navigation_uses_the_same_compiler_owned_items_as_the_header
    File.write(File.join(@temporary_root, "vault", "about.md"), <<~MARKDOWN)
      ---
      publish: true
      navigation:
        label: Company
        order: 15
      ---
      # About
    MARKDOWN
    install_project_layout

    build_site("website" => website_config.merge("theme" => "minimal")).process

    document = Nokogiri::HTML(File.read(File.join(destination, "index.html")))
    header = document.css(".site-navigation [data-navigation-id]").map do |item|
      link = item.at_css("a")
      [item["data-navigation-id"], link["href"], link.text, link["aria-current"]]
    end
    search = document.css("[data-search-navigation] [data-navigation-id]").map do |item|
      link = item.at_css("a")
      [item["data-navigation-id"], link["href"], link.text, link["aria-current"]]
    end

    assert_equal header, search
    assert_includes search, ["page:about.md", "/about/", "Company", nil]
  end

  def test_host_docs_source_is_compiled_without_entering_the_reader
    FileUtils.mv(File.join(@temporary_root, "vault"), File.join(@temporary_root, "docs"))
    site = build_site("website" => website_config.merge("source" => "docs"))
    site.process

    assert File.file?(File.join(destination, "index.html"))
    assert_empty site.pages.select { |page| page.path.to_s.include?("docs") }
    assert_empty site.static_files.select { |file| file.path.to_s.include?("docs") }
  end

  def test_bundled_docs_source_is_excluded_before_reader_and_compiled_by_the_adapter
    FileUtils.remove_entry(File.join(@site_root, "docs"))
    FileUtils.mv(File.join(@temporary_root, "vault"), File.join(@site_root, "docs"))
    site = build_site(
      "exclude" => [],
      "website" => website_config.merge("source" => "website/docs")
    )

    assert_includes site.config.fetch("exclude"), "docs"

    site.process

    assert File.file?(File.join(destination, "index.html"))
    refute File.exist?(File.join(destination, "private.md"))
    refute File.exist?(File.join(destination, "media", "unused.png"))
    assert_empty site.pages.reject { |page| page.respond_to?(:website_route) }
    assert_empty site.static_files.select { |file| file.path.to_s.start_with?(File.join(@site_root, "docs")) }

    homepage = site.pages.find { |page| page.respond_to?(:website_route) && page.website_route == "/" }
    assert_equal(
      "https://github.com/example/obsidian/edit/main/website/docs/index.md",
      homepage.data.dig("website", "source_links", "edit")
    )
  end

  def test_missing_website_configuration_uses_public_defaults
    site = build_site("website" => nil)

    assert_equal "website/docs", site.config.dig("website", "source")
    assert_equal "docs", site.config.dig("website", "theme")
    assert_nil site.config.dig("website", "content")
    assert_nil site.config.dig("website", "features")
    assert_nil site.config.dig("website", "comments")
    assert_nil site.config.dig("website", "analytics")
  end

  def test_legacy_obsidian_configuration_is_rejected_instead_of_using_bundled_defaults
    error = assert_raises(Jekyll::Errors::FatalException) do
      build_site("website" => nil, "obsidian" => website_config)
    end

    assert_includes error.message, "obsidian"
    assert_includes error.message, "website"
  end

  def test_production_analytics_reaches_both_theme_heads_with_exact_csp_permissions
    install_project_layout
    profiles = {
      "cloudflare" => {
        "configuration" => { "provider" => "cloudflare", "token" => "site-token-123" },
        "identifier" => "site-token-123",
        "csp" => "default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self' https://static.cloudflareinsights.com; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self' https://cloudflareinsights.com; frame-src 'self'"
      },
      "google" => {
        "configuration" => { "provider" => "google", "measurement_id" => "G-ABC123XYZ9" },
        "identifier" => "G-ABC123XYZ9",
        "csp" => "default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self' https://www.googletagmanager.com; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self' https://*.analytics.google.com https://*.google-analytics.com https://www.googletagmanager.com; frame-src 'self'"
      }
    }

    profiles.each do |provider, profile|
      %w[minimal docs].each do |theme|
        themed_destination = File.join(@site_root, "_site-#{theme}-#{provider}")
        configured_analytics = profile.fetch("configuration")
        site = build_site(
          "destination" => themed_destination,
          "website" => website_config.merge("theme" => theme, "analytics" => configured_analytics)
        )
        assert_equal configured_analytics, site.config.dig("website", "analytics"), "#{theme}/#{provider}"

        site.process

        ["index.html", "404.html"].each do |relative|
          document = Nokogiri::HTML(File.read(File.join(themed_destination, relative)))
          analytics = document.at_css('meta[name="website:analytics"]')
          assert_equal provider, analytics["data-provider"], "#{theme}/#{provider}/#{relative}"
          assert_equal profile.fetch("identifier"), analytics["content"], "#{theme}/#{provider}/#{relative}"
          assert_equal profile.fetch("csp"), document.at_css("meta[data-page-csp]")["content"], "#{theme}/#{provider}/#{relative}"
        end
      end
    end
  end

  def test_development_validates_analytics_but_omits_runtime_meta_and_permissions
    install_project_layout
    ENV["JEKYLL_ENV"] = "development"
    analytics = { "provider" => "google", "measurement_id" => "G-ABC123XYZ9" }
    site = build_site("website" => website_config.merge("theme" => "docs", "analytics" => analytics))

    assert_equal analytics, site.config.dig("website", "analytics")
    site.process

    document = Nokogiri::HTML(File.read(File.join(destination, "index.html")))
    assert_nil document.at_css('meta[name="website:analytics"]')
    assert_equal(
      "default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self'",
      document.at_css("meta[data-page-csp]")["content"]
    )
  end

  def test_redirect_pages_never_load_configured_analytics
    install_project_layout
    FileUtils.rm(File.join(@temporary_root, "vault", "index.md"))
    File.write(File.join(@temporary_root, "vault", "Start.md"), "---\npublish: true\n---\n# Start")
    analytics = { "provider" => "cloudflare", "token" => "site-token-123" }

    build_site(
      "website" => website_config.merge("theme" => "docs", "analytics" => analytics)
    ).process

    redirect = Nokogiri::HTML(File.read(File.join(destination, "index.html")))
    assert_equal "refresh", redirect.at_css('meta[http-equiv="refresh"]')["http-equiv"]
    assert_nil redirect.at_css('meta[name="website:analytics"]')
    assert_equal(
      "default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self'",
      redirect.at_css("meta[data-page-csp]")["content"]
    )

    destination_page = Nokogiri::HTML(File.read(File.join(destination, "Start", "index.html")))
    assert_equal "cloudflare", destination_page.at_css('meta[name="website:analytics"]')["data-provider"]
  end

  def test_blog_renders_comments_hook_backlink_and_conditional_csp
    install_project_layout
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "blog"))
    File.write(File.join(@temporary_root, "vault", "blog", "open.md"), <<~MARKDOWN)
      ---
      publish: true
      content_type: post
      date: 2026-08-01
      ---
      # Open post
    MARKDOWN
    File.write(File.join(@temporary_root, "vault", "blog", "closed.md"), <<~MARKDOWN)
      ---
      publish: true
      content_type: post
      date: 2026-08-02
      comments: false
      ---
      # Closed post
    MARKDOWN
    comments = {
      "repository" => "example/community",
      "repository_id" => "R_kgDOExample",
      "category" => "Blog comments",
      "category_id" => "DIC_kwDOExample"
    }
    site = build_site("website" => website_config.merge("theme" => "minimal", "comments" => comments))

    site.process

    open_post = File.read(File.join(destination, "blog", "open", "index.html"))
    assert_includes open_post, "data-website-comments-load"
    assert_includes open_post, 'data-website-comments-term="website:post:blog/open"'
    assert_includes open_post, 'meta name="giscus:backlink" content="https://example.test/blog/open/"'
    assert_includes open_post, "script-src 'self' https://giscus.app"
    assert_includes open_post, "style-src 'self' 'unsafe-inline' https://giscus.app"
    assert_includes open_post, "frame-src 'self' https://giscus.app"
    refute_includes open_post, '<script src="https://giscus.app/client.js"'

    closed_post = File.read(File.join(destination, "blog", "closed", "index.html"))
    refute_includes closed_post, "data-website-comments-load"
    refute_includes closed_post, "giscus:backlink"
    refute_includes closed_post, "https://giscus.app"

    homepage = File.read(File.join(destination, "index.html"))
    refute_includes homepage, "data-website-comments-load"
    refute_includes homepage, "https://giscus.app"

    ENV["JEKYLL_ENV"] = "development"
    build_site("website" => website_config.merge("theme" => "minimal", "comments" => comments)).process
    development_post = File.read(File.join(destination, "blog", "open", "index.html"))
    assert_includes development_post, "Comments load only on the published site."
    refute_includes development_post, "data-website-comments-load"
    refute_includes development_post, "https://giscus.app"
  end

  def test_incomplete_giscus_setup_renders_a_noninteractive_fallback
    install_project_layout
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "blog"))
    File.write(File.join(@temporary_root, "vault", "blog", "post.md"), <<~MARKDOWN)
      ---
      publish: true
      content_type: post
      date: 2026-08-01
      ---
      # Post
    MARKDOWN

    build_site(
      "website" => website_config.merge("theme" => "minimal", "comments" => { "enabled" => true })
    ).process

    html = File.read(File.join(destination, "blog", "post", "index.html"))
    assert_includes html, "Comments are not available yet. You can finish the GitHub Discussions setup later."
    assert_includes html, 'href="https://github.com/example/obsidian"'
    assert_includes html, "Open the comments repository on GitHub"
    refute_includes html, "data-website-comments-load"
    refute_includes html, "giscus:backlink"
    refute_includes html, "https://giscus.app"
  end

  def test_non_blog_themes_can_render_explicitly_enabled_comments
    install_project_layout
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "blog"))
    File.write(File.join(@temporary_root, "vault", "blog", "post.md"), <<~MARKDOWN)
      ---
      publish: true
      content_type: post
      date: 2026-08-01
      ---
      # Post
    MARKDOWN
    comments = {
      "enabled" => true,
      "repository" => "example/community",
      "repository_id" => "R_kgDOExample",
      "category" => "Comments",
      "category_id" => "DIC_kwDOExample"
    }

    %w[docs].each do |theme|
      build_site("website" => website_config.merge("theme" => theme, "comments" => comments)).process
      html = File.read(File.join(destination, "blog", "post", "index.html"))
      assert_includes html, "data-website-comments-load", theme
      assert_includes html, "website:post:blog/post", theme
    end
  end

  def test_minimal_renders_explicit_i18n
    install_project_layout
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "blog"))
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "_translations", "zh-CN", "blog"))
    File.write(File.join(@temporary_root, "vault", "_locale.yml"), "name: English\n")
    File.write(
      File.join(@temporary_root, "vault", "_translations", "zh-CN", "_locale.yml"),
      "name: 简体中文\nmessages:\n  home: 首页\n  notes: 笔记\n  posted_by: 发布者\n"
    )
    File.write(File.join(@temporary_root, "vault", "_translations", "zh-CN", "index.md"), <<~MARKDOWN)
      ---
      publish: true
      title: 首页
      ---
      # 首页
    MARKDOWN
    File.write(File.join(@temporary_root, "vault", "blog", "post.md"), <<~MARKDOWN)
      ---
      publish: true
      content_type: post
      date: 2026-08-01
      author:
        - Editorial team
      ---
      # Post
    MARKDOWN
    File.write(File.join(@temporary_root, "vault", "_translations", "zh-CN", "blog", "post.md"), <<~MARKDOWN)
      ---
      publish: true
      author:
        - 中文编辑部
      ---
      # 文章
    MARKDOWN
    i18n = { "enabled" => true, "locales" => %w[en zh-CN] }

    { "minimal" => "首页" }.each do |theme, localized_label|
      build_site("website" => website_config.merge("theme" => theme, "i18n" => i18n)).process
      html = File.read(File.join(destination, "zh-CN", "index.html"))
      assert_includes html, '<html class="no-js" lang="zh-CN" dir="ltr" data-auto-hide-root-scrollbar>', theme
      assert_includes html, "data-language-switcher", theme
      assert_includes html, localized_label, theme
      post = Nokogiri::HTML(File.read(File.join(destination, "zh-CN", "blog", "post", "index.html")))
      assert_equal "发布者 中文编辑部", post.at_css(".note-byline").text.strip, theme
    end
  end

  def test_fallback_note_header_and_body_use_the_default_language_direction
    install_project_layout
    File.write(File.join(@temporary_root, "vault", "_locale.yml"), "name: English\ndir: ltr\n")
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "_translations", "ar"))
    File.write(
      File.join(@temporary_root, "vault", "_translations", "ar", "_locale.yml"),
      "name: العربية\ndir: rtl\n"
    )

    build_site(
      "website" => website_config.merge("theme" => "docs", "i18n" => { "locales" => %w[en ar] })
    ).process

    fallback = File.read(File.join(destination, "ar", "index.html"))
    document = Nokogiri::HTML5.parse(fallback)
    assert_equal "ar", document.at_css("html")["lang"]
    assert_equal "rtl", document.at_css("html")["dir"]
    assert_equal "en", document.at_css(".note-header")["lang"]
    assert_equal "ltr", document.at_css(".note-header")["dir"]
    assert_equal "en", document.at_css(".note-content")["lang"]
    assert_equal "ltr", document.at_css(".note-content")["dir"]
  end

  def test_fallback_portfolio_topics_separate_ui_and_content_languages
    install_project_layout
    File.write(File.join(@temporary_root, "vault", "_locale.yml"), "name: English\ndir: ltr\n")
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "_translations", "ar"))
    File.write(
      File.join(@temporary_root, "vault", "_translations", "ar", "_locale.yml"),
      "name: العربية\ndir: rtl\nmessages:\n  topics: المواضيع\n"
    )
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "portfolio"))
    File.write(
      File.join(@temporary_root, "vault", "portfolio", "project.md"),
      "---\npublish: true\ndescription: Default summary\ncategories: [Rust]\n---\n# Project\n"
    )

    build_site(
      "website" => website_config.merge(
        "theme" => "minimal",
        "i18n" => { "enabled" => true, "locales" => %w[en ar] }
      )
    ).process

    document = Nokogiri::HTML5.parse(
      File.read(File.join(destination, "ar", "portfolio", "project", "index.html"))
    )
    topics = document.at_css(".note-header .minimal-portfolio-card__topics")
    refute_nil topics
    assert_equal "المواضيع", topics["aria-label"]
    assert_equal "ar", topics["lang"]
    assert_equal "rtl", topics["dir"]
    topic = topics.at_css("li")
    assert_equal "Rust", topic.text
    assert_equal "en", topic["lang"]
    assert_equal "ltr", topic["dir"]
    topic_link = topic.at_css("a.tag-chip")
    refute_nil topic_link
    assert_equal "/ar/portfolio/?topic=rust", topic_link["href"]
  end

  def test_fallback_blog_topics_separate_ui_and_content_languages
    install_project_layout
    File.write(File.join(@temporary_root, "vault", "_locale.yml"), "name: English\ndir: ltr\n")
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "_translations", "ar"))
    File.write(
      File.join(@temporary_root, "vault", "_translations", "ar", "_locale.yml"),
      "name: العربية\ndir: rtl\nmessages:\n  topics: المواضيع\n"
    )
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "blog"))
    File.write(
      File.join(@temporary_root, "vault", "blog", "post.md"),
      "---\npublish: true\ncontent_type: post\ndate: 2026-08-01\ncategories: [Architecture]\n---\n# Post\n"
    )

    build_site(
      "website" => website_config.merge(
        "theme" => "minimal",
        "i18n" => { "enabled" => true, "locales" => %w[en ar] }
      )
    ).process

    document = Nokogiri::HTML5.parse(
      File.read(File.join(destination, "ar", "blog", "post", "index.html"))
    )
    topics = document.at_css(".note-header .note-meta__topics")
    refute_nil topics
    assert_equal "المواضيع", topics["aria-label"]
    assert_equal "ar", topics["lang"]
    assert_equal "rtl", topics["dir"]
    topic = topics.at_css("a")
    assert_equal "Architecture", topic.text
    assert_equal "en", topic["lang"]
    assert_equal "ltr", topic["dir"]
  end

  def test_reader_rejects_public_symlink_that_resolves_into_private_vault_content
    File.symlink(
      File.join(@temporary_root, "vault", "private.md"),
      File.join(@site_root, "public-alias.html")
    )
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "website.source entered Jekyll Reader"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "public-alias.html"))
  end

  def test_reader_rejects_page_symlink_that_resolves_into_private_vault_content
    private_page = File.join(@temporary_root, "vault", "private-page.html")
    File.write(private_page, "---\ntitle: Private\n---\nPrivate page marker")
    File.symlink(private_page, File.join(@site_root, "public-page.html"))
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "website.source entered Jekyll Reader"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "public-page.html"))
  end

  def test_reader_rejects_collection_document_symlink_that_resolves_into_private_vault_content
    private_document = File.join(@temporary_root, "vault", "private-document.md")
    File.write(private_document, "---\npublish: false\n---\nPrivate document marker")
    FileUtils.mkdir_p(File.join(@site_root, "_docs"))
    File.symlink(private_document, File.join(@site_root, "_docs", "public.md"))
    site = build_site("collections" => { "docs" => { "output" => true } })

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "website.source entered Jekyll Reader"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "docs"))
  end

  def test_reader_rejects_directory_symlink_chain_into_private_vault_content
    File.symlink(File.join(@temporary_root, "vault"), File.join(@site_root, "public-copy"))
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "website.source entered Jekyll Reader"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "public-copy"))
  end

  def test_source_overlapping_the_jekyll_site_is_rejected_during_initialization
    FileUtils.mkdir_p(File.join(@site_root, "content"))
    error = assert_raises(Jekyll::Errors::FatalException) do
      build_site("website" => website_config.merge("source" => "website/content"))
    end
    assert_includes error.message, "must not overlap the Jekyll source"
  end

  def test_vault_symlink_is_rejected
    File.symlink(File.join(@temporary_root, "vault", "private.md"), File.join(@temporary_root, "vault", "alias.md"))
    error = assert_raises(Jekyll::Errors::FatalException) { build_site.process }
    assert_includes error.message, "symlink"
  end

  def test_ignored_obsidian_directory_cannot_hide_a_symlink
    external = File.join(@temporary_root, "external-obsidian")
    FileUtils.mkdir_p(external)
    File.write(File.join(external, "workspace.json"), "secret")
    File.symlink(external, File.join(@temporary_root, "vault", ".obsidian"))

    error = assert_raises(Jekyll::Errors::FatalException) { build_site.process }
    assert_includes error.message, "symlink"
  end

  def test_existing_jekyll_route_collision_fails_before_atomic_append
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "blog"))
    File.write(File.join(@temporary_root, "vault", "blog", "post.md"), "---\npublish: true\ndate: 2026-07-30\n---\n# Post")
    File.write(File.join(@site_root, "blog.html"), "---\npermalink: /blog/\n---\nExisting")
    site = build_site
    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "collision"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
  end

  def test_static_root_index_collision_uses_final_destination_and_is_atomic
    File.write(File.join(@site_root, "index.html"), "Existing static index")
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "collision"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "index.html"))
  end

  def test_nested_static_index_collision_uses_final_destination
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "blog"))
    File.write(File.join(@temporary_root, "vault", "blog", "post.md"), "---\npublish: true\ndate: 2026-07-30\n---\n# Post")
    FileUtils.mkdir_p(File.join(@site_root, "blog"))
    File.write(File.join(@site_root, "blog", "index.html"), "Existing blog index")
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "collision"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "blog", "index.html"))
  end

  def test_output_collection_document_collision_is_atomic
    FileUtils.mkdir_p(File.join(@site_root, "_docs"))
    File.write(
      File.join(@site_root, "_docs", "home.md"),
      "---\npermalink: /\n---\n# Existing collection home"
    )
    site = build_site("collections" => { "docs" => { "output" => true } })

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "collision"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "index.html"))
  end

  def test_preexisting_destination_symlink_is_rejected_without_touching_target
    external = File.join(@temporary_root, "external-output")
    FileUtils.mkdir_p(external)
    canary = File.join(external, "canary.txt")
    File.write(canary, "preserve me")
    File.symlink(external, destination)

    error = assert_raises(Jekyll::Errors::FatalException) { build_site.process }
    assert_includes error.message, "destination"
    assert_equal "preserve me", File.read(canary)
  end

  def test_nested_destination_is_rejected_before_it_can_follow_a_symlink
    external = File.join(@temporary_root, "external-parent")
    FileUtils.mkdir_p(external)
    canary = File.join(external, "canary.txt")
    File.write(canary, "preserve me")
    redirect = File.join(@site_root, "output-redirect")
    File.symlink(external, redirect)

    error = assert_raises(Jekyll::Errors::FatalException) do
      build_site("destination" => File.join(redirect, "site")).process
    end
    assert_includes error.message, "destination must be a top-level _site"
    assert_equal "preserve me", File.read(canary)
  end

  def test_destination_tree_is_not_rescanned_after_initialization
    site = build_site
    external = File.join(@temporary_root, "external-assets")
    FileUtils.mkdir_p(external)
    canary = File.join(external, "canary.txt")
    File.write(canary, "preserve me")
    FileUtils.mkdir_p(File.join(destination, "assets"))
    File.symlink(external, File.join(destination, "assets", "redirect"))

    site.process
    assert_equal "preserve me", File.read(canary)
  end

  def test_destination_outside_the_jekyll_site_is_rejected_during_initialization
    unsafe_destination = File.join(@temporary_root, "vault", "published")

    error = assert_raises(Jekyll::Errors::FatalException) do
      build_site("destination" => unsafe_destination)
    end
    assert_includes error.message, "destination must stay inside the Jekyll source"
  end

  def test_destination_cannot_contain_the_jekyll_site
    unsafe_destination = @temporary_root

    error = assert_raises(Jekyll::Errors::FatalException) do
      build_site("destination" => unsafe_destination)
    end
    assert_includes error.message, "Destination directory cannot be or contain the Source directory"
  end

  def test_jekyll_cache_symlink_is_rejected_before_core_writes_through_it
    external = File.join(@temporary_root, "external-cache")
    FileUtils.mkdir_p(external)
    File.symlink(external, File.join(@site_root, ".jekyll-cache"))

    error = assert_raises(Jekyll::Errors::FatalException) { build_site }

    assert_includes error.message, "Jekyll cache"
    assert_includes error.message, "symbolic link"
    refute File.exist?(File.join(external, ".gitignore"))
  end

  def test_disabled_jekyll_disk_cache_does_not_follow_nested_cache_symlinks
    cache_root = File.join(@site_root, ".jekyll-cache")
    FileUtils.mkdir_p(cache_root)
    external_target = File.join(@temporary_root, "outside-cache-gitignore")
    File.symlink(external_target, File.join(cache_root, ".gitignore"))

    build_site.process

    refute File.exist?(external_target)
    assert File.symlink?(File.join(cache_root, ".gitignore"))
  end

  def test_unsafe_encoded_jekyll_route_is_rejected_during_preflight
    File.write(File.join(@site_root, "unsafe.html"), "---\npermalink: /safe/%2Fhidden/\n---\nUnsafe")
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "unsafe output route"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
  end

  def test_non_development_builds_require_the_application_asset_manifest
    FileUtils.rm(File.join(@site_root, ".jekyll-obsidian-cache", "assets", "manifest.json"))

    %w[production ci].each do |environment|
      ENV["JEKYLL_ENV"] = environment
      site = build_site
      error = assert_raises(Jekyll::Errors::FatalException) { site.process }
      assert_includes error.message, "asset manifest"
      refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    end
  end

  def test_development_allows_a_missing_application_asset_manifest
    ENV["JEKYLL_ENV"] = "development"
    FileUtils.rm(File.join(@site_root, ".jekyll-obsidian-cache", "assets", "manifest.json"))
    site = build_site

    site.process
    assert File.file?(File.join(destination, "index.html"))
  end

  def test_missing_active_theme_asset_fails_before_atomic_append
    FileUtils.rm(File.join(@site_root, ".jekyll-obsidian-cache", "assets", "minimal.js"))
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }

    assert_includes error.message, "application assets"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
  end

  def test_missing_enabled_bundle_feature_manifest_entry_fails_before_atomic_append
    write_asset_manifest(
      "entries" => theme_manifest_entries,
      "features" => {
        "graph" => { "files" => ["features/graph.js"] },
        "previews" => { "files" => ["features/previews.js"] }
      }
    )
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }

    assert_includes error.message, "features.search"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
  end

  def test_application_asset_cache_root_symlink_is_rejected_before_atomic_append
    cache_root = File.join(@site_root, ".jekyll-obsidian-cache", "assets")
    external_root = Dir.mktmpdir("obsidian-assets-outside")
    external_assets = File.join(external_root, "assets")
    FileUtils.mv(cache_root, external_assets)
    File.symlink(external_assets, cache_root)
    error = assert_raises(Jekyll::Errors::FatalException) { build_site.process }

    assert_includes error.message, "application assets"
    assert_includes error.message, "symbolic link"
  ensure
    FileUtils.remove_entry(external_root) if external_root && File.exist?(external_root)
  end

  def test_application_asset_intermediate_symlink_is_rejected_before_atomic_append
    cache_root = File.join(@site_root, ".jekyll-obsidian-cache", "assets")
    feature_root = File.join(cache_root, "features")
    external_root = Dir.mktmpdir("obsidian-feature-assets-outside")
    external_features = File.join(external_root, "features")
    FileUtils.mv(feature_root, external_features)
    File.symlink(external_features, feature_root)

    error = assert_raises(Jekyll::Errors::FatalException) { build_site.process }

    assert_includes error.message, "application asset"
    assert_includes error.message, "symbolic link"
  ensure
    FileUtils.remove_entry(external_root) if external_root && File.exist?(external_root)
  end

  def test_unknown_theme_is_rejected_before_reader
    site = build_site("website" => website_config.merge("theme" => "magazine"))
    error = assert_expected_failure(Jekyll::Errors::FatalException) { site.process }

    assert_includes error.message, "invalid_theme"
  end

  def test_unknown_website_configuration_keys_are_rejected
    error = assert_raises(Jekyll::Errors::FatalException) do
      build_site("website" => website_config.merge("parser_registry" => "plugins"))
    end

    assert_includes error.message, "website contains unsupported key"
    assert_includes error.message, "parser_registry"
  end

  def test_feature_overrides_must_be_yaml_booleans
    site = build_site("website" => website_config.merge("features" => { "search" => "yes" }))
    error = assert_expected_failure(Jekyll::Errors::FatalException) { site.process }

    assert_includes error.message, "invalid_feature"
  end

  def test_unknown_feature_override_is_rejected
    site = build_site("website" => website_config.merge("features" => { "unknown" => true }))
    error = assert_expected_failure(Jekyll::Errors::FatalException) { site.process }

    assert_includes error.message, "invalid_feature"
    assert_includes error.message, "unknown"
  end

  def test_content_directories_must_not_overlap_across_types
    site = build_site(
      "website" => website_config.merge(
        "content" => {
          "default_type" => "page",
          "directories" => { "post" => ["writing"], "doc" => ["writing/reference"] }
        }
      )
    )
    error = assert_expected_failure(Jekyll::Errors::FatalException) { site.process }

    assert_includes error.message, "overlapping_content_directories"
  end

  def test_content_directory_symlinks_are_rejected_before_reader
    external = File.join(@temporary_root, "external-posts")
    FileUtils.mkdir_p(external)
    File.symlink(external, File.join(@temporary_root, "vault", "blog"))

    site = build_site
    error = assert_raises(Jekyll::Errors::FatalException) { site.process }

    assert_includes error.message, "vault symlink"
    assert_includes error.message, "symlink"
  end

  def test_application_assets_are_pruned_to_the_active_theme_and_enabled_features
    write_asset_manifest(
      "entries" => {
        "minimal" => { "js" => "minimal.js", "color_scheme" => "shared.js", "files" => ["minimal.js", "shared.js"] },
        "docs" => { "js" => "docs.js", "color_scheme" => "shared.js", "files" => ["docs.js", "shared.js"] },
      },
      "features" => {
        "graph" => { "files" => ["features/graph.js", "shared.js"] },
        "search" => { "files" => ["features/search.js", "shared.js"] },
        "previews" => { "files" => ["features/previews.js"] },
        "math" => { "files" => ["features/math.js"] }
      }
    )
    File.open(File.join(@temporary_root, "vault", "index.md"), "a") { |file| file.write("\nInline math: $x^2$.\n") }
    site = build_site(
      "website" => website_config.merge(
        "theme" => "minimal",
        "features" => { "graph" => true, "previews" => true, "search" => false }
      )
    )

    site.process

    assert File.file?(File.join(destination, "assets", "website", "minimal.js"))
    assert File.file?(File.join(destination, "assets", "website", "shared.js"))
    assert File.file?(File.join(destination, "assets", "website", "features", "graph.js"))
    assert File.file?(File.join(destination, "assets", "website", "features", "previews.js"))
    assert File.file?(File.join(destination, "assets", "website", "features", "math.js"))
    refute File.exist?(File.join(destination, "assets", "website", "docs.js"))
    refute File.exist?(File.join(destination, "assets", "website", "features", "search.js"))
    assert_equal "minimal.js", site.data.dig("website_assets", "entries", "minimal", "js")
  end

  def test_switching_themes_removes_stale_application_assets
    build_site(
      "website" => website_config.merge("theme" => "minimal")
    ).process
    assert File.file?(File.join(destination, "assets", "website", "minimal.js"))
    refute File.exist?(File.join(destination, "assets", "website", "docs.js"))

    build_site(
      "website" => website_config.merge("theme" => "docs")
    ).process

    refute File.exist?(File.join(destination, "assets", "website", "minimal.js"))
    assert File.file?(File.join(destination, "assets", "website", "docs.js"))
  end

  def test_git_first_commit_dates_ignore_later_commits_and_do_not_synthesize_updated
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "blog"))
    post_path = File.join(@temporary_root, "vault", "blog", "中文.md")
    File.write(post_path, "---\npublish: true\n---\n# 中文")
    run_git("init", "--quiet")
    run_git("config", "user.name", "Obsidian Test")
    run_git("config", "user.email", "obsidian@example.test")
    run_git("add", ".")
    git_environment = {
      "GIT_AUTHOR_DATE" => "2026-07-31T12:34:56+00:00",
      "GIT_COMMITTER_DATE" => "2026-07-31T12:34:56+00:00"
    }
    run_git("commit", "--quiet", "-m", "Unicode fixture", environment: git_environment)
    File.open(post_path, "a") { |file| file.write("\nLater edit.") }
    run_git("add", "vault/blog/中文.md")
    later_environment = {
      "GIT_AUTHOR_DATE" => "2026-08-01T01:02:03+00:00",
      "GIT_COMMITTER_DATE" => "2026-08-01T01:02:03+00:00"
    }
    run_git("commit", "--quiet", "-m", "Later edit", environment: later_environment)
    install_project_layout

    site = build_site
    site.process
    feed = File.read(File.join(destination, "feed.xml"))
    assert_includes feed, "2026-07-31T12:34:56Z"
    refute_includes feed, "2026-08-01T01:02:03Z"
    assert_includes feed, "中文"

    post = site.pages.find { |page| page.data.dig("website", "id") == "blog/中文.md" }
    refute_nil post
    assert_nil post.data.dig("website", "updated")
    post_html = File.read(post.destination(destination))
    assert_includes post_html, "Published 2026-07-31"
    refute_includes post_html, "Updated "
  end

  def test_missing_deterministic_time_omits_feed_navigation_and_passes_url_verification
    File.write(File.join(@temporary_root, "vault", "index.md"), "---\npublish: true\ntitle: Integration\n---\n# Integration")
    install_project_layout

    site = build_site
    site.process

    refute site.data["website_feed_available"]
    refute File.exist?(File.join(destination, "feed.xml"))
    refute_includes File.read(File.join(destination, "index.html")), "/feed.xml"

    verifier = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
    stdout, stderr, status = Open3.capture3(Gem.ruby, verifier, destination, "https://example.test", "")
    assert status.success?, "#{stdout}\n#{stderr}"
  end

  def test_adapter_assigns_supported_base_and_3gp_media_types
    File.binwrite(File.join(@temporary_root, "vault", "media", "clip.3gp"), "audio")
    File.binwrite(File.join(@temporary_root, "vault", "media", "records.base"), "{}")
    File.open(File.join(@temporary_root, "vault", "index.md"), "a") do |file|
      file.write("\n![[media/clip.3gp]]\n[[media/records.base]]\n")
    end

    build_site.process
    html = File.read(File.join(destination, "index.html"))
    assert_includes html, 'type="audio/3gpp"'
    assert_includes html, "records.base"
    assert_includes html, "application/json"
    assert File.file?(File.join(destination, "assets", "vault", "media", "clip.3gp"))
    assert File.file?(File.join(destination, "assets", "vault", "media", "records.base"))
  end

  def test_repeated_process_does_not_duplicate_and_removes_stale_public_output
    site = build_site
    site.process
    first_count = site.pages.count { |page| page.class.name.include?("GeneratedPage") }
    site.process
    assert_equal first_count, site.pages.count { |page| page.class.name.include?("GeneratedPage") }

    File.write(File.join(@temporary_root, "vault", "index.md"), "---\npublish: false\n---\nStale marker")
    error = assert_expected_failure(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "content directory must contain at least one public note"
    # A failed build never appends a new output set. The previous destination is
    # intentionally left intact because cleanup/write were never reached.
    assert File.file?(File.join(destination, "index.html"))
  end

  def test_real_site_process_preserves_vault_and_repeats_byte_identically
    vault_root = File.join(@temporary_root, "vault")
    before_vault = tree_digest(vault_root)
    site = build_site

    site.process
    first_vault = tree_digest(vault_root)
    first_output = tree_digest(destination)

    site.process
    second_vault = tree_digest(vault_root)
    second_output = tree_digest(destination)

    assert_equal before_vault, first_vault
    assert_equal before_vault, second_vault
    assert_equal first_output, second_output
  end

  def test_git_first_commit_times_replace_the_legacy_cache_and_are_reused
    status = Object.new
    status.define_singleton_method(:success?) { true }
    calls = []
    capture = lambda do |*command|
      calls << command
      if command.include?("rev-parse")
        ["abc123\n", "", status]
      else
        ["\x1e2026-07-30T00:00:00Z\nvault/index.md\n", "", status]
      end
    end
    layout = JekyllObsidian::WorkspaceLayout.resolve(site: build_site, source: "vault")
    FileUtils.mkdir_p(layout.jekyll_cache_root)
    cache_path = File.join(layout.jekyll_cache_root, "jekyll-obsidian-git-times.json")
    File.write(cache_path, JSON.generate(
      "head" => "abc123",
      "source" => "vault",
      "times" => { "index.md" => { "first" => "2025-01-01T00:00:00Z", "last" => "2025-02-01T00:00:00Z" } }
    ))
    canary = File.join(@temporary_root, "git-cache-canary.json")
    File.write(canary, "preserve me")
    predictable_temporary = File.join(
      layout.jekyll_cache_root,
      "jekyll-obsidian-git-times.json.#{Process.pid}.tmp"
    )
    File.symlink(canary, predictable_temporary)

    with_replaced_singleton_method(Open3, :capture3, capture) do
      first = JekyllObsidian::Adapter.send(:git_first_commit_time_map, layout)
      second = JekyllObsidian::Adapter.send(:git_first_commit_time_map, layout)
      assert_equal first, second
      assert_equal({ "index.md" => "2026-07-30T00:00:00Z" }, first)
    end

    assert_equal 1, calls.count { |command| command.include?("log") }
    assert calls.all? { |command| command[2] == @temporary_root }
    cache = JSON.parse(File.read(cache_path))
    assert_equal 1, cache.fetch("version")
    assert_equal({ "index.md" => "2026-07-30T00:00:00Z" }, cache.fetch("first_committed_at"))
    refute cache.key?("times")
    assert_equal "preserve me", File.read(canary)
    assert File.symlink?(predictable_temporary)
  end

  def test_publish_true_to_false_removes_stale_note_and_indexes
    public_path = File.join(@temporary_root, "vault", "temporary.md")
    File.write(public_path, "---\npublish: true\nupdated: 2026-07-30\n---\n# Temporary\nStale public marker")
    site = build_site
    site.process
    assert File.file?(File.join(destination, "temporary", "index.html"))

    File.write(public_path, "---\npublish: false\n---\n# Temporary\nStale public marker")
    site.process
    refute File.exist?(File.join(destination, "temporary", "index.html"))
    generated = Dir.glob(File.join(destination, "**", "*")).select { |path| File.file?(path) }.map { |path| File.binread(path) }.join("\n")
    refute_includes generated, "Stale public marker"
    refute_includes generated, "temporary.md"
  end

  private

  def assert_expected_failure(error_class, &block)
    error = nil
    capture_io { error = assert_raises(error_class, &block) }
    error
  end

  def with_replaced_singleton_method(target, method_name, replacement)
    singleton_class = target.singleton_class
    original = target.method(method_name)
    singleton_class.send(:remove_method, method_name)
    singleton_class.send(:define_method, method_name, replacement)
    yield
  ensure
    singleton_class.send(:remove_method, method_name)
    singleton_class.send(:define_method, method_name, original)
  end

  def destination
    File.join(@site_root, "_site")
  end

  def website_config
    {
      "source" => "vault",
      "syntax_profile" => "ofm@1",
      "theme" => "minimal",
      "repository" => "example/obsidian",
      "edit_branch" => "main",
      "content" => {
        "default_type" => "page",
        "directories" => { "post" => ["blog"], "doc" => ["docs"] }
      },
      "features" => {}
    }
  end

  def build_site(overrides = {})
    config = Jekyll.configuration(
      {
        "source" => @site_root,
        "destination" => destination,
        "disable_disk_cache" => true,
        "quiet" => true,
        "strict_front_matter" => true,
        "title" => "Integration Obsidian",
        "description" => "Adapter fixture",
        "lang" => "en",
        "url" => "https://example.test",
        "baseurl" => "",
        "exclude" => [".jekyll-obsidian-cache"],
        "website" => website_config
      }.merge(overrides)
    )
    Jekyll::Site.new(config)
  end

  def write_empty_asset_manifest
    write_asset_manifest(
      "entries" => theme_manifest_entries,
      "features" => {
        "search" => { "files" => ["features/search.js"] },
        "graph" => { "files" => ["features/graph.js"] },
        "previews" => { "files" => ["features/previews.js"] }
      }
    )
  end

  def theme_manifest_entries
    bootstrap = "color-scheme.js"
    {
      "minimal" => { "js" => "minimal.js", "color_scheme" => bootstrap, "files" => ["minimal.js", bootstrap] },
      "docs" => { "js" => "docs.js", "color_scheme" => bootstrap, "files" => ["docs.js", bootstrap] },
    }
  end

  def write_asset_manifest(overrides)
    root = File.join(@site_root, ".jekyll-obsidian-cache", "assets")
    FileUtils.mkdir_p(root)
    manifest = { "schema_version" => 1, "features" => {} }.merge(overrides)
    files = manifest.fetch("entries").values.flat_map { |entry| entry.fetch("files") }
    files.concat(manifest.fetch("features", {}).values.flat_map { |feature| feature.fetch("files") })
    files.uniq.sort.each do |relative|
      absolute = File.join(root, relative)
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, relative)
    end
    manifest["files"] = files.uniq.sort
    File.write(File.join(root, "manifest.json"), JSON.generate(manifest))
  end

  def install_project_layout
    project_root = File.expand_path("../..", __dir__)
    %w[website-minimal website-docs website-redirect].each do |layout|
      FileUtils.cp(File.join(project_root, "_layouts", "#{layout}.html"), File.join(@site_root, "_layouts", "#{layout}.html"))
    end
    FileUtils.mkdir_p(File.join(@site_root, "_includes"))
    FileUtils.cp_r(File.join(project_root, "_includes", "."), File.join(@site_root, "_includes"))
  end

  def run_git(*arguments, environment: {})
    success = system(environment, "git", "-C", @temporary_root, *arguments, out: File::NULL, err: File::NULL)
    assert success, "git #{arguments.join(" ")} failed"
  end

  def tree_digest(root)
    entries = Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH)
      .reject { |path| File.directory?(path) }
      .sort
      .map do |path|
        relative = Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
        [relative, Digest::SHA256.hexdigest(File.binread(path))]
      end
    Digest::SHA256.hexdigest(JSON.generate(entries))
  end
end
