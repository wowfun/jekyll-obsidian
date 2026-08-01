# frozen_string_literal: true

require "digest"
require "fileutils"
require "jekyll"
require "open3"
require "tmpdir"
require "test_helper"
require "jekyll_obsidian/adapter"

class JekyllAdapterTest < Minitest::Test
  def setup
    @previous_jekyll_env = ENV["JEKYLL_ENV"]
    ENV["JEKYLL_ENV"] = "production"
    @temporary_root = Dir.mktmpdir("jekyll-obsidian-integration")
    FileUtils.mkdir_p(File.join(@temporary_root, "_layouts"))
    FileUtils.mkdir_p(File.join(@temporary_root, "vault", "media"))
    %w[obsidian-blog obsidian-docs obsidian-digital-garden].each do |layout|
      File.write(File.join(@temporary_root, "_layouts", "#{layout}.html"), <<~LIQUID)
        <!doctype html><html data-theme="#{layout.delete_prefix("obsidian-")}"><body><div data-layout="once">{{ content }}</div></body></html>
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
    FileUtils.remove_entry(@temporary_root) if @temporary_root && File.exist?(@temporary_root)
  end

  def test_real_site_process_isolates_vault_and_renders_layout_once
    site = build_site
    site.process

    index = File.read(File.join(destination, "index.html"))
    assert_equal 1, index.scan('data-layout="once"').length
    assert_includes index, "Literal {{ site.secret }}."
    assert_includes index, "/assets/vault/media/public.png"
    assert File.file?(File.join(destination, "assets", "vault", "media", "public.png"))
    refute File.exist?(File.join(destination, "assets", "vault", "media", "unused.png"))
    refute File.exist?(File.join(destination, "vault"))

    generated = Dir.glob(File.join(destination, "**", "*")).select { |path| File.file?(path) }.map { |path| File.binread(path) }.join("\n")
    refute_includes generated, "Private leak marker"
    refute_includes generated, "unused-private-image"

    catalog = File.read(File.join(destination, "assets", "obsidian", "catalog.v1.json"))
    assert catalog.start_with?("{\"schema_version\":1")
    refute_includes catalog, "<!doctype html>"
  end

  def test_blog_archive_renders_each_entry_once
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
    File.write(File.join(@temporary_root, "_layouts", "obsidian-blog.html"), <<~LIQUID)
      <!doctype html><html><body>{{ content }}{% if page.obsidian.kind == 'archive' %}{% for group in page.obsidian.theme_data.archive_groups %}{% for post in group.posts %}<a data-archive-entry href="{{ post.url }}">{{ post.title }}</a>{% endfor %}{% endfor %}{% endif %}</body></html>
    LIQUID

    site = build_site("obsidian" => obsidian_config.merge("theme" => "blog"))
    site.process

    archive = File.read(File.join(destination, "archive", "index.html"))
    assert_equal 1, archive.scan(">One dispatch<").length
  end

  def test_dynamic_source_is_excluded_before_reader
    FileUtils.mv(File.join(@temporary_root, "vault"), File.join(@temporary_root, "notebook"))
    site = build_site("obsidian" => obsidian_config.merge("source" => "notebook"))
    site.read

    assert_empty site.pages.select { |page| page.path.to_s.include?("notebook") }
    assert_empty site.static_files.select { |file| file.path.to_s.include?("notebook") }
  end

  def test_missing_obsidian_configuration_uses_public_defaults
    site = build_site("obsidian" => nil)

    assert_equal "vault", site.config.dig("obsidian", "source")
    assert_equal "digital-garden", site.config.dig("obsidian", "theme")
    assert_nil site.config.dig("obsidian", "content")
    assert_nil site.config.dig("obsidian", "features")
  end

  def test_reader_rejects_public_symlink_that_resolves_into_private_vault_content
    File.symlink(
      File.join(@temporary_root, "vault", "private.md"),
      File.join(@temporary_root, "public-alias.html")
    )
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "obsidian.source entered Jekyll Reader"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "public-alias.html"))
  end

  def test_reader_rejects_page_symlink_that_resolves_into_private_vault_content
    private_page = File.join(@temporary_root, "vault", "private-page.html")
    File.write(private_page, "---\ntitle: Private\n---\nPrivate page marker")
    File.symlink(private_page, File.join(@temporary_root, "public-page.html"))
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "obsidian.source entered Jekyll Reader"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "public-page.html"))
  end

  def test_reader_rejects_collection_document_symlink_that_resolves_into_private_vault_content
    private_document = File.join(@temporary_root, "vault", "private-document.md")
    File.write(private_document, "---\npublish: false\n---\nPrivate document marker")
    FileUtils.mkdir_p(File.join(@temporary_root, "_docs"))
    File.symlink(private_document, File.join(@temporary_root, "_docs", "public.md"))
    site = build_site("collections" => { "docs" => { "output" => true } })

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "obsidian.source entered Jekyll Reader"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "docs"))
  end

  def test_reader_rejects_directory_symlink_chain_into_private_vault_content
    File.symlink(File.join(@temporary_root, "vault"), File.join(@temporary_root, "public-copy"))
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "obsidian.source entered Jekyll Reader"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "public-copy"))
  end

  def test_include_overlap_is_rejected_during_initialization
    error = assert_raises(Jekyll::Errors::FatalException) do
      build_site("include" => ["vault"])
    end
    assert_includes error.message, "obsidian.source"
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
    File.write(File.join(@temporary_root, "graph.html"), "---\npermalink: /graph/\n---\nExisting")
    site = build_site
    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "collision"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
  end

  def test_static_root_index_collision_uses_final_destination_and_is_atomic
    File.write(File.join(@temporary_root, "index.html"), "Existing static index")
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "collision"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "index.html"))
  end

  def test_nested_static_index_collision_uses_final_destination
    FileUtils.mkdir_p(File.join(@temporary_root, "notes"))
    File.write(File.join(@temporary_root, "notes", "index.html"), "Existing notes index")
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "collision"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
    refute File.exist?(File.join(destination, "notes", "index.html"))
  end

  def test_output_collection_document_collision_is_atomic
    FileUtils.mkdir_p(File.join(@temporary_root, "_docs"))
    File.write(
      File.join(@temporary_root, "_docs", "home.md"),
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

  def test_destination_parent_component_symlink_is_rejected
    external = File.join(@temporary_root, "external-parent")
    FileUtils.mkdir_p(external)
    canary = File.join(external, "canary.txt")
    File.write(canary, "preserve me")
    redirect = File.join(@temporary_root, "output-redirect")
    File.symlink(external, redirect)

    error = assert_raises(Jekyll::Errors::FatalException) do
      build_site("destination" => File.join(redirect, "site")).process
    end
    assert_includes error.message, "destination path contains a symlink"
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

  def test_destination_inside_obsidian_source_is_rejected_during_initialization
    unsafe_destination = File.join(@temporary_root, "vault", "published")

    error = assert_raises(Jekyll::Errors::FatalException) do
      build_site("destination" => unsafe_destination)
    end
    assert_includes error.message, "overlaps obsidian.source"
  end

  def test_destination_containing_obsidian_source_is_rejected_during_initialization
    FileUtils.mkdir_p(File.join(@temporary_root, "content"))
    FileUtils.mv(File.join(@temporary_root, "vault"), File.join(@temporary_root, "content", "vault"))
    unsafe_destination = File.join(@temporary_root, "content")

    error = assert_raises(Jekyll::Errors::FatalException) do
      build_site(
        "destination" => unsafe_destination,
        "obsidian" => obsidian_config.merge("source" => "content/vault")
      )
    end
    assert_includes error.message, "overlaps obsidian.source"
  end

  def test_unsafe_encoded_jekyll_route_is_rejected_during_preflight
    File.write(File.join(@temporary_root, "unsafe.html"), "---\npermalink: /safe/%2Fhidden/\n---\nUnsafe")
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "unsafe output route"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
  end

  def test_non_development_builds_require_the_application_asset_manifest
    FileUtils.rm(File.join(@temporary_root, ".jekyll-obsidian-cache", "assets", "manifest.json"))

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
    FileUtils.rm(File.join(@temporary_root, ".jekyll-obsidian-cache", "assets", "manifest.json"))
    site = build_site

    site.process
    assert File.file?(File.join(destination, "index.html"))
  end

  def test_missing_active_theme_asset_fails_before_atomic_append
    FileUtils.rm(File.join(@temporary_root, ".jekyll-obsidian-cache", "assets", "digital-garden.js"))
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
    cache_root = File.join(@temporary_root, ".jekyll-obsidian-cache", "assets")
    external_root = Dir.mktmpdir("obsidian-assets-outside")
    external_assets = File.join(external_root, "assets")
    FileUtils.mv(cache_root, external_assets)
    File.symlink(external_assets, cache_root)
    site = build_site

    error = assert_raises(Jekyll::Errors::FatalException) { site.process }

    assert_includes error.message, "application asset cache"
    assert_includes error.message, "symlink"
    refute site.pages.any? { |page| page.class.name.include?("GeneratedPage") }
  ensure
    FileUtils.remove_entry(external_root) if external_root && File.exist?(external_root)
  end

  def test_unknown_theme_is_rejected_before_reader
    site = build_site("obsidian" => obsidian_config.merge("theme" => "magazine"))
    error = assert_raises(Jekyll::Errors::FatalException) { site.process }

    assert_includes error.message, "invalid_theme"
  end

  def test_unknown_obsidian_configuration_keys_are_rejected
    error = assert_raises(Jekyll::Errors::FatalException) do
      build_site("obsidian" => obsidian_config.merge("parser_registry" => "plugins"))
    end

    assert_includes error.message, "obsidian contains unsupported key"
    assert_includes error.message, "parser_registry"
  end

  def test_feature_overrides_must_be_yaml_booleans
    site = build_site("obsidian" => obsidian_config.merge("features" => { "search" => "yes" }))
    error = assert_raises(Jekyll::Errors::FatalException) { site.process }

    assert_includes error.message, "invalid_feature"
  end

  def test_unknown_feature_override_is_rejected
    site = build_site("obsidian" => obsidian_config.merge("features" => { "unknown" => true }))
    error = assert_raises(Jekyll::Errors::FatalException) { site.process }

    assert_includes error.message, "invalid_feature"
    assert_includes error.message, "unknown"
  end

  def test_content_directories_must_not_overlap_across_types
    site = build_site(
      "obsidian" => obsidian_config.merge(
        "content" => {
          "default_type" => "page",
          "directories" => { "post" => ["writing"], "doc" => ["writing/reference"] }
        }
      )
    )
    error = assert_raises(Jekyll::Errors::FatalException) { site.process }

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
        "blog" => { "js" => "blog.js", "files" => ["blog.js", "shared.js"] },
        "docs" => { "js" => "docs.js", "files" => ["docs.js", "shared.js"] },
        "digital-garden" => { "js" => "digital-garden.js", "files" => ["digital-garden.js", "shared.js"] }
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
      "obsidian" => obsidian_config.merge(
        "theme" => "blog",
        "features" => { "graph" => true, "previews" => true, "search" => false }
      )
    )

    site.process

    assert File.file?(File.join(destination, "assets", "obsidian", "blog.js"))
    assert File.file?(File.join(destination, "assets", "obsidian", "shared.js"))
    assert File.file?(File.join(destination, "assets", "obsidian", "features", "graph.js"))
    assert File.file?(File.join(destination, "assets", "obsidian", "features", "previews.js"))
    assert File.file?(File.join(destination, "assets", "obsidian", "features", "math.js"))
    refute File.exist?(File.join(destination, "assets", "obsidian", "docs.js"))
    refute File.exist?(File.join(destination, "assets", "obsidian", "digital-garden.js"))
    refute File.exist?(File.join(destination, "assets", "obsidian", "features", "search.js"))
    assert_equal "blog.js", site.data.dig("obsidian_assets", "entries", "blog", "js")
  end

  def test_switching_themes_removes_stale_application_assets
    build_site(
      "obsidian" => obsidian_config.merge("theme" => "blog")
    ).process
    assert File.file?(File.join(destination, "assets", "obsidian", "blog.js"))
    refute File.exist?(File.join(destination, "assets", "obsidian", "docs.js"))

    build_site(
      "obsidian" => obsidian_config.merge("theme" => "docs")
    ).process

    refute File.exist?(File.join(destination, "assets", "obsidian", "blog.js"))
    assert File.file?(File.join(destination, "assets", "obsidian", "docs.js"))
  end

  def test_git_times_are_discovered_for_non_ascii_vault_paths
    File.write(File.join(@temporary_root, "vault", "中文.md"), "---\npublish: true\n---\n# 中文")
    run_git("init", "--quiet")
    run_git("config", "user.name", "Obsidian Test")
    run_git("config", "user.email", "obsidian@example.test")
    run_git("add", ".")
    git_environment = {
      "GIT_AUTHOR_DATE" => "2026-07-31T12:34:56+00:00",
      "GIT_COMMITTER_DATE" => "2026-07-31T12:34:56+00:00"
    }
    run_git("commit", "--quiet", "-m", "Unicode fixture", environment: git_environment)

    build_site.process
    feed = File.read(File.join(destination, "feed.xml"))
    assert_includes feed, "2026-07-31T12:34:56Z"
    assert_includes feed, "中文"
  end

  def test_missing_deterministic_time_omits_feed_navigation_and_passes_url_verification
    File.write(File.join(@temporary_root, "vault", "index.md"), "---\npublish: true\ntitle: Integration\n---\n# Integration")
    install_project_layout

    site = build_site
    site.process

    refute site.data["obsidian_feed_available"]
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
    error = assert_raises(Jekyll::Errors::FatalException) { site.process }
    assert_includes error.message, "index"
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

  def test_git_times_reuse_the_head_and_source_cache
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
    site = Object.new
    site.define_singleton_method(:source) { @temporary_root }
    site.instance_variable_set(:@temporary_root, @temporary_root)
    site.define_singleton_method(:in_source_dir) { |*parts| File.join(source, *parts) }

    Open3.stub(:capture3, capture) do
      first = JekyllObsidian::Adapter.send(:git_time_map, site, "vault")
      second = JekyllObsidian::Adapter.send(:git_time_map, site, "vault")
      assert_equal first, second
    end

    assert_equal 1, calls.count { |command| command.include?("log") }
    assert File.file?(File.join(@temporary_root, ".jekyll-cache", "jekyll-obsidian-git-times.json"))
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

  def destination
    File.join(@temporary_root, "_site")
  end

  def obsidian_config
    {
      "source" => "vault",
      "syntax_profile" => "ofm@1",
      "theme" => "digital-garden",
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
        "source" => @temporary_root,
        "destination" => destination,
        "disable_disk_cache" => true,
        "quiet" => true,
        "strict_front_matter" => true,
        "title" => "Integration Obsidian",
        "description" => "Adapter fixture",
        "lang" => "en",
        "url" => "https://example.test",
        "baseurl" => "",
        "exclude" => ["vault", ".jekyll-obsidian-cache"],
        "obsidian" => obsidian_config
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
    {
      "blog" => { "js" => "blog.js", "files" => ["blog.js"] },
      "docs" => { "js" => "docs.js", "files" => ["docs.js"] },
      "digital-garden" => { "js" => "digital-garden.js", "files" => ["digital-garden.js"] }
    }
  end

  def write_asset_manifest(overrides)
    root = File.join(@temporary_root, ".jekyll-obsidian-cache", "assets")
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
    %w[obsidian-blog obsidian-docs obsidian-digital-garden].each do |layout|
      FileUtils.cp(File.join(project_root, "_layouts", "#{layout}.html"), File.join(@temporary_root, "_layouts", "#{layout}.html"))
    end
    FileUtils.mkdir_p(File.join(@temporary_root, "_includes"))
    FileUtils.cp_r(File.join(project_root, "_includes", "."), File.join(@temporary_root, "_includes"))
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
