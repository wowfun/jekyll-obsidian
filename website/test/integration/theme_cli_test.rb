# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "tmpdir"
require "yaml"
require "test_helper"

class ThemeCliTest < Minitest::Test
  def setup
    @project_root = File.expand_path("../..", __dir__)
    @ruby_bin = File.dirname(Gem.ruby)
  end

  def test_build_theme_override_uses_a_temporary_overlay_without_rewriting_config
    config_path = File.join(@project_root, "_config.yml")
    before = Digest::SHA256.file(config_path).hexdigest
    base_config = YAML.safe_load_file(config_path, permitted_classes: [], aliases: false)
    assert_equal true, base_config["disable_disk_cache"]
    assert_equal "minimal", base_config.dig("website", "theme")

    Dir.mktmpdir("jekyll-obsidian-cli") do |temporary|
      capture = File.join(temporary, "overlay.yml")
      install_fake_bundle(temporary)
      stdout, stderr, status = Open3.capture3(
        {
          "PATH" => "#{temporary}:#{@ruby_bin}:#{ENV.fetch("PATH")}",
          "JEKYLL_ENV" => "development",
          "CAPTURE_PATH" => capture
        },
        File.join(@project_root, "bin", "build"),
        "--source", "website/docs",
        "--theme", "docs",
        "--destination", "_site-cli-overlay",
        "--skip-assets",
        chdir: File.dirname(@project_root)
      )

      assert status.success?, "#{stdout}\n#{stderr}"
      overlay = YAML.safe_load_file(capture, permitted_classes: [], aliases: false)
      assert_equal true, overlay["disable_disk_cache"]
      assert_equal "website/docs", overlay.dig("website", "source")
      assert_equal "docs", overlay.dig("website", "theme")
    end

    assert_equal before, Digest::SHA256.file(config_path).hexdigest
  ensure
    FileUtils.rm_rf(File.join(@project_root, "_site-cli-overlay"))
  end

  def test_build_loads_the_host_configuration_before_the_temporary_overlay
    Dir.mktmpdir("jekyll-obsidian-cli") do |temporary|
      captured_config = File.join(temporary, "config-paths.txt")
      install_fake_bundle(temporary)
      stdout, stderr, status = Open3.capture3(
        {
          "PATH" => "#{temporary}:#{@ruby_bin}:#{ENV.fetch("PATH")}",
          "JEKYLL_ENV" => "development",
          "CAPTURE_PATH" => File.join(temporary, "overlay.yml"),
          "CAPTURE_CONFIG_PATH" => captured_config
        },
        File.join(@project_root, "bin", "build"),
        "--destination", "_site-cli-host-config",
        "--skip-assets",
        chdir: @project_root
      )

      assert status.success?, "#{stdout}\n#{stderr}"
      paths = File.read(captured_config).split(",")
      assert_equal File.join(@project_root, "_config.yml"), paths[0]
      assert_equal File.expand_path("../../../.github/jekyll-obsidian.yml", __dir__), paths[1]
      host_config = YAML.safe_load_file(paths[1], permitted_classes: [], aliases: false)
      assert_equal "minimal", host_config.dig("website", "theme")
      assert_match(%r{/\.jekyll-obsidian-cache/config\.[^/]+/config\.yml\z}, paths[2])
    end
  ensure
    FileUtils.rm_rf(File.join(@project_root, "_site-cli-host-config"))
  end

  def test_build_rejects_an_unknown_theme
    stdout, stderr, status = Open3.capture3(
      { "PATH" => "#{@ruby_bin}:#{ENV.fetch("PATH")}" },
      File.join(@project_root, "bin", "build"),
      "--theme", "magazine",
      chdir: File.dirname(@project_root)
    )

    refute status.success?
    assert_includes "#{stdout}\n#{stderr}", "--theme"
  end

  def test_build_rejects_removed_theme_identifiers
    %w[blog digital-garden].each do |theme|
      stdout, stderr, status = Open3.capture3(
        { "PATH" => "#{@ruby_bin}:#{ENV.fetch("PATH")}" },
        File.join(@project_root, "bin", "build"),
        "--theme", theme,
        chdir: File.dirname(@project_root)
      )

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "--theme must be one of: minimal, docs."
    end
  end

  def test_production_build_rejects_a_missing_origin_before_running_tooling
    stdout, stderr, status = Open3.capture3(
      {
        "PATH" => "#{@ruby_bin}:#{ENV.fetch("PATH")}",
        "JEKYLL_ENV" => "production",
        "GITHUB_REPOSITORY" => nil,
        "PAGES_ORIGIN" => nil,
        "JEKYLL_URL" => nil
      },
      File.join(@project_root, "bin", "build"),
      "--skip-assets",
      chdir: @project_root
    )

    refute status.success?
    assert_includes "#{stdout}\n#{stderr}", "production builds require --url"
  end

  def test_failed_staged_build_preserves_the_last_good_destination
    destination_name = "_site-cli-last-good"
    destination_path = File.join(@project_root, destination_name)
    FileUtils.mkdir_p(destination_path)
    File.write(File.join(destination_path, "marker.txt"), "last good")

    Dir.mktmpdir("jekyll-obsidian-cli") do |temporary|
      install_failing_bundle(temporary)
      _stdout, _stderr, status = Open3.capture3(
        {
          "PATH" => "#{temporary}:#{@ruby_bin}:#{ENV.fetch("PATH")}",
          "JEKYLL_ENV" => "development"
        },
        File.join(@project_root, "bin", "build"),
        "--destination", destination_name,
        "--skip-assets",
        chdir: @project_root
      )

      refute status.success?
      assert_equal "last good", File.read(File.join(destination_path, "marker.txt"))
    end
  ensure
    FileUtils.rm_rf(destination_path) if destination_path
  end

  def test_dev_help_exposes_the_same_theme_choices
    Dir.mktmpdir("jekyll-obsidian-cwd") do |temporary|
      stdout, stderr, status = Open3.capture3(
        {
          "PATH" => "#{@ruby_bin}:#{ENV.fetch("PATH")}",
          "BUNDLE_GEMFILE" => File.join(temporary, "missing-host-Gemfile"),
          "RUBYOPT" => nil,
          "RUBYLIB" => nil
        },
        File.join(@project_root, "bin", "dev"),
        "--help",
        chdir: temporary
      )

      assert status.success?, stderr
      assert_includes stdout, "--theme"
      assert_includes stdout, "minimal|docs"
      refute_includes stdout, "blog"
      refute_includes stdout, "digital-garden"
    end
  end

  def test_dev_rejects_an_unknown_theme_before_starting_the_watcher
    stdout, stderr, status = Open3.capture3(
      { "PATH" => "#{@ruby_bin}:#{ENV.fetch("PATH")}" },
      File.join(@project_root, "bin", "dev"),
      "--theme", "magazine",
      chdir: @project_root
    )

    refute status.success?
    assert_includes "#{stdout}\n#{stderr}", "invalid argument"
  end

  def test_dev_rejects_removed_theme_identifiers_before_starting_the_watcher
    %w[blog digital-garden].each do |theme|
      stdout, stderr, status = Open3.capture3(
        { "PATH" => "#{@ruby_bin}:#{ENV.fetch("PATH")}" },
        File.join(@project_root, "bin", "dev"),
        "--theme", theme,
        chdir: @project_root
      )

      refute status.success?
      assert_includes "#{stdout}\n#{stderr}", "invalid argument"
    end
  end

  private

  def install_fake_bundle(directory)
    executable = File.join(directory, "bundle")
    File.write(executable, <<~SH)
      #!/bin/sh
      previous=""
      config=""
      for argument in "$@"; do
        if [ "$previous" = "--config" ]; then
          config=$argument
          break
        fi
        previous=$argument
      done
      overlay=${config##*,}
      cp "$overlay" "$CAPTURE_PATH"
      if [ -n "${CAPTURE_CONFIG_PATH:-}" ]; then
        printf '%s' "$config" > "$CAPTURE_CONFIG_PATH"
      fi
    SH
    FileUtils.chmod(0o755, executable)
  end

  def install_failing_bundle(directory)
    executable = File.join(directory, "bundle")
    File.write(executable, "#!/bin/sh\nexit 1\n")
    FileUtils.chmod(0o755, executable)
  end
end
