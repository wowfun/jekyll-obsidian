# frozen_string_literal: true

require "test_helper"

class OutputLimitsTest < Minitest::Test
  def entries
    [note("index.md", "---\npublish: true\n---\n# Home")] + (1..4).map do |day|
      note("posts/#{day}.md", "---\npublish: true\ncontent_type: post\ndate: 2026-09-0#{day}\ndescription: Short summary #{day}\n---\n# Report #{day}\n\nLong body token #{day}")
    end
  end

  def test_bounded_summary_search_feed_and_authored_home
    result = compile(*entries, search: { "mode" => "summary", "max_entries" => 2, "excerpt_length" => 12, "content_types" => ["post"] }, feed: { "max_entries" => 1 }, home: { "recent_posts_limit" => 0 })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    docs = generated_json(result, "/assets/website/search.v1.json").fetch("documents")
    assert_equal %w[posts/4.md posts/3.md], docs.map { |doc| doc.fetch("id") }
    assert docs.all? { |doc| doc.fetch("text").length <= 12 }
    refute docs.any? { |doc| doc.fetch("text").include?("Long body") }
    assert_empty page(result, "/").data.dig("website", "theme_data", "recent_posts")
    feed = result.generated_files.find { |file| file.route == "/feed.xml" }.content
    assert_equal 1, feed.scan("<entry>").length
    assert_includes feed, "Report 4"
    assert_equal 5, result.notes.length
  end

  def test_defaults_keep_full_search_and_all_feed_entries
    result = compile(*entries)
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal 5, generated_json(result, "/assets/website/search.v1.json").fetch("documents").length
    assert_includes generated_json(result, "/assets/website/search.v1.json").to_json, "Long body"
    assert_equal 4, result.generated_files.find { |file| file.route == "/feed.xml" }.content.scan("<entry>").length
  end

  def test_invalid_settings_are_diagnostics_not_exceptions
    result = compile(*entries, search: { "mode" => "bad", "max_entries" => -2 }, feed: { "max_entries" => "4" }, home: { "recent_posts_limit" => -1 })
    refute result.success?
    assert_equal %w[invalid_feed_config invalid_home_config invalid_search_config], result.diagnostics.select { |d| d.severity == :error }.map(&:code).uniq.sort
  end
end
