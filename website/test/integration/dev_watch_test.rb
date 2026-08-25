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

  def test_initial_build_status_reports_scope_and_elapsed_time
    output = StringIO.new
    warnings = StringIO.new
    ticks = [10.0, 11.25]
    build_assets = []

    succeeded = JekyllObsidian::DevWatch.build_with_status(
      initial: true,
      build_assets: true,
      build_runner: ->(with_assets) { build_assets << with_assets; true },
      output:,
      warnings:,
      clock: -> { ticks.shift }
    )

    assert succeeded
    assert_equal [true], build_assets
    assert_equal "Building assets and site...\nBuilt assets and site in 1.25s.\n", output.string
    assert_empty warnings.string
  end

  def test_rebuild_failure_status_keeps_the_last_successful_site_available
    output = StringIO.new
    warnings = StringIO.new
    ticks = [20.0, 22.5]

    succeeded = JekyllObsidian::DevWatch.build_with_status(
      initial: false,
      build_assets: false,
      build_runner: ->(_with_assets) { false },
      output:,
      warnings:,
      clock: -> { ticks.shift }
    )

    refute succeeded
    assert_equal "Source changed. Rebuilding site...\n", output.string
    assert_equal "Build failed after 2.50s. Continuing to serve the last successful site.\n", warnings.string
  end

  def test_initial_build_failure_status_explains_that_the_watcher_stays_active
    output = StringIO.new
    warnings = StringIO.new
    ticks = [30.0, 31.0]

    succeeded = JekyllObsidian::DevWatch.build_with_status(
      initial: true,
      build_assets: true,
      build_runner: ->(_with_assets) { false },
      output:,
      warnings:,
      clock: -> { ticks.shift }
    )

    refute succeeded
    assert_equal "Building assets and site...\n", output.string
    assert_equal "Initial build failed after 1.00s. The watcher will stay active so you can repair the source.\n",
      warnings.string
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
    output = StringIO.new
    warnings = StringIO.new
    ticks = [40.0, 43.0]

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
      output:,
      warnings:,
      clock: -> { ticks.shift }
    )

    assert_equal [[:build, false], [:resolve], [:listen, "/host/docs"]], events
    assert_equal "Source changed. Rebuilding site...\nNow watching docs/ for published content.\n", output.string
    assert_equal "Build failed after 3.00s. Continuing to serve the last successful site.\n", warnings.string
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
    output = StringIO.new
    warnings = StringIO.new
    ticks = [50.0, 50.75]

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
      output:,
      warnings:,
      clock: -> { ticks.shift }
    )

    assert_equal [[:build, false], [:resolve], [:listen, "/host/docs"]], events
    assert_equal "Source changed. Rebuilding site...\nRebuilt site in 0.75s.\n" \
      "Now watching docs/ for published content.\n", output.string
    assert_empty warnings.string
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
    assert_includes source, 'command << "--quiet"'
    assert_includes source, '"--trace", "--quiet",'
    assert_includes source, 'Process.kill("INT", -server_pid)'
    refute_includes source, 'Process.kill("TERM", -server_pid)'
  end

  def test_local_server_help_supports_short_and_long_forms_and_explains_rebuild_policy
    command = File.expand_path("../../bin/dev", __dir__)
    %w[-h --help].each do |flag|
      stdout, stderr, status = Open3.capture3(command, flag)

      assert status.success?, "#{flag}: #{stderr}"
      assert_empty stderr, flag
      assert_includes stdout, "Preview host (default: 127.0.0.1)"
      assert_includes stdout, "Preview port (default: 58000)"
      assert_includes stdout, "Preview base URL (default: empty)"
      assert_includes stdout, "Preview theme (default: minimal)"
      assert_includes stdout, "Watching is always enabled."
      assert_includes stdout, "--watch and --incremental are not supported."
    end
  end

  def test_local_server_rejects_unsupported_and_unknown_options_without_a_ruby_backtrace
    command = File.expand_path("../../bin/dev", __dir__)
    %w[--watch --incremental --unknown].each do |flag|
      stdout, stderr, status = Open3.capture3(command, flag)

      refute status.success?, flag
      assert_empty stdout, flag
      assert_includes stderr, "Error: invalid option: #{flag}"
      assert_includes stderr, "Run <site-dir>/bin/dev --help for supported options."
      refute_includes stderr, "dev-watch.rb:"
    end
  end

  def test_local_server_rejects_arguments_after_the_option_terminator
    command = File.expand_path("../../bin/dev", __dir__)
    stdout, stderr, status, timed_out = capture_command(command, "--", "--watch")

    refute timed_out, "bin/dev started the watcher instead of rejecting trailing arguments"
    refute status.success?
    assert_empty stdout
    assert_includes stderr, "Error: unexpected argument: --watch"
    assert_includes stderr, "Run <site-dir>/bin/dev --help for supported options."
    refute_includes stderr, "dev-watch.rb:"
  end

  private

  def capture_command(*command)
    stdout_text = nil
    stderr_text = nil
    status = nil
    timed_out = false
    Open3.popen3(*command, pgroup: true) do |stdin, stdout, stderr, waiter|
      stdin.close
      stdout_reader = Thread.new { stdout.read }
      stderr_reader = Thread.new { stderr.read }
      unless waiter.join(2)
        timed_out = true
        begin
          Process.kill("TERM", -waiter.pid)
        rescue Errno::ESRCH
          nil
        end
        unless waiter.join(2)
          begin
            Process.kill("KILL", -waiter.pid)
          rescue Errno::ESRCH
            nil
          end
          waiter.join
        end
      end
      status = waiter.value
      stdout_text = stdout_reader.value
      stderr_text = stderr_reader.value
    end
    [stdout_text, stderr_text, status, timed_out]
  end
end
