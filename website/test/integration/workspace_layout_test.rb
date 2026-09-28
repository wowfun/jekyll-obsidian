# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "test_helper"
require "jekyll_obsidian/workspace_layout"

class WorkspaceLayoutTest < Minitest::Test
  SiteFixture = Data.define(:source, :dest, :cache_dir, :config)

  def setup
    @workspace = File.realpath(Dir.mktmpdir("jekyll-obsidian-workspace"))
    @cache = File.join(@workspace, ".jekyll-obsidian-cache")
    @runtime = File.join(@cache, "runtime")
    @assets = File.realpath(Dir.mktmpdir("jekyll-obsidian-package-assets"))
    FileUtils.mkdir_p([@runtime, File.join(@workspace, "docs"), File.join(@workspace, "website", "docs")])
  end

  def teardown
    FileUtils.remove_entry(@workspace)
    FileUtils.remove_entry(@assets)
  end

  def test_content_and_read_only_assets_are_independent_of_runtime_location
    %w[docs website/docs].each do |source|
      layout = resolve(source:)
      assert_equal @workspace, layout.workspace_root
      assert_equal File.join(@workspace, source), layout.source_root
      assert_equal @assets, layout.application_assets_root
      assert_equal @cache, layout.application_cache_root
      assert_equal File.join(@cache, "site"), layout.destination_root
      assert_predicate layout, :frozen?
    end
    assert_equal "docs", resolve.source
  end

  def test_supports_unicode_and_spaces_without_git
    FileUtils.mkdir_p(File.join(@workspace, "站点", "my docs"))
    assert_equal "站点/my docs", resolve(source: "站点/my docs").source
  end

  def test_rejects_unsafe_or_reserved_sources
    [nil, "", ".", "/absolute", "../docs", "docs/../website", "docs//nested", "docs/./nested",
      "C:/vault", "docs\0hidden", "docs\nhidden", ".jekyll-obsidian-cache", ".jekyll-obsidian-cache/runtime"].each do |source|
      assert_raises(JekyllObsidian::WorkspaceLayout::Invalid, source.inspect) { resolve(source:) }
    end
  end

  def test_rejects_symlink_components_and_regular_file_sources
    File.symlink(File.join(@workspace, "docs"), File.join(@workspace, "linked"))
    assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) { resolve(source: "linked") }
    File.write(File.join(@workspace, "file"), "not a directory")
    assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) { resolve(source: "file") }
  end

  def test_requires_an_isolated_runtime
    assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
      resolve(site: fixture(source: File.join(@workspace, "website")))
    end
  end

  def test_rejects_destinations_outside_owned_cache_and_implementation_directories
    [File.join(@workspace, "docs"), File.join(@workspace, "_site"), @runtime, File.join(@cache, "assets")].each do |dest|
      assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) { resolve(site: fixture(dest:)) }
    end
    %w[site site-docs site-build.Abc123].each do |name|
      assert_equal File.join(@cache, name), resolve(site: fixture(dest: File.join(@cache, name))).destination_root
    end
  end

  def test_rejects_destination_and_cache_symlinks
    File.symlink(@assets, File.join(@cache, "site"))
    assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) { resolve }
    File.unlink(File.join(@cache, "site"))
    File.symlink(@assets, File.join(@runtime, ".jekyll-cache"))
    assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) { resolve }
  end

  def test_rejects_an_arbitrary_jekyll_cache
    assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
      resolve(site: fixture(cache_dir: File.join(@workspace, "docs")))
    end
  end

  private

  def fixture(**overrides)
    SiteFixture.new(**{
      source: @runtime, dest: File.join(@cache, "site"), cache_dir: File.join(@runtime, ".jekyll-cache"),
      config: { JekyllObsidian::WorkspaceLayout::CONTEXT_KEY => { "workspace_root" => @workspace, "assets_root" => @assets } }
    }.merge(overrides))
  end

  def resolve(source: JekyllObsidian::WorkspaceLayout::DEFAULT_SOURCE, site: fixture)
    JekyllObsidian::WorkspaceLayout.resolve(site:, source:)
  end
end
