# frozen_string_literal: true
require "test_helper"

class FavoritesTest < Minitest::Test
  def articles
    [note("index.md", "---\npublish: true\n---\n# Home")] +
      ["2026-01-01T00:30:00Z", "2025-12-31T16:00:00Z", "2025-12-31T15:59:59Z"].each_with_index.map do |date, i|
        note("items/#{i}.md", "---\npublish: true\ncontent_type: post\ntitle: Item #{i}\ndate: #{date}\nsource_url: https://example.test/#{i}\ntags: [source/hn, topics/agents]\n---\nBody")
      end
  end

  def test_dates_and_favorites_share_normalized_cards_and_localized_identity
    result = compile(*articles,
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\nmessages:\n  favorites: 收藏\n"),
      baseurl: "/garden", features: { "favorites" => true }, home: { "layout" => "archive" },
      blog: { "page_size" => 2, "utc_offset" => "+08:00", "ledger_group_by" => "day" }, i18n: { "enabled" => true, "locales" => %w[en zh-CN] })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal ["2026-01-01"], page(result, "/").data.dig("website", "theme_data", "archive_groups").map { |g| g.fetch("label") }
    assert_equal "收藏", page(result, "/zh-CN/favorites/").data.fetch("title")
    assert_equal "favorites", page(result, "/favorites/").data.dig("website", "active_navigation_id")
    assert_equal "noindex", page(result, "/favorites/").data.dig("website", "robots")
    assert_equal "https://example.test/garden/", page(result, "/favorites/").data.dig("website", "canonical_url")
    assert_equal "https://example.test/garden/zh-CN/", page(result, "/zh-CN/favorites/").data.dig("website", "canonical_url")
    assert_empty page(result, "/favorites/").data.dig("website", "theme_data", "archive_groups")
    en = page(result, "/items/0/").data.fetch("website")
    zh = page(result, "/zh-CN/items/0/").data.fetch("website")
    assert_equal en.fetch("favorites_scope"), zh.fetch("favorites_scope")
    assert_equal en.fetch("favorite_card").fetch("id"), zh.fetch("favorite_card").fetch("id")
    assert_equal "/garden/zh-CN/items/0/", zh.fetch("favorite_card").fetch("url")
    assert_equal "2026-01-01", en.fetch("favorite_card").fetch("display_date")
    assert_equal({ "source/hn" => "hn", "topic/agents" => "agents" }, en.fetch("favorite_card").fetch("favorite_labels"))
    refute en.key?("favorite_labels")
    refute en.key?("favorite_prefixes")
    assert result.generated_files.any? { |file| file.route.end_with?("identities.json") }
  end

  def test_full_ledger_daily_groups_and_default_disabled_feature
    result = compile(*articles, blog: { "ledger_group_by" => "day", "utc_offset" => "+08:00" })
    assert result.success?
    assert_equal %w[2026-01-01 2025-12-31], page(result, "/blog/").data.dig("website", "theme_data", "archive_groups").map { |g| g.fetch("label") }
    refute page(result, "/favorites/")
    refute result.generated_files.any? { |file| file.route.end_with?("identities.json") }
    refute compile(*articles, blog: { "ledger_group_by" => "month" }).success?
    refute compile(*articles, theme: "docs", features: { "favorites" => true }).success?
  end

  def test_favorites_exist_without_posts_and_reserve_their_route
    result = compile(note("index.md", "---\npublish: true\n---\n# Home"), features: { "favorites" => true })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert page(result, "/favorites/")
    collision = compile(*articles, note("favorites/index.md", "---\npublish: true\n---\n# Mine"), features: { "favorites" => true })
    refute collision.success?
  end
end
