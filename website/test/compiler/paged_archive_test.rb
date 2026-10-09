# frozen_string_literal: true
require "test_helper"
require "base64"
class PagedArchiveTest < Minitest::Test
  def test_root_archive_chunks_facets_and_source_url
    entries = [note("index.md", "---\npublish: true\n---\n# Home")] + (0...101).map do |i|
      note("items/#{i}.md", "---\npublish: true\ncontent_type: post\ntitle: Item #{i}\ndate: #{(DateTime.iso8601('2026-10-09T00:00:00Z') + Rational(i, 24)).iso8601}\ntags: [source/hn, topics/agents]\nsource_url: https://example.test/#{i}\n---\nSummary")
    end
    result = compile(*entries, baseurl: "/garden", home: { "layout" => "archive" }, blog: { "page_size" => 50, "utc_offset" => "+08:00" }, tag_labels: { "source/hn" => "Hacker News", "topics/agents" => "Agents" })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    root = page(result, "/")
    assert_equal "blog-index", root.data.dig("website", "kind")
    refute page(result, "/blog/")
    archive = root.data.dig("website", "theme_data", "archive")
    assert_equal 101, archive.fetch("total")
    assert_equal 3, archive.fetch("chunks").length
    assert_equal 50, root.data.dig("website", "theme_data", "archive_groups").sum { |g| g.fetch("posts").length }
    prefix = archive.fetch("url").delete_prefix("/garden").delete_suffix("manifest.json")
    chunk = generated_json(result, prefix + archive.fetch("chunks").first)
    assert_equal "Item 100", chunk.fetch("cards").first.fetch("title")
    assert_equal "https://example.test/100", chunk.fetch("cards").first.fetch("source_url")
    assert_equal "Hacker News", archive.fetch("facets").fetch("source").first.fetch("name")
    posting = generated_json(result, prefix + archive.fetch("facets").fetch("source").first.fetch("posting"))
    assert_equal 13, Base64.strict_decode64(posting.fetch("bitmap")).bytesize
    assert_equal "/garden/", page(result, "/items/100/").data.dig("website", "routes", "blog")
    assert_equal "2026-10-13T12:00:00+08:00", page(result, "/items/100/").data.dig("website", "published_at")
  end
  def test_undated_posts_follow_dated_posts_in_paged_archives
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("items/undated.md", "---\npublish: true\ncontent_type: post\n---\n# Undated"),
      note("items/dated.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-09\n---\n# Dated"),
      environment: "development", home: { "layout" => "archive" }
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal %w[2026 Undated], page(result, "/").data.dig("website", "theme_data", "archive_groups").map { |group| group.fetch("label") }
  end

  def test_source_url_rejects_unsafe_schemes_and_credentials
    %w[javascript:alert(1) https://user:pass@example.test/].each do |url|
      result = compile(note("index.md", "---\npublish: true\nsource_url: #{url}\n---\n# Hello"))
      refute result.success?
    end
  end
end

class PagedArchiveLocalizedTest < Minitest::Test
  def test_localized_archive_asset_routes_and_shared_stable_facet_ids
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("items/a.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-09\ntags: [source/hn, topics/agents]\nsource_url: https://example.test/a\n---\n# English"),
      note("_translations/zh-CN/items/a.md", "---\ntitle: 中文\n---\n正文"),
      locale_manifest("_locale.yml", "name: English\ntag_labels:\n  topics/agents: Agents\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\ntag_labels:\n  topics/agents: 智能体\n"),
      baseurl: "/garden", i18n: { "enabled" => true, "locales" => %w[en zh-CN] }, home: { "layout" => "archive" }, blog: { "page_size" => 50 }
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    archive = page(result, "/zh-CN/").data.dig("website", "theme_data", "archive")
    assert_includes archive.fetch("url"), "/garden/assets/website/i18n/zh-CN/archive/"
    manifest = generated_json(result, archive.fetch("url").delete_prefix("/garden"))
    assert_equal "agents", manifest.fetch("facets").fetch("topic").first.fetch("id")
    assert_equal "智能体", manifest.fetch("facets").fetch("topic").first.fetch("name")
    prefix = archive.fetch("url").delete_prefix("/garden").delete_suffix("manifest.json")
    card = generated_json(result, prefix + manifest.fetch("chunks").first).fetch("cards").first
    assert_equal "/garden/zh-CN/items/a/", card.fetch("url")
    assert_equal "https://example.test/a", card.fetch("source_url")
  end
end

class PagedArchiveScaleTest < Minitest::Test
  def test_one_hundred_thousand_records_use_lazy_postings_and_small_card_chunks
    builder = Object.new
    def builder.href(route) = route
    config = Struct.new(:blog, :site, :url_builder).new(
      { "page_size" => 50, "utc_offset" => "+08:00", "facets" => { "source" => "source/", "topic" => "topics/" } },
      Struct.new(:tag_labels, :tag_aliases).new({}, {}), builder
    )
    cards = Array.new(100_000) do |i|
      { "id" => i.to_s, "title" => "Record #{i}", "url" => "/items/#{i}/", "published_at" => "2026-10-09T00:00:00Z", "tags" => ["source/hn", "topics/agents"] }
    end
    result = JekyllObsidian::PagedArchive.build(cards, config)
    manifest = result.fetch("archive")
    assert_equal 2_000, manifest.fetch("chunks").length
    assert_operator JSON.generate(manifest).bytesize, :<, 50_000
    assert_equal 50, result.fetch("archive_groups").first.fetch("posts").length
    posting = JSON.parse(result.fetch("files").find { |file| file.route.end_with?(manifest.fetch("facets").fetch("source").first.fetch("posting")) }.content)
    assert_equal 12_500, Base64.strict_decode64(posting.fetch("bitmap")).bytesize
  end
end
