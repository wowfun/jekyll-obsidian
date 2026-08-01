# frozen_string_literal: true

require "listen"
require "test_helper"

class DevWatchTest < Minitest::Test
  def test_ignore_pattern_is_anchored_to_the_relative_project_root
    source = File.read(File.expand_path("../../scripts/dev-watch.rb", __dir__))
    pattern_source = source[/^WATCH_IGNORE_PATTERN = %r\{([^\n]+)\}$/, 1]
    refute_nil pattern_source, "dev watcher must expose its relative-path ignore policy"
    pattern = Regexp.new(pattern_source)
    silencer = Listen::Silencer.new(ignore: pattern)

    assert silencer.silenced?(Pathname("node_modules/package/index.js"), :file)
    assert silencer.silenced?(Pathname(".jekyll-obsidian-cache/assets/main.js"), :file)
    refute silencer.silenced?(Pathname("vault/_site/note.md"), :file)
    refute silencer.silenced?(Pathname("vault/notes/note.md"), :file)
  end
end
