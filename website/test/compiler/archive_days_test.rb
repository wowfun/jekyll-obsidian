# frozen_string_literal: true
require "test_helper"
require "liquid"

class ArchiveDaysTest < Minitest::Test
  def test_day_ui_renders_placeholder_defaults_and_escapes_locale_messages
    source = File.read(File.expand_path("../../_includes/website/archive-day-ui.html", __dir__))
    template = Liquid::Template.parse(source)
    html = template.render!("ui" => {})
    assert_includes html, 'data-date="{month} {day}"'
    assert_includes html, 'data-entry="{count} entry"'
    html = template.render!("ui" => { "ledger_date" => '"<month>' })
    assert_includes html, 'data-date="&quot;&lt;month&gt;"'
  end
end
