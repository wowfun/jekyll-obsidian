# frozen_string_literal: true

require "test_helper"

class DateBasisTest < Minitest::Test
  def test_date_basis_accepts_only_explicit_published_or_observed_values
    %w[published observed].each do |basis|
      parsed = JekyllObsidian::FrontMatter.parse("post.md", "---\ndate_basis: #{basis}\n---\nBody")
      assert_empty parsed.diagnostics
      assert_equal basis, parsed.properties.fetch("date_basis")
    end
    ["unknown", "observed ", "[[target]]", nil, true, 0, [], {}].each do |basis|
      parsed = JekyllObsidian::FrontMatter.parse("post.md", "---\ndate_basis: #{JSON.generate(basis)}\n---\nBody")
      assert parsed.diagnostics.any? { |diagnostic| diagnostic.code == "invalid_property" }, basis.inspect
      refute parsed.properties.key?("date_basis")
      assert_empty parsed.property_links
    end
  end

  def test_date_basis_is_reserved_and_never_a_custom_display_field
    assert_includes JekyllObsidian::FrontMatter::SUPPORTED, "date_basis"
    result = compile(note("index.md", "---\npublish: true\ndate_basis: observed\n---\n# Home"))
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal "observed", page(result, "/").data.dig("website", "date_basis")
    assert_empty page(result, "/").data.dig("website", "display_properties")
  end

  def test_translation_inherits_the_default_notes_authored_date_basis
    result = compile(*localized_notes("title: 首页\n"), i18n: { "enabled" => true, "locales" => %w[en zh-CN] })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal "observed", page(result, "/zh-CN/").data.dig("website", "date_basis")
  end

  def test_translation_cannot_change_the_meaning_of_the_default_notes_date
    result = compile(*localized_notes("date_basis: published\n"), i18n: { "enabled" => true, "locales" => %w[en zh-CN] })
    refute result.success?
    assert result.diagnostics.any? { |diagnostic| diagnostic.code == "localized_structure_override" && diagnostic.message.include?("date_basis") }
  end

  def test_a_git_publication_date_does_not_imply_observation_time
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("post.md", "---\npublish: true\ncontent_type: post\n---\nBody", first_committed_at: "2026-10-10T00:00:00Z")
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal "2026-10-10T00:00:00Z", page(result, "/post/").data.dig("website", "published_at")
    assert_nil page(result, "/post/").data.dig("website", "date_basis")
  end

  private

  def localized_notes(translation)
    [
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("index.md", "---\npublish: true\ndate_basis: observed\n---\n# Home"),
      note("_translations/zh-CN/index.md", "---\n#{translation}---\n# 首页")
    ]
  end
end
