# frozen_string_literal: true
require "test_helper"
require "liquid"
require "jekyll_obsidian/template_filters"

class ArchiveDaysTest < Minitest::Test
  def test_reference_time_is_required_immutable_and_replayable
    request = JekyllObsidian::BuildRequest.new(
      snapshot: JekyllObsidian::Snapshot.new(entries: [note("post.md", "---\npublish: true\ncontent_type: post\ndate: 2040-12-31\n---\n# Post")]),
      config: JekyllObsidian::BuildConfig.new(**DEFAULT_CONFIG.merge(home: { "layout" => "archive" })),
      reference_time: Time.utc(2040, 12, 31, 23, 59))
    assert request.reference_time.frozen?
    first = JekyllObsidian::VaultCompiler.compile(request)
    assert first.success?, first.diagnostics.map(&:message).join("\n")
    assert_equal first, JekyllObsidian::VaultCompiler.compile(request)
    assert_equal 2040, page(first, "/").data.dig("website", "theme_data", "ledger_current_year")
    missing = JekyllObsidian::VaultCompiler.compile(request.with(reference_time: nil))
    refute missing.success?
    assert missing.diagnostics.any? { |diagnostic| diagnostic.code == "invalid_request" && diagnostic.message.include?("reference_time") }
  end

  def test_daily_groups_remain_chronological_with_old_pinned_posts
    result = compile(
      note("old-pin.md", "---\npublish: true\ncontent_type: post\ndate: 2025-01-01\npinned: true\n---\n# Pinned"),
      note("old.md", "---\npublish: true\ncontent_type: post\ndate: 2025-01-01\n---\n# Old"),
      note("latest.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-15\n---\n# Latest"),
      blog: { "ledger_group_by" => "day" })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    groups = page(result, "/blog/").data.dig("website", "theme_data", "archive_groups")
    assert_equal %w[2026-10-15 2025-01-01], groups.map { |group| group.fetch("label") }
    assert_equal [true, false], groups.map { |group| group.fetch("open") }
    assert_equal %w[Pinned Old], groups.last.fetch("posts").map { |post| post.fetch("title") }
  end

  def test_all_archives_and_locales_use_the_injected_time_in_the_configured_timezone
    # One instant falls in different years in these offsets. No wall-clock reads
    # or assumptions about unrelated timing calls can affect the expected values.
    reference_time = Time.utc(2040, 12, 31, 16, 30)
    [nil, { "enabled" => false }, { "enabled" => true, "locales" => %w[en zh-CN] }].each do |i18n|
      { "+08:00" => 2041, "-08:00" => 2040 }.each do |offset, year|
        result = compile(
          note("index.md", "---\npublish: true\n---\n# Home"),
          note("news/index.md", "---\npublish: true\ntab:\n  id: news\n  layout: archive\n---\n# News"),
          note("news/post.md", "---\npublish: true\ncontent_type: post\ndate: 2040-12-31\n---\n# Post"),
          locale_manifest("_locale.yml", "name: English\n"),
          locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
          reference_time: reference_time, i18n: i18n,
          home: { "layout" => "archive" }, features: { "favorites" => true },
          blog: { "ledger_group_by" => "day", "utc_offset" => offset })
        assert result.success?, result.diagnostics.map(&:message).join("\n")
        prefixes = i18n && i18n["enabled"] ? ["/", "/zh-CN/"] : ["/"]
        prefixes.each do |prefix|
          [prefix, "#{prefix}news/", "#{prefix}favorites/"].each do |route|
            assert_equal year, page(result, route).data.dig("website", "theme_data", "ledger_current_year"), route
          end
        end
        unless i18n && i18n["enabled"]
          assert_nil page(result, "/").data.dig("website", "i18n", "messages"), "non-localized sites require template defaults"
        end
      end
    end
  end

  def test_day_ui_defaults_match_the_frontend_fixture_and_escape_locale_messages
    source = File.read(File.expand_path("../../_includes/website/archive-day-ui.html", __dir__))
    template = Liquid::Template.parse(source)
    actual = Nokogiri::HTML5.fragment(template.render!("ui" => {})).at_css("template")
    fixture = File.read(File.expand_path("../../tests/frontend/support/archive-day-ui.html", __dir__))
    expected = Nokogiri::HTML5.fragment(fixture).at_css("template")
    assert_equal expected.attributes.transform_values(&:value), actual.attributes.transform_values(&:value)
    html = template.render!("ui" => { "ledger_date" => '"<month>' })
    assert_includes html, 'data-date="&quot;&lt;month&gt;"'
  end

  def day_heading(date, count, messages = {})
    @heading_template ||= Liquid::Template.parse(File.read(File.expand_path("../../_includes/website/archive-day.html", __dir__))).tap do |template|
      # Stub only this template's row include, without changing Liquid's global
      # registry (which may contain either Liquid or Jekyll include tags).
      template.root.nodelist.grep(Liquid::Tag).select { |tag| tag.tag_name == "include" }.each do |tag|
        tag.define_singleton_method(:render) { |_context| "" }
      end
    end
    day = date && Date.iso8601(date)
    group = { "label" => date || "Undated", "posts" => Array.new(count), "open" => true }
    group["day"] = { "year" => day.year, "month" => day.month, "day" => day.day, "weekday" => day.wday } if day
    html = @heading_template.render!({ "include" => { "group" => group }, "ui" => messages,
      "page" => { "website" => { "theme_data" => { "ledger_current_year" => 2026 } } } }, filters: [JekyllObsidian::TemplateFilters])
    Nokogiri::HTML5.fragment(html)
  end

  def test_liquid_heading_defaults_work_without_localization
    heading = day_heading("2026-10-15", 2)
    assert_equal "October 15", heading.at_css("h2").text
    assert_equal "2026-10-15", heading.at_css("time")["datetime"]
    assert_equal "Thursday · 2 entries", heading.at_css(".archive-day__meta").text
    assert_equal "December 31, 2025", day_heading("2025-12-31", 1).at_css("h2").text
    assert_equal "Undated", day_heading(nil, 0).at_css("h2").text
  end

  def test_month_names_are_literal_substitutions
    ['Oct$& {day} {year}', 'Oct\\& {month}'].each do |name|
      months = Array.new(12, "Month"); months[9] = name
      assert_equal "#{name} 15", day_heading("2026-10-15", 1, "ledger_months" => months.join("|")).at_css("h2").text
    end
  end

  def test_liquid_heading_localizes_month_weekday_count_and_old_years
    messages = Psych.safe_load_file(File.expand_path("../../jekyll-obsidian-docs/_translations/zh-CN/_locale.yml", __dir__)).fetch("messages")
    heading = day_heading("2026-10-15", 30, messages)
    assert_equal "10月15日", heading.at_css("h2").text
    assert_equal "星期四 · 30 条", heading.at_css(".archive-day__meta").text
    assert_equal "2025年12月31日", day_heading("2025-12-31", 1, messages).at_css("h2").text
    assert_equal "未注明日期", day_heading(nil, 0, messages).at_css("h2").text
  end
end
