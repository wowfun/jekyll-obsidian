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
    ledger = page(result, "/").data.dig("website", "theme_data", "archive_groups").flat_map { |group| group.fetch("posts") }
    assert_equal en.fetch("favorite_card"), ledger.find { |card| card.fetch("id") == en.fetch("id") }.fetch("favorite_card")
    assert ledger.all? { |card| !card.fetch("favorite_card").key?("archive_facets") }
    %w[en zh-CN].each do |locale|
      route = locale == "en" ? "/favorites/" : "/zh-CN/favorites/"
      archive = page(result, route).data.dig("website", "theme_data", "archive")
      descriptor_route = archive.fetch("current_url").delete_prefix("/garden")
      descriptor = result.generated_files.find { |file| file.route == descriptor_route }
      assert_equal archive.fetch("url"), JSON.parse(descriptor.content).fetch("url")
    end

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
  def test_lookup_only_favorites_do_not_emit_remote_filter_postings
    result = compile(*articles, features: { "favorites" => true })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    refute result.generated_files.any? { |file| file.route.include?("/facet-") }
    archive = page(result, "/favorites/").data.dig("website", "theme_data", "archive")
    assert archive.fetch("facets").values.flatten.none? { |option| option.key?("posting") }
    assert result.generated_files.any? { |file| file.route.end_with?("identities.json") }
  end

  def test_lookup_only_favorites_keep_chronology_separate_from_pinned_display
    result = compile(
      note("items/new.md", "---\npublish: true\ncontent_type: post\ndate: 2026-01-02\n---\n# New"),
      note("items/old.md", "---\npublish: true\ncontent_type: post\ndate: 2025-12-31\npinned: true\n---\n# Old"),
      note("items/undated.md", "---\npublish: true\ncontent_type: post\npinned: true\n---\n# Undated"),
      environment: "development", features: { "favorites" => true })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    archive = page(result, "/favorites/").data.dig("website", "theme_data", "archive")
    assert_equal({ "2026" => [0, 1], "2025" => [1, 2], "Undated" => [2, 3] }, archive.fetch("years"))
    assert_equal({ "2026-01-02" => [0, 1], "2025-12-31" => [1, 2] }, archive.fetch("days"))
    chunk = result.generated_files.find { |file| file.route.end_with?("cards-0.json") }
    assert_equal %w[New Old Undated], JSON.parse(chunk.content).fetch("cards").map { |card| card.fetch("title") }
    displayed = page(result, "/").data.dig("website", "theme_data", "recent_posts")
    assert_equal %w[Old Undated New], displayed.map { |card| card.fetch("title") }
    assert_equal page(result, "/items/old/").data.dig("website", "favorite_card"), displayed.first.fetch("favorite_card")
  end

  def test_paged_cards_omit_unused_favorite_snapshots_when_the_feature_is_disabled
    result = compile(*articles, blog: { "page_size" => 2 })
    assert result.success?
    cards = page(result, "/blog/").data.dig("website", "theme_data", "archive_groups").flat_map { |group| group.fetch("posts") }
    assert cards.none? { |card| card.key?("favorite_labels") || card.key?("favorite_card") }
  end

end
