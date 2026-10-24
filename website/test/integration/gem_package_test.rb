# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "nokogiri"
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
    assert_includes spec.files, "website/_includes/website/back-to-top.html"
    assert_includes spec.files, "LICENSE"
    refute spec.files.any? { |path| path.match?(%r{/(?:jekyll-obsidian-docs|test|tests|node_modules|vendor|src|\.jekyll-obsidian-cache)/}) }
    refute spec.files.any? { |path| path.end_with?("package.json", "Gemfile", "Gemfile.lock") }

    Dir.mktmpdir("jekyll-obsidian-package") do |temporary|
      gem_home = File.join(temporary, "gems")
      installed = Gem::Installer.at(archive, install_dir: gem_home, ignore_dependencies: true, wrappers: true).install
      executable = File.join(gem_home, "bin", "jekyll-obsidian")
      package = installed.full_gem_path
      packaged_assets = File.join(package, "website", "assets")
      manifest = JSON.parse(File.read(File.join(packaged_assets, "manifest.json")))
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
      configuration_path = File.join(host, ".github", "jekyll-obsidian.yml")
      configuration = Psych.safe_load(File.read(configuration_path))
      configuration["lang"] = "en"
      configuration.fetch("website")["i18n"] = { "enabled" => true, "locales" => %w[en zh-CN] }
      File.write(configuration_path, JSON.generate(configuration))
      content = File.join(host, "website", "docs")
      File.write(File.join(content, "_locale.yml"), "name: English\n")
      translated = File.join(content, "_translations", "zh-CN")
      FileUtils.mkdir_p(translated)
      File.write(File.join(translated, "_locale.yml"), "name: 简体中文\nmessages:\n  back_to_top: 回到顶部\n")
      File.write(File.join(translated, "index.md"), "---\npublish: true\n---\n# 欢迎\n")
      %w[minimal docs].each do |theme|
        run_cli(environment, executable, host, "_#{JekyllObsidian::VERSION}_", "build",
          "--url", "https://example.test", "--baseurl", "/project", "--theme", theme)
        html = File.read(File.join(host, ".jekyll-obsidian-cache", "site", "index.html"))
        assert_includes html, "Welcome"
        assert_includes html, "/project/assets/website/"
        assert_includes html, "class=\"theme-#{theme}\""
        document = Nokogiri::HTML5.parse(html)
        buttons = document.css("button[data-back-to-top]")
        assert_equal 1, buttons.size
        button = buttons.first
        assert_equal "button", button["type"]
        refute_nil button.attribute("hidden")
        assert_equal "Back to top", button["aria-label"]
        assert_equal "Back to top", button["title"]
        assert_equal "-1", document.at_css("main#main-content")&.[]("tabindex")
        entry = manifest.fetch("entries").fetch(theme)
        %w[archive-filters favorite-controls].each do |lazy|
          assert entry.fetch("files").any? { |file| file.start_with?("#{lazy}-") }, "#{theme} must ship #{lazy}"
        end
        assert_includes document.css("script[type='module'][src]").map { |script| script["src"] },
          "/project/assets/website/#{entry.fetch('js')}"
        assert_includes document.css("link[rel='stylesheet']").map { |link| link["href"] },
          "/project/assets/website/#{entry.fetch('css')}"
        entry.fetch("files").each do |relative|
          published = File.join(host, ".jekyll-obsidian-cache", "site", "assets", "website", relative)
          assert File.file?(published), "#{theme} is missing #{relative}"
          assert_equal Digest::SHA256.file(File.join(packaged_assets, relative)).hexdigest,
            Digest::SHA256.file(published).hexdigest, "#{theme} changed packaged asset #{relative}"
        end
        localized = Nokogiri::HTML5.parse(File.read(File.join(host, ".jekyll-obsidian-cache", "site", "zh-CN", "index.html")))
        assert_includes localized.text, "欢迎"
        assert_equal "回到顶部", localized.at_css("[data-back-to-top]")["aria-label"]
        [document, localized].each do |built|
          built.css('meta[name="website:search-worker"], meta[name="website:archive-worker"]').each do |meta|
            relative = meta["content"].delete_prefix("/project/")
            assert File.file?(File.join(host, ".jekyll-obsidian-cache", "site", relative)), "missing worker #{relative}"
          end
        end
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
