# frozen_string_literal: true

require "listen"
require "fileutils"
require "open3"
require "stringio"
require "tmpdir"
require "test_helper"
require "jekyll_obsidian/dev_watch"

class DevWatchTest < Minitest::Test
  def test_configured_source_uses_jekyll_yaml_loading_and_merge_semantics
    Dir.mktmpdir("jekyll-obsidian-dev-watch") do |workspace|
      site_dir = File.join(workspace, "website")
      host_dir = File.join(workspace, ".github")
      FileUtils.mkdir_p([site_dir, host_dir])
      base_config = File.join(site_dir, "_config.yml")
      host_config = File.join(host_dir, "jekyll-obsidian.yml")
      File.write(base_config, <<~YAML)
        metadata: &metadata
          released: 2026-08-02
        website:
          source: website/docs
      YAML
      File.write(host_config, <<~YAML)
        host_metadata: &host_metadata
          owner: example
        inherited: *host_metadata
        website:
          source: docs
      YAML

      source = JekyllObsidian::DevWatch.configured_source(
        site_dir:,
        configuration_paths: [base_config, host_config]
      )

      assert_equal "docs", source
    end
  end

  def test_configured_source_uses_workspace_default_when_not_configured
    Dir.mktmpdir("jekyll-obsidian-dev-watch") do |workspace|
      config_path = File.join(workspace, "_config.yml")
      File.write(config_path, "title: Example\n")

      source = JekyllObsidian::DevWatch.configured_source(
        site_dir: workspace,
        configuration_paths: [config_path]
      )

      assert_same JekyllObsidian::WorkspaceLayout::DEFAULT_SOURCE, source
    end
  end

  def test_site_ignore_pattern_is_anchored_to_the_relative_site_root
    source = File.read(File.expand_path("../../scripts/dev-watch.rb", __dir__))
    pattern_source = source[/^SITE_IGNORE_PATTERN = %r\{([^\n]+)\}$/, 1]
    refute_nil pattern_source, "dev watcher must expose its site-relative ignore policy"
    pattern = Regexp.new(pattern_source)
    silencer = Listen::Silencer.new(ignore: pattern)

    assert silencer.silenced?(Pathname("node_modules/package/index.js"), :file)
    assert silencer.silenced?(Pathname(".jekyll-obsidian-cache/assets/main.js"), :file)
    assert silencer.silenced?(Pathname("_site-preview/note.html"), :file)
    refute silencer.silenced?(Pathname("src/frontend/main.ts"), :file)
  end

  def test_content_ignore_pattern_hides_directories_excluded_from_the_snapshot
    source = File.read(File.expand_path("../../scripts/dev-watch.rb", __dir__))
    pattern_source = source[/^CONTENT_IGNORE_PATTERN = %r\{([^\n]+)\}$/, 1]
    refute_nil pattern_source, "dev watcher must expose its content-relative ignore policy"
    pattern = Regexp.new(pattern_source)
    silencer = Listen::Silencer.new(ignore: pattern)

    assert silencer.silenced?(Pathname(".obsidian/workspace.json"), :file)
    assert silencer.silenced?(Pathname(".trash/deleted.md"), :file)
    refute silencer.silenced?(Pathname("notes/note.md"), :file)
  end

  def test_failed_build_does_not_prevent_switching_to_a_valid_content_root
    listener_class = Struct.new(:stopped) do
      def stop
        self.stopped = true
      end
    end
    layout_class = Struct.new(:source, :source_root, keyword_init: true)
    current_layout = layout_class.new(source: "vault", source_root: "/host/vault")
    next_layout = layout_class.new(source: "docs", source_root: "/host/docs")
    current_listener = listener_class.new(false)
    next_listener = listener_class.new(false)
    events = []

    layout, listener = JekyllObsidian::DevWatch.rebuild_and_refresh(
      batch: [[:site, "_config.yml"]],
      build_assets: false,
      site_dir: "/host/website",
      destination: "_site",
      layout: current_layout,
      content_listener: current_listener,
      changes: Queue.new,
      build_runner: lambda do |build_assets|
        events << [:build, build_assets]
        false
      end,
      layout_resolver: lambda do |_site_dir, _destination|
        events << [:resolve]
        next_layout
      end,
      listener_starter: lambda do |source_root, _changes|
        events << [:listen, source_root]
        next_listener
      end,
      output: StringIO.new,
      warnings: StringIO.new
    )

    assert_equal [[:build, false], [:resolve], [:listen, "/host/docs"]], events
    assert current_listener.stopped
    assert_same next_layout, layout
    assert_same next_listener, listener
  end

  def test_host_configuration_change_switches_to_the_new_content_root
    listener_class = Struct.new(:stopped) do
      def stop
        self.stopped = true
      end
    end
    layout_class = Struct.new(:source, :source_root, keyword_init: true)
    current_layout = layout_class.new(source: "website/docs", source_root: "/host/website/docs")
    next_layout = layout_class.new(source: "docs", source_root: "/host/docs")
    current_listener = listener_class.new(false)
    next_listener = listener_class.new(false)
    events = []

    layout, listener = JekyllObsidian::DevWatch.rebuild_and_refresh(
      batch: [[:host_config, ".github/jekyll-obsidian.yml"]],
      build_assets: false,
      site_dir: "/host/website",
      destination: "_site",
      layout: current_layout,
      content_listener: current_listener,
      changes: Queue.new,
      build_runner: ->(build_assets) { events << [:build, build_assets]; true },
      layout_resolver: ->(_site_dir, _destination) { events << [:resolve]; next_layout },
      listener_starter: ->(source_root, _changes) { events << [:listen, source_root]; next_listener },
      output: StringIO.new,
      warnings: StringIO.new
    )

    assert_equal [[:build, false], [:resolve], [:listen, "/host/docs"]], events
    assert current_listener.stopped
    assert_same next_layout, layout
    assert_same next_listener, listener
  end

  def test_site_and_content_use_separate_listener_roots
    source = File.read(File.expand_path("../../scripts/dev-watch.rb", __dir__))

    assert_includes source, "start_site_listener(site_dir, changes)"
    assert_includes source, "start_content_listener(layout.source_root, changes)"
    assert_includes source, "start_host_config_listener(site_dir, changes)"
    assert_includes source, "DevWatch.rebuild_and_refresh"
    refute_includes source, "Listen.to(layout.workspace_root"
    refute_includes source, "build_succeeded &&"
  end

  def test_missing_source_uses_the_workspace_layout_default
    source = File.read(File.expand_path("../../scripts/dev-watch.rb", __dir__))

    assert_includes source, "JekyllObsidian::DevWatch.configured_source"
    refute_match(/source\.is_a\?\(String\).*\? source : \"vault\"/, source)
  end

  def test_local_server_uses_the_project_preview_defaults
    source = File.read(File.expand_path("../../scripts/dev-watch.rb", __dir__))

    assert_includes source, 'Options.new(host: "127.0.0.1", port: 58_000, baseurl: "", theme: "minimal")'
    assert_includes source, 'command.concat(["--theme", options.theme])'
  end

  def test_local_server_help_reports_the_preview_theme_default
    command = File.expand_path("../../bin/dev", __dir__)
    stdout, stderr, status = Open3.capture3(command, "--help")

    assert status.success?, stderr
    assert_empty stderr
    assert_includes stdout, "Preview theme (default: minimal)"
  end
end
