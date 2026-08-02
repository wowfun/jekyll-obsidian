# frozen_string_literal: true

require "listen"
require "stringio"
require "test_helper"
require "jekyll_obsidian/dev_watch"

class DevWatchTest < Minitest::Test
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

  def test_site_and_content_use_separate_listener_roots
    source = File.read(File.expand_path("../../scripts/dev-watch.rb", __dir__))

    assert_includes source, "start_site_listener(site_dir, changes)"
    assert_includes source, "start_content_listener(layout.source_root, changes)"
    assert_includes source, "DevWatch.rebuild_and_refresh"
    refute_includes source, "Listen.to(layout.workspace_root"
    refute_includes source, "build_succeeded &&"
  end
end
