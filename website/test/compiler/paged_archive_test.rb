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
    files = result.generated_files.select { |file| file.route.start_with?(prefix) }
    assert_equal false, files.find { |file| file.route.end_with?("manifest.json") }.localize_content
    assert files.select { |file| file.route.include?("facet-") }.all? { |file| file.localize_content == false }
    assert_equal true, files.find { |file| file.route.end_with?(archive.fetch("chunks").first) }.localize_content
    chunk = generated_json(result, prefix + archive.fetch("chunks").first)
    assert_equal "Item 100", chunk.fetch("cards").first.fetch("title")
    assert_equal "Summary", chunk.fetch("cards").first.fetch("summary")
    assert_equal "/garden/items/100.md", chunk.fetch("cards").first.fetch("markdown_url")
    assert_equal 7, archive.fetch("export_max_days")
    assert_equal "Summary", root.data.dig("website", "theme_data", "archive_groups").first.fetch("posts").first.fetch("summary")
    assert_equal "https://example.test/100", chunk.fetch("cards").first.fetch("source_url")
    assert_equal "Hacker News", archive.fetch("facets").fetch("source").first.fetch("name")
    posting = generated_json(result, prefix + archive.fetch("facets").fetch("source").first.fetch("posting"))
    assert_equal 13, Base64.strict_decode64(posting.fetch("bitmap")).bytesize
    assert_equal "/garden/", page(result, "/items/100/").data.dig("website", "routes", "blog")
    assert_equal "2026-10-13T12:00:00+08:00", page(result, "/items/100/").data.dig("website", "published_at")
  end
  def test_archive_note_facets_are_available_with_tag_index_disabled
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("items/a.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-09\ntags: [source/hn, topics/old, topics/agents]\n---\nBody"),
      baseurl: "/garden", home: { "layout" => "archive" }, features: { "tags" => false },
      tag_labels: { "source/hn" => "Hacker News", "topics/agents" => "Agents" },
      tag_aliases: { "topics/old" => "topics/agents" }
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    data = page(result, "/items/a/").data.fetch("website")
    assert_equal false, data.fetch("features").fetch("tags")
    assert_equal [
      { "facet" => "source", "id" => "hn", "name" => "Hacker News" },
      { "facet" => "topic", "id" => "agents", "name" => "Agents" }
    ], data.fetch("archive_facets")
    assert_equal "/garden/", data.fetch("routes").fetch("blog")
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

  def test_archive_facet_names_cannot_collide_with_query_controls
    %w[page year month day].each do |name|
      result = compile(
        note("index.md", "---\npublish: true\n---\n# Home"),
        home: { "layout" => "archive" }, blog: { "facets" => { name => "#{name}/" } }
      )
      refute result.success?, "#{name} must remain an archive query control"
      assert result.diagnostics.any? { |diagnostic| diagnostic.code == "invalid_blog_config" }
    end
  end

  def test_source_url_rejects_unsafe_schemes_and_credentials
    %w[javascript:alert(1) https://user:pass@example.test/].each do |url|
      result = compile(note("index.md", "---\npublish: true\nsource_url: #{url}\n---\n# Hello"))
      refute result.success?
    end
  end

  def test_daily_timeline_uses_local_calendar_dates_and_excludes_undated_posts
    entries = ["2026-01-01T00:30:00Z", "2025-12-31T16:00:00Z", "2025-12-31T15:59:59Z"].each_with_index.map do |date, index|
      note("items/#{index}.md", "---\npublish: true\ncontent_type: post\ndate: #{date}\n---\n# Item #{index}")
    end
    result = compile(*entries, note("items/undated.md", "---\npublish: true\ncontent_type: post\n---\n# Undated"),
      environment: "development", home: { "layout" => "archive" }, blog: { "page_size" => 1, "utc_offset" => "+08:00", "timeline_granularity" => "day" })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    data = page(result, "/").data.dig("website", "theme_data")
    assert_equal({ "2026-01-01" => [0, 2], "2025-12-31" => [2, 3] }, data.dig("archive", "days"))
    assert_equal [
      { "year" => "2026", "count" => 2, "days" => [{ "key" => "2026-01-01", "label" => "01-01", "count" => 2 }] },
      { "year" => "2025", "count" => 1, "days" => [{ "key" => "2025-12-31", "label" => "12-31", "count" => 1 }] }
    ], data.fetch("timeline")
    assert_equal 4, data.dig("archive", "chunks").length
  end

  def test_full_archive_daily_timeline_and_cards_share_local_dates
    result = compile(
      note("items/a.md", "---\npublish: true\ncontent_type: post\ndate: 2025-12-31T17:00:00Z\n---\n# First"),
      note("items/b.md", "---\npublish: true\ncontent_type: post\ndate: 2026-01-02T17:00:00Z\n---\n# Later"),
      blog: { "utc_offset" => "+08:00", "timeline_granularity" => "day" }
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    data = page(result, "/blog/").data.dig("website", "theme_data")
    assert_nil data.fetch("archive")
    assert_equal %w[2026-01-03 2026-01-01], data.fetch("timeline").first.fetch("days").map { |day| day.fetch("key") }
    assert_equal ["2026"], data.fetch("archive_groups").map { |group| group.fetch("label") }
    assert_equal %w[2026-01-03 2026-01-01], data.fetch("archive_groups").first.fetch("posts").map { |card| card.fetch("filter_day") }
  end

  def test_timeline_granularity_rejects_unsupported_values
    result = compile(note("index.md", "---\npublish: true\n---\n# Home"), blog: { "timeline_granularity" => "hour" })
    refute result.success?
    assert result.diagnostics.any? { |diagnostic| diagnostic.code == "invalid_blog_config" }
  end

  def test_monthly_timeline_order_is_consistent_between_paged_and_full_archives
    entries = %w[2026-01-01 2026-03-01 2025-12-31].each_with_index.map do |date, index|
      note("items/#{index}.md", "---\npublish: true\ncontent_type: post\ndate: #{date}\n---\n# Item #{index}")
    end
    full = compile(*entries)
    paged = compile(*entries, blog: { "page_size" => 2 })
    assert full.success?, full.diagnostics.map(&:message).join("\n")
    assert paged.success?, paged.diagnostics.map(&:message).join("\n")
    expected = page(full, "/blog/").data.dig("website", "theme_data", "timeline")
    assert_equal %w[2026-01 2026-03], expected.first.fetch("months").map { |month| month.fetch("key") }
    assert_equal expected, page(paged, "/blog/").data.dig("website", "theme_data", "timeline")
  end

  def test_export_day_limit_is_a_positive_integer
    [0, -1, "7", 1.5].each do |limit|
      result = compile(note("index.md", "---\npublish: true\n---\n# Home"), blog: { "export_max_days" => limit })
      refute result.success?
      assert result.diagnostics.any? { |diagnostic| diagnostic.code == "invalid_blog_config" }
    end
    result = compile(note("index.md", "---\npublish: true\n---\n# Home"), home: { "layout" => "archive" }, blog: { "export_max_days" => 3 })
    assert_equal 3, page(result, "/").data.dig("website", "theme_data", "archive", "export_max_days")
  end
end

class GeneratedFileLocalizationTest < Minitest::Test
  def test_content_policy_comes_from_the_producer_independently_of_the_route
    compiler = JekyllObsidian::LocalizedCompiler.allocate
    compiler.instance_variable_set(:@default_locale, "en")
    content = "{\"url\":\"/a/\",\"id\":\"/literal-id/\"}\n"
    file = JekyllObsidian::GeneratedFile.new(route: "/assets/website/new-index.json", content: content, media_type: "application/json", localize_content: false)
    compiler.define_singleton_method(:localize_data) { |*| raise "Producer marked this content complete" }
    localized = compiler.send(:localize_generated_file, file, "zh-CN")
    assert_equal "/assets/website/i18n/zh-CN/new-index.json", localized.route
    assert_equal content, localized.content
    assert_equal false, localized.localize_content
    # Existing producers default to localization, including URL-bearing JSON.
    ordinary = JekyllObsidian::GeneratedFile.new(route: file.route, content: content, media_type: file.media_type)
    calls = []
    compiler.singleton_class.remove_method(:localize_data)
    compiler.define_singleton_method(:localize_data) do |value, locale|
      calls << [value, locale]
      value.merge("url" => "/zh-CN/a/")
    end
    localized = compiler.send(:localize_generated_file, ordinary, "zh-CN")
    assert_equal [[JSON.parse(content), "zh-CN"]], calls
    assert_equal "/zh-CN/a/", JSON.parse(localized.content).fetch("url")
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
    assert_equal false, result.generated_files.find { |file| file.route == archive.fetch("url").delete_prefix("/garden") }.localize_content
    manifest = generated_json(result, archive.fetch("url").delete_prefix("/garden"))
    assert_equal "agents", manifest.fetch("facets").fetch("topic").first.fetch("id")
    assert_equal "智能体", manifest.fetch("facets").fetch("topic").first.fetch("name")
    prefix = archive.fetch("url").delete_prefix("/garden").delete_suffix("manifest.json")
    card = generated_json(result, prefix + manifest.fetch("chunks").first).fetch("cards").first
    assert_equal "/garden/zh-CN/items/a/", card.fetch("url")
    assert_equal "/garden/zh-CN/items/a.md", card.fetch("markdown_url")
    assert_equal 7, manifest.fetch("export_max_days")
    assert_equal "https://example.test/a", card.fetch("source_url")
  end
end

class PagedArchiveScaleTest < Minitest::Test
  def test_rejects_noncontiguous_dates_and_dated_cards_after_undated_cards
    config = Struct.new(:blog, :site, :features).new(
      { "page_size" => 2, "export_max_days" => 7, "facets" => {} },
      Struct.new(:tag_labels, :tag_aliases).new({}, {}), { "favorites" => false }
    )
    [["2026-01-03", "2026-01-01", "2026-01-03"], [nil, "2026-01-03"]].each do |dates|
      cards = dates.each_with_index.map { |date, index| { "id" => index.to_s, "published_at" => date } }
      error = assert_raises(ArgumentError) { JekyllObsidian::PagedArchive.build(cards, config) }
      assert_includes error.message, "descending with undated cards last"
    end
  end

  def test_one_hundred_thousand_records_use_lazy_postings_and_small_card_chunks
    builder = Object.new
    def builder.href(route) = route
    config = Struct.new(:blog, :site, :url_builder, :features).new(
      { "page_size" => 50, "export_max_days" => 7, "ledger_group_by" => "day", "utc_offset" => "+08:00", "facets" => { "source" => "source/", "topic" => "topics/" } },
      Struct.new(:tag_labels, :tag_aliases).new({}, {}), builder, { "favorites" => true }
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
    identities = JSON.parse(result.fetch("files").find { |file| file.route.end_with?("identities.json") }.content)
    assert_equal 100_000, identities.fetch("ids").length
    assert_operator JSON.generate(identities).bytesize, :<, 1_000_000
  end
  def test_custom_facets_keep_their_name_instead_of_being_labeled_topics
    require "liquid"
    result = compile(note("items/a.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-10\ntags: [read/next]\n---\nBody"),
      home: { "layout" => "archive" }, blog: { "facets" => { "reading" => "read/" } })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    template = Liquid::Template.parse(File.read(File.expand_path("../../_includes/website/archive-facets.html", __dir__)))
    markup = template.render!("page" => page(result, "/").data, "ui" => { "topics" => "Topics" })
    assert_equal ["reading"], Nokogiri::HTML5.fragment(markup).css("nav").map { |node| node["aria-label"] }
  end

end
