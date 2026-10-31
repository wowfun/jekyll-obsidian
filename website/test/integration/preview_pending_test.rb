# frozen_string_literal: true

require "test_helper"
require "jekyll_obsidian/preview"

class PreviewPendingTest < Minitest::Test
  def test_changes_during_a_blocked_build_schedule_only_one_follow_up
    preview = JekyllObsidian::Preview.new(Object.new)
    events = preview.instance_variable_get(:@events)
    started, release = Queue.new, Queue.new
    builds = 0
    preview.send(:mark_dirty)
    builder = Thread.new do
      events.pop
      builds += 1
      started << true
      release.pop
      if events.pop(timeout: 0.01)
        builds += 1
      end
    end
    started.pop
    10_000.times { preview.send(:mark_dirty) }
    assert_equal 1, events.size
    release << true
    builder.join
    assert_equal 2, builds
    assert events.empty?
    preview.send(:mark_dirty)
    assert_equal 1, events.size
  ensure
    builder&.kill if builder&.alive?
  end
end
