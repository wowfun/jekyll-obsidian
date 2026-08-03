# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "test_helper"
require "jekyll_obsidian/workspace_layout"

class WorkspaceLayoutTest < Minitest::Test
  SiteFixture = Data.define(:source, :dest, :cache_dir)

  def setup
    @workspace_root = Dir.mktmpdir("jekyll-obsidian-workspace")
    @site_root = File.join(@workspace_root, "website")
    FileUtils.mkdir_p(File.join(@site_root, "docs"))
    FileUtils.mkdir_p(File.join(@workspace_root, "vault"))
    FileUtils.mkdir_p(File.join(@workspace_root, "docs"))
    run_git(@workspace_root, "init", "--quiet")
  end

  def teardown
    FileUtils.remove_entry(@workspace_root) if @workspace_root && File.exist?(@workspace_root)
  end

  def test_resolves_vault_and_docs_from_the_git_workspace
    {
      "vault" => File.join(@workspace_root, "vault"),
      "docs" => File.join(@workspace_root, "docs")
    }.each do |source, expected_source_root|
      layout = resolve(source:)

      assert_equal File.realpath(@workspace_root), layout.workspace_root
      assert_equal File.realpath(@site_root), layout.site_root
      assert_equal source, layout.source
      assert_equal File.realpath(expected_source_root), layout.source_root
      assert_equal File.join(@site_root, "_site"), layout.destination_root
      assert_equal File.join(@site_root, ".jekyll-cache"), layout.jekyll_cache_root
      assert_equal File.join(@site_root, ".jekyll-obsidian-cache"), layout.application_cache_root
      assert_equal File.join(@site_root, ".jekyll-obsidian-cache", "assets"), layout.application_assets_root
      assert_predicate layout, :frozen?
    end
  end

  def test_defaults_to_the_bundled_site_docs_directory
    layout = resolve

    assert_equal "website/docs", layout.source
    assert_equal File.join(@site_root, "docs"), layout.source_root
  end

  def test_accepts_only_the_bundled_docs_directory_inside_the_site
    layout = resolve(source: "website/docs")

    assert_equal File.join(@site_root, "docs"), layout.source_root

    FileUtils.mkdir_p(File.join(@site_root, "docs", "nested"))
    error = assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
      resolve(source: "website/docs/nested")
    end
    assert_match(/must not overlap the Jekyll source/, error.message)
  end

  def test_discovers_the_workspace_when_the_site_directory_is_renamed
    renamed_site = File.join(@workspace_root, "documentation-site")
    FileUtils.mv(@site_root, renamed_site)

    layout = resolve(source: "vault", site_root: renamed_site)

    assert_equal File.realpath(@workspace_root), layout.workspace_root
    assert_equal File.realpath(renamed_site), layout.site_root
    assert_equal File.join(@workspace_root, "vault"), layout.source_root
  end

  def test_falls_back_to_the_site_parent_without_a_git_workspace
    root = Dir.mktmpdir("jekyll-obsidian-no-git")
    site_root = File.join(root, "website")
    FileUtils.mkdir_p(site_root)
    FileUtils.mkdir_p(File.join(root, "vault"))

    layout = resolve(source: "vault", site_root:)

    assert_equal File.realpath(root), layout.workspace_root
    assert_equal File.realpath(site_root), layout.site_root
    assert_equal File.join(root, "vault"), layout.source_root
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  def test_accepts_a_normalized_nested_source
    nested_source = File.join(@workspace_root, "content", "guides")
    FileUtils.mkdir_p(nested_source)

    layout = resolve(source: "content/guides")

    assert_equal "content/guides", layout.source
    assert_equal nested_source, layout.source_root
  end

  def test_rejects_unsafe_source_values
    unsafe_sources = [
      nil,
      "",
      ".",
      "/absolute",
      "../vault",
      "vault/../docs",
      "vault//nested",
      "vault/./nested",
      "C:/vault",
      "vault\0hidden"
    ]

    unsafe_sources.each do |source|
      error = assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
        resolve(source:)
      end
      assert_match(/website\.source/, error.message)
    end
  end

  def test_rejects_a_source_with_a_symbolic_link_component
    FileUtils.mkdir_p(File.join(@workspace_root, "content"))
    File.symlink(
      File.join(@workspace_root, "vault"),
      File.join(@workspace_root, "content", "linked-vault")
    )

    error = assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
      resolve(source: "content/linked-vault")
    end

    assert_match(/website\.source.*symbolic link/, error.message)
  end

  def test_rejects_sources_that_overlap_the_site_in_either_direction
    FileUtils.mkdir_p(File.join(@site_root, "content"))
    containing_site = File.join(@workspace_root, "container")
    nested_site = File.join(containing_site, "documentation-site")
    FileUtils.mkdir_p(nested_site)

    [
      ["website/content", site_fixture],
      ["container", site_fixture(site_root: nested_site)]
    ].each do |source, site|
      error = assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
        JekyllObsidian::WorkspaceLayout.resolve(site:, source:)
      end
      assert_match(/must not overlap the Jekyll source/, error.message)
    end
  end

  def test_rejects_a_destination_outside_the_site
    site = site_fixture(destination: File.join(@workspace_root, "_site"))

    error = assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
      JekyllObsidian::WorkspaceLayout.resolve(site:, source: "vault")
    end

    assert_match(/destination must stay inside the Jekyll source/, error.message)
  end

  def test_accepts_only_public_or_internal_staging_destinations
    staging = File.join(@site_root, ".jekyll-obsidian-cache", "site-build.Abc123")
    FileUtils.mkdir_p(staging)

    layout = JekyllObsidian::WorkspaceLayout.resolve(
      site: site_fixture(destination: staging),
      source: "vault"
    )
    assert_equal staging, layout.destination_root

    error = assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
      JekyllObsidian::WorkspaceLayout.resolve(
        site: site_fixture(destination: File.join(@site_root, "lib")),
        source: "vault"
      )
    end
    assert_match(/destination must be a top-level _site/, error.message)
  end

  def test_rejects_a_destination_symbolic_link
    external = File.join(@workspace_root, "external-output")
    FileUtils.mkdir_p(external)
    File.symlink(external, File.join(@site_root, "_site"))

    error = assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
      resolve(source: "vault")
    end

    assert_match(/destination.*symbolic link/, error.message)
  end

  def test_rejects_a_jekyll_cache_outside_the_site
    site = site_fixture(cache: File.join(@workspace_root, ".jekyll-cache"))

    error = assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
      JekyllObsidian::WorkspaceLayout.resolve(site:, source: "vault")
    end

    assert_match(/Jekyll cache must stay inside the Jekyll source/, error.message)
  end

  def test_rejects_a_jekyll_cache_that_owns_site_implementation
    FileUtils.mkdir_p(File.join(@site_root, "lib"))
    site = site_fixture(cache: File.join(@site_root, "lib"))

    error = assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
      JekyllObsidian::WorkspaceLayout.resolve(site:, source: "vault")
    end

    assert_match(/Jekyll cache must use the site-local \.jekyll-cache directory/, error.message)
  end

  def test_rejects_jekyll_and_application_cache_symbolic_links
    external = File.join(@workspace_root, "external-cache")
    FileUtils.mkdir_p(external)

    File.symlink(external, File.join(@site_root, ".jekyll-cache"))
    jekyll_error = assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
      resolve(source: "vault")
    end
    assert_match(/Jekyll cache.*symbolic link/, jekyll_error.message)

    FileUtils.rm(File.join(@site_root, ".jekyll-cache"))
    File.symlink(external, File.join(@site_root, ".jekyll-obsidian-cache"))
    application_error = assert_raises(JekyllObsidian::WorkspaceLayout::Invalid) do
      resolve(source: "vault")
    end
    assert_match(/application cache.*symbolic link/, application_error.message)
  end

  private

  def resolve(source: JekyllObsidian::WorkspaceLayout::DEFAULT_SOURCE, site_root: @site_root)
    JekyllObsidian::WorkspaceLayout.resolve(
      site: site_fixture(site_root:),
      source:
    )
  end

  def site_fixture(site_root: @site_root, destination: nil, cache: nil)
    SiteFixture.new(
      source: site_root,
      dest: destination || File.join(site_root, "_site"),
      cache_dir: cache || File.join(site_root, ".jekyll-cache")
    )
  end

  def run_git(root, *arguments)
    success = system("git", "-C", root, *arguments, out: File::NULL, err: File::NULL)
    assert success, "git #{arguments.join(' ')} failed"
  end
end
