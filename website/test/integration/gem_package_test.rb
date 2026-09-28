# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "rubygems/installer"
require "rubygems/package"
require "tmpdir"
require "test_helper"

class GemPackageTest < Minitest::Test
  def test_installed_gem_builds_an_independent_host_with_read_only_package_and_no_node
    repository = File.expand_path("../../..", __dir__)
    archive = File.join(repository, "pkg", "#{JekyllObsidian::GEM_NAME}-#{JekyllObsidian::VERSION}.gem")
    assert File.file?(archive), "Run website/bin/test or ruby website/scripts/package.rb before package tests."
    spec = Gem::Package.new(archive).spec
    assert_includes spec.files, "website/assets/manifest.json"
    assert_includes spec.files, "LICENSE"
    refute spec.files.any? { |path| path.match?(%r{/(?:jekyll-obsidian-docs|test|tests|node_modules|vendor|src|\.jekyll-obsidian-cache)/}) }
    refute spec.files.any? { |path| path.end_with?("package.json", "Gemfile", "Gemfile.lock") }

    Dir.mktmpdir("jekyll-obsidian-package") do |temporary|
      gem_home = File.join(temporary, "gems")
      installed = Gem::Installer.at(archive, install_dir: gem_home, ignore_dependencies: true, wrappers: true).install
      executable = File.join(gem_home, "bin", "jekyll-obsidian")
      package = installed.full_gem_path
      before = digest_files(package)
      host = File.join(temporary, "用户 repository")
      FileUtils.mkdir_p(host)
      environment = {
        "GEM_HOME" => gem_home, "GEM_PATH" => ([gem_home] + Gem.path).join(File::PATH_SEPARATOR),
        "BUNDLE_GEMFILE" => nil, "BUNDLE_BIN_PATH" => nil, "BUNDLER_VERSION" => nil,
        "RUBYOPT" => nil, "PATH" => "/usr/bin:/bin",
        "GITHUB_REPOSITORY" => "example/host", "JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_IN" => nil,
        "JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_OUT" => nil
      }
      # Ruby and Git are sufficient at runtime. Any attempted Node command fails the test.
      fake_bin = File.join(temporary, "bin")
      FileUtils.mkdir_p(fake_bin)
      %w[node npm npx].each do |name|
        file = File.join(fake_bin, name)
        File.write(file, "#!/bin/sh\necho 'Node must not run in an installed gem' >&2\nexit 97\n")
        FileUtils.chmod(0o755, file)
      end
      environment["PATH"] = "#{fake_bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}"
      entries = Dir.glob(File.join(package, "**", "*"), File::FNM_DOTMATCH).reject { |path| %w[. ..].include?(File.basename(path)) }
      entries.each { |path| File.chmod(File.directory?(path) ? 0o555 : 0o444, path) }
      File.chmod(0o555, package)
      run_cli(environment, executable, host, "init", "--source", "website/docs")
      %w[minimal docs].each do |theme|
        run_cli(environment, executable, host, "_#{JekyllObsidian::VERSION}_", "build",
          "--url", "https://example.test", "--baseurl", "/project", "--theme", theme)
        html = File.read(File.join(host, ".jekyll-obsidian-cache", "site", "index.html"))
        assert_includes html, "Welcome"
        assert_includes html, "/project/assets/website/"
        assert_includes html, "class=\"theme-#{theme}\""
      end
      assert_equal before, digest_files(package)
      assert_equal ["docs"], Dir.children(File.join(host, "website"))
      run_cli(environment, executable, host, "clean")
      assert File.file?(File.join(host, "website", "docs", "index.md"))
    ensure
      if package && File.directory?(package)
        File.chmod(0o755, package)
        entries&.each { |path| File.chmod(File.directory?(path) ? 0o755 : 0o644, path) }
      end
    end
  end

  private

  def run_cli(environment, executable, host, *arguments)
    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, executable, *arguments, chdir: host)
    assert status.success?, "#{arguments.join(' ')}\n#{stdout}\n#{stderr}"
  end

  def digest_files(root)
    Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }
      .sort.map { |path| [path.delete_prefix(root), Digest::SHA256.file(path).hexdigest] }
  end
end
