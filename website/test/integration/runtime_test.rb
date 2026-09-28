# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "tmpdir"
require "test_helper"
require "jekyll_obsidian/runtime"
require "jekyll_obsidian/initializer"

class RuntimeTest < Minitest::Test
  def setup
    @root = File.realpath(Dir.mktmpdir("jekyll-obsidian-host"))
    JekyllObsidian::Initializer.run(root: @root, source: "website/docs")
    @runtime = JekyllObsidian::Runtime.new(root: @root)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_initialized_host_builds_both_themes_without_reading_the_host_jekyll_site
    FileUtils.mkdir_p(File.join(@root, "_plugins"))
    File.write(File.join(@root, "_plugins", "unrelated.rb"), 'raise "host plugin must not load"')
    File.write(File.join(@root, "_config.yml"), "title: Unrelated Jekyll site\n")
    File.write(File.join(@root, "private.html"), "host-secret-marker")
    File.write(File.join(@root, "website", "docs", "private.md"), "private-note-marker")
    %w[minimal docs].each do |theme|
      build(theme:, baseurl: "/project")
      html = File.read(File.join(@runtime.destination, "index.html"))
      assert_includes html, "Welcome"
      assert_includes html, "/project/assets/website/"
      refute File.exist?(File.join(@runtime.destination, "private.html"))
      refute File.exist?(File.join(@runtime.destination, "private.md"))
      output = Dir.glob(File.join(@runtime.destination, "**", "*.{html,json,md}")).map { |file| File.read(file) }.join
      refute_includes output, "host-secret-marker"
      refute_includes output, "private-note-marker"
    end
  end

  def test_configuration_is_editable_and_cli_overrides_do_not_rewrite_it
    config = YAML.safe_load_file(@runtime.config_path)
    config["title"] = "Changed title"
    config["website"]["theme"] = "docs"
    config["website"]["source"] = "中文/my docs"
    FileUtils.mkdir_p(File.join(@root, "中文"))
    FileUtils.mv(File.join(@root, "website", "docs"), File.join(@root, "中文", "my docs"))
    File.write(@runtime.config_path, YAML.dump(config))
    before = File.binread(@runtime.config_path)
    build
    html = File.read(File.join(@runtime.destination, "index.html"))
    assert_includes html, 'class="theme-docs"'
    assert_includes html, "Changed title"
    build(theme: "minimal")
    assert_includes File.read(File.join(@runtime.destination, "index.html")), 'class="theme-minimal"'
    assert_equal before, File.binread(@runtime.config_path)
  end

  def test_failed_build_preserves_the_last_successful_site
    build
    before = tree_digest(@runtime.destination)
    File.write(File.join(@root, "website", "docs", "index.md"), "---\npublish: false\n---\nPrivate now")
    error = assert_raises(Jekyll::Errors::FatalException) { build }
    assert_includes error.message, "publish: true"
    assert_equal before, tree_digest(@runtime.destination)
    assert_empty Dir.glob(File.join(@runtime.cache_root, "site-build.*"))
  end

  def test_rebuilding_reuses_git_history_outside_the_disposable_jekyll_source
    [
      %w[init --quiet], %w[add .],
      ["-c", "user.name=Test", "-c", "user.email=test@example.test", "commit", "--quiet", "-m", "Initial notes"]
    ].each do |arguments|
      output, status = Open3.capture2e("git", "-C", @root, *arguments)
      assert status.success?, output
    end
    build
    cache = File.join(@runtime.cache_root, "git-times.json")
    assert File.file?(cache)
    timestamp = Time.at(1_000_000_000)
    File.utime(timestamp, timestamp, cache)
    build
    assert_equal timestamp, File.mtime(cache)
  end

  def test_invalid_configuration_does_not_fall_back_to_bundled_documentation
    File.write(@runtime.config_path, "website: [broken\n")
    assert_raises(JekyllObsidian::Runtime::Error) { build }
    refute File.exist?(@runtime.cache_root)
  end

  def test_jekyll_implementation_options_cannot_redirect_the_reader
    config = YAML.safe_load_file(@runtime.config_path)
    config["source"] = @root
    File.write(@runtime.config_path, YAML.dump(config))
    error = assert_raises(JekyllObsidian::Runtime::Error) { build }
    assert_includes error.message, "unsupported site configuration: source"
    refute File.exist?(@runtime.cache_root)
  end

  def test_invalid_urls_fail_before_creating_build_state
    ["https://example.test/path", "https://example.test?query", "file:///private"].each do |url|
      assert_raises(JekyllObsidian::Runtime::Error) { @runtime.build(url:) }
    end
    assert_raises(JekyllObsidian::Runtime::Error) { build(baseurl: "/../outside") }
    refute File.exist?(@runtime.cache_root)
  end

  def test_clean_only_removes_owned_output_and_keeps_content_and_configuration
    build
    user_output = File.join(@root, "_site")
    FileUtils.mkdir_p(user_output)
    File.write(File.join(user_output, "owned-by-user"), "keep")
    @runtime.clean
    refute File.exist?(@runtime.destination)
    assert File.file?(@runtime.config_path)
    assert File.file?(File.join(@root, "website", "docs", "index.md"))
    assert File.file?(File.join(user_output, "owned-by-user"))
  end

  def test_build_and_clean_reject_a_symlinked_cache
    external = File.join(@root, "external")
    FileUtils.mkdir_p(external)
    File.write(File.join(external, "keep"), "keep")
    File.symlink(external, @runtime.cache_root)
    assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) { build }
    assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) { @runtime.clean }
    assert_equal "keep", File.read(File.join(external, "keep"))
  end

  def test_init_is_idempotent_and_does_not_modify_existing_content
    before = tree_digest(@root)
    assert_empty JekyllObsidian::Initializer.run(root: @root, source: "website/docs")
    assert_equal before, tree_digest(@root)
  end

  def test_init_preflights_conflicts_before_creating_any_files
    FileUtils.remove_entry(File.join(@root, ".github"))
    FileUtils.mkdir_p(File.join(@root, ".github", "workflows"))
    workflow = File.join(@root, ".github", "workflows", "pages.yml")
    File.write(workflow, "name: My existing workflow\n")
    before = tree_digest(@root)
    assert_raises(ArgumentError) { JekyllObsidian::Initializer.run(root: @root, source: "new-docs") }
    assert_equal before, tree_digest(@root)
    refute File.exist?(File.join(@root, "new-docs"))
  end

  def test_initializing_existing_notes_does_not_create_a_welcome_page
    FileUtils.remove_entry(File.join(@root, ".github"))
    File.write(File.join(@root, "website", "docs", "notes.md"), "existing note")
    File.unlink(File.join(@root, "website", "docs", "index.md"))
    JekyllObsidian::Initializer.run(root: @root, source: "website/docs")
    refute File.exist?(File.join(@root, "website", "docs", "index.md"))
    assert_equal "existing note", File.read(File.join(@root, "website", "docs", "notes.md"))
  end

  def test_unrelated_jekyll_sites_are_not_affected_by_loading_the_runtime
    source = File.join(@root, "other-site")
    FileUtils.mkdir_p(source)
    File.write(File.join(source, "index.html"), "unrelated site")
    site = Jekyll::Site.new(Jekyll.configuration("config" => [], "source" => source,
      "destination" => File.join(@root, "other-output"), "disable_disk_cache" => true, "quiet" => true))
    site.process
    assert_equal "unrelated site", File.read(File.join(@root, "other-output", "index.html"))
  end

  private

  def build(**options)
    result = nil
    capture_io { result = @runtime.build(url: "https://example.test", quiet: true, **options) }
    result
  end

  def tree_digest(root)
    Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }
      .sort.map { |path| [path.delete_prefix(root), Digest::SHA256.file(path).hexdigest] }
  end
end
