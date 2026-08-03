# frozen_string_literal: true

require "test_helper"

class LinkSecurityTest < Minitest::Test
  def test_markdown_path_escape_is_fatal_in_production
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      updated: 2026-07-30
      ---
      # Home
      [plain escape](../../private.md)
      [encoded escape](..%2F..%2Fprivate.md)
    MARKDOWN

    refute result.success?
    escapes = result.diagnostics.select { |item| item.code == "path_escape" }
    assert_equal 2, escapes.length
    assert escapes.all? { |item| item.severity == :error }
    assert_instance_of JekyllObsidian::BuildFailure, result
    refute result.diagnostics.any? { |item| item.code == "unresolved_link" }
  end

  def test_markdown_path_escape_is_a_placeholder_warning_in_development
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home\n[escape](../../private.md)"),
      environment: "development"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    diagnostic = result.diagnostics.find { |item| item.code == "path_escape" }
    refute_nil diagnostic
    assert_equal :warning, diagnostic.severity
    assert_includes page(result, "/").content, "website-link--unresolved"
  end

  def test_missing_markdown_link_remains_distinct_from_path_escape
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n[missing](missing.md)")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert result.diagnostics.any? { |item| item.code == "unresolved_link" && item.severity == :warning }
    refute result.diagnostics.any? { |item| item.code == "path_escape" }
    assert_includes page(result, "/").content, "website-link--unresolved"
  end

  def test_relative_markdown_link_can_move_up_without_escaping_the_vault
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("Guides/one.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# One\n[home](../index.md)")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    refute result.diagnostics.any? { |item| item.code == "path_escape" }
    assert_includes page(result, "/Guides/one/").content, 'href="/"'
  end
end
