# frozen_string_literal: true
require "test_helper"
require "liquid"

class ArchiveDaysTest < Minitest::Test
  def test_home_tabs_and_favorites_use_one_year_when_render_crosses_new_year
    before_midnight = Time.new(2026, 12, 31, 23, 59, 59, "+08:00")
    after_midnight = before_midnight + 1
    reads = 0
    clock = -> { reads += 1; reads <= 2 ? before_midnight : after_midnight }
    original_now = Time.method(:now)
    begin
      Time.define_singleton_method(:now, clock)
      result = compile(
        note("index.md", "---\npublish: true\n---\n# Home"),
        note("news/index.md", "---\npublish: true\ntab:\n  id: news\n  layout: archive\n---\n# News"),
        note("news/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-12-31\n---\n# Post"),
        home: { "layout" => "archive" }, features: { "favorites" => true },
        blog: { "ledger_group_by" => "day", "utc_offset" => "+08:00" })
    ensure
      Time.define_singleton_method(:now, original_now)
    end
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal [2026, 2026, 2026], %w[/ /news/ /favorites/].map { |route| page(result, route).data.dig("website", "theme_data", "ledger_current_year") }
    assert_nil page(result, "/").data.dig("website", "i18n", "messages"), "non-localized sites require template defaults"
  end

  def test_day_ui_renders_placeholder_defaults_and_escapes_locale_messages
    source = File.read(File.expand_path("../../_includes/website/archive-day-ui.html", __dir__))
    template = Liquid::Template.parse(source)
    html = template.render!("ui" => {})
    assert_includes html, 'data-date="{month} {day}"'
    assert_includes html, 'data-entry="{count} entry"'
    html = template.render!("ui" => { "ledger_date" => '"<month>' })
    assert_includes html, 'data-date="&quot;&lt;month&gt;"'
  end

  def test_locales_share_the_same_year_when_localized_compilation_crosses_new_year
    before_midnight = Time.new(2026, 12, 31, 23, 59, 59, "+08:00")
    reads = 0
    clock = -> { reads += 1; reads == 1 ? before_midnight : before_midnight + 1 }
    original_now = Time.method(:now)
    begin
      Time.define_singleton_method(:now, clock)
      result = compile(
        note("index.md", "---\npublish: true\n---\n# Home"),
        note("post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-12-31\n---\n# Post"),
        locale_manifest("_locale.yml", "name: English\n"),
        locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
        home: { "layout" => "archive" }, blog: { "ledger_group_by" => "day", "utc_offset" => "+08:00" },
        i18n: { "enabled" => true, "locales" => %w[en zh-CN] })
    ensure
      Time.define_singleton_method(:now, original_now)
    end
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal [2026, 2026], %w[/ /zh-CN/].map { |route| page(result, route).data.dig("website", "theme_data", "ledger_current_year") }
  end

  def day_heading(date, count, messages = {})
    # Isolate the Liquid heading; the nested row include is covered by site builds.
    source = File.read(File.expand_path("../../_includes/website/archive-day.html", __dir__)).split("{% include website/blog-ledger.html", 2).first
    day = date && Date.iso8601(date)
    group = { "label" => date || "Undated", "posts" => Array.new(count), "open" => true }
    group["day"] = { "year" => day.year, "month" => day.month, "day" => day.day, "weekday" => day.wday } if day
    html = Liquid::Template.parse(source).render!("include" => { "group" => group }, "ui" => messages,
      "page" => { "website" => { "theme_data" => { "ledger_current_year" => 2026 } } })
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

  def test_liquid_heading_localizes_month_weekday_count_and_old_years
    messages = Psych.safe_load_file(File.expand_path("../../jekyll-obsidian-docs/_translations/zh-CN/_locale.yml", __dir__)).fetch("messages")
    heading = day_heading("2026-10-15", 30, messages)
    assert_equal "10月15日", heading.at_css("h2").text
    assert_equal "星期四 · 30 条", heading.at_css(".archive-day__meta").text
    assert_equal "2025年12月31日", day_heading("2025-12-31", 1, messages).at_css("h2").text
    assert_equal "未注明日期", day_heading(nil, 0, messages).at_css("h2").text
  end
end
