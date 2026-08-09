# frozen_string_literal: true

require "test_helper"

class FrontmatterPropertyLinksTest < Minitest::Test
  def test_custom_property_wiki_links_join_the_existing_relation_model_without_reaching_page_data
    result = compile(
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        project: "[[projects/alpha|Alpha project]]"
        references:
          - background
          - "[[notes/context]]"
        aliases:
          - "[[catalog-only]]"
        tags:
          - "[[taxonomy-only]]"
        ---
        # Home
      MARKDOWN
      note("projects/alpha.md", "---\npublish: true\n---\n# Alpha"),
      note("notes/context.md", "---\npublish: true\n---\n# Context"),
      note("catalog-only.md", "---\npublish: true\n---\n# Catalog only"),
      note("taxonomy-only.md", "---\npublish: true\n---\n# Taxonomy only")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    source_relations = result.relations.select { |relation| relation.source_id == "index.md" }
    assert_equal %w[notes/context.md projects/alpha.md], source_relations.map(&:target_id).sort
    assert source_relations.all? { |relation| relation.kind == :link }

    home = page(result, "/")
    assert_equal %w[notes/context.md projects/alpha.md],
      home.data.dig("website", "links").map { |link| link.fetch("id") }.sort
    public_data = JSON.generate(home.data)
    refute_includes public_data, '"project":'
    refute_includes public_data, '"references":'
    assert_equal ["index.md"], page(result, "/projects/alpha/").data.dig("website", "backlinks").map { |link| link.fetch("id") }
  end

  def test_custom_property_wiki_links_require_complete_double_quoted_scalars
    single_quoted = compile(
      note("index.md", "---\npublish: true\nproject: '[[target]]'\n---\n# Home"),
      note("target.md", "---\npublish: true\n---\n# Target")
    )
    refute single_quoted.success?
    assert(single_quoted.diagnostics.any? do |item|
      item.code == "invalid_property" && item.message == "project wiki links must use double-quoted YAML strings"
    end)

    unquoted = compile(
      note("index.md", "---\npublish: true\nproject: [[target]]\n---\n# Home"),
      note("target.md", "---\npublish: true\n---\n# Target")
    )
    refute unquoted.success?
    assert(unquoted.diagnostics.any? do |item|
      item.code == "invalid_property" && item.message == "project wiki links must use double-quoted YAML strings"
    end)

    embedded = compile(
      note("index.md", "---\npublish: true\nproject: 'prefix [[target]]'\n---\n# Home"),
      note("target.md", "---\npublish: true\n---\n# Target")
    )
    assert embedded.success?, embedded.diagnostics.map(&:message).join("\n")
    assert_empty embedded.relations
  end

  def test_custom_property_names_cannot_inject_control_characters_into_diagnostics
    result = compile(
      note(
        "index.md",
        "---\npublish: true\n" \
          "\"bad\\e[31mkey\": \"[[missing]]\"\n" \
          "\"line\\nkey\": value\n" \
          "\"line\\u2028separator\": value\n" \
          "\"paragraph\\u2029separator\": value\n" \
          "\"\\u00a0leading-space\": value\n" \
          "\"trailing-space\\u3000\": value\n" \
          "---\n# Home"
      ),
      environment: "development"
    )

    refute result.success?
    invalid = result.diagnostics.select { |item| item.code == "invalid_property" }
    assert_equal 6, invalid.length
    expected_message =
      "custom property names must be non-empty NFC text without leading, trailing, or control characters"
    assert invalid.all? { |item| item.message == expected_message }
    diagnostic_text = invalid.map(&:message).join("\n")
    refute_includes diagnostic_text, "\e"
    refute_includes diagnostic_text, "line\nkey"
    refute result.diagnostics.any? { |item| item.code == "unresolved_property_link" }
  end

  def test_frontmatter_and_body_diagnostics_remain_distinct_when_their_spans_match
    result = compile(
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        project: "[[dup]]"
        ---
        # Home

        xxxxxxxxx[[dup|xx]]
      MARKDOWN
      note("a/dup.md", "---\npublish: true\n---\n# First duplicate"),
      note("b/dup.md", "---\npublish: true\n---\n# Second duplicate"),
      environment: "development"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    ambiguous = result.diagnostics.select { |item| item.code == "ambiguous_target" }
    assert_equal 2, ambiguous.length
    assert_equal [nil, "project"], ambiguous.map(&:property).sort_by(&:to_s)
    assert_equal 1, ambiguous.map { |item| item.span.to_h }.uniq.length
  end

  def test_related_projects_resolved_notes_in_authored_order_without_repeating_direct_links
    entries = [
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        related:
          - "[[blog/second]]"
          - "[[blog/first|Read the first article]]"
          - "[[blog/second|Duplicate label]]"
        ---
        # Home
      MARKDOWN
      note("blog/first.md", "---\npublish: true\ncontent_type: post\ndate: 2026-01-01\ndescription: First summary.\n---\n# First article"),
      note("blog/second.md", "---\npublish: true\ncontent_type: post\ndate: 2026-02-01\ndescription: Second summary.\n---\n# Second article")
    ]

    result = compile(*entries)

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    related = page(result, "/").data.dig("website", "related_articles")
    assert_equal %w[blog/second.md blog/first.md], related.map { |article| article.fetch("id") }
    assert_equal ["Second article", "Read the first article"], related.map { |article| article.fetch("title") }
    assert_equal ["/blog/second/", "/blog/first/"], related.map { |article| article.fetch("url") }
    assert_empty page(result, "/").data.dig("website", "links")
    assert_equal ["index.md"], page(result, "/blog/first/").data.dig("website", "backlinks").map { |link| link.fetch("id") }

    without_relation_rail = compile(*entries, features: { "relations" => false })
    assert without_relation_rail.success?, without_relation_rail.diagnostics.map(&:message).join("\n")
    assert_equal %w[blog/second.md blog/first.md],
      page(without_relation_rail, "/").data.dig("website", "related_articles").map { |article| article.fetch("id") }
    assert_empty page(without_relation_rail, "/").data.dig("website", "links")
  end

  def test_related_is_a_strict_double_quoted_wiki_link_list
    scalar = compile(note("index.md", "---\npublish: true\nrelated: \"[[target]]\"\n---\n# Home"))
    refute scalar.success?
    assert scalar.diagnostics.any? { |item| item.message == "related must be an array of double-quoted wiki links" }

    unquoted = compile(note("index.md", "---\npublish: true\nrelated:\n  - [[target]]\n---\n# Home"))
    refute unquoted.success?
    assert unquoted.diagnostics.any? { |item| item.message == "related wiki links must use double-quoted YAML strings" }

    ordinary = compile(note("index.md", "---\npublish: true\nrelated:\n  - target\n---\n# Home"))
    refute ordinary.success?
    assert ordinary.diagnostics.any? { |item| item.message == "related entries must use [[target]] or [[target|label]] syntax" }

    unsafe_label = compile(
      note("index.md", "---\npublish: true\nrelated:\n  - \"[[target|bad\\u0001label]]\"\n---\n# Home"),
      note("target.md", "---\npublish: true\n---\n# Target")
    )
    refute unsafe_label.success?
    assert(unsafe_label.diagnostics.any? do |item|
      item.code == "invalid_property" &&
        item.message == "related entries must contain only output-safe Unicode characters"
    end)
  end

  def test_broken_related_targets_fail_production_and_are_omitted_in_development
    source = note("index.md", "---\npublish: true\nrelated:\n  - \"[[missing]]\"\n---\n# Home")

    production = compile(source)
    refute production.success?
    assert(production.diagnostics.any? do |item|
      item.code == "unresolved_related" && item.severity == :error
    end)

    development = compile(source, environment: "development")
    assert development.success?, development.diagnostics.map(&:message).join("\n")
    assert(development.diagnostics.any? do |item|
      item.code == "unresolved_related" && item.severity == :warning
    end)
    assert_empty page(development, "/").data.dig("website", "related_articles")
  end

  def test_related_rejects_self_references_and_missing_fragments
    self_reference = compile(note("index.md", "---\npublish: true\nrelated:\n  - \"[[index]]\"\n---\n# Home"))
    refute self_reference.success?
    assert self_reference.diagnostics.any? { |item| item.code == "related_self_reference" }

    fragment_self_reference = compile(
      note("index.md", "---\npublish: true\nrelated:\n  - \"[[#Section]]\"\n---\n# Home\n\n## Section")
    )
    refute fragment_self_reference.success?
    assert fragment_self_reference.diagnostics.any? { |item| item.code == "related_self_reference" }

    missing_fragment = compile(
      note("index.md", "---\npublish: true\nrelated:\n  - \"[[target#Missing]]\"\n---\n# Home"),
      note("target.md", "---\npublish: true\n---\n# Target")
    )
    refute missing_fragment.success?
    assert missing_fragment.diagnostics.any? { |item| item.code == "unresolved_related_fragment" }
  end
end
