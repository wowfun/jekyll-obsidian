# frozen_string_literal: true

require "test_helper"

class RelationsAndTransclusionTest < Minitest::Test
  def test_links_and_embeds_share_one_typed_relation_model
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n[[target]]\n![[target#Section]]"),
      note("target.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Target\n## Section\nEmbedded text.")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    relations = result.relations.select { |item| item.source_id == "index.md" }
    assert_equal %i[embed link], relations.map(&:kind).sort
    assert_equal ["target.md"], relations.map(&:target_id).uniq
    assert_equal "Section", relations.find { |item| item.kind == :embed }.fragment

    target = page(result, "/target/")
    assert_includes target.data.dig("obsidian", "backlinks").map { |item| item.fetch("id") }, "index.md"
    assert_includes target.data.dig("obsidian", "embedded_by").map { |item| item.fetch("id") }, "index.md"
  end

  def test_repeated_transclusions_have_unique_ids_and_source_links
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n![[target#Section]]\n![[target#Section]]"),
      note("target.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Target\n## Section\nA [self link](#Section).")
    )

    html = page(result, "/").content
    ids = html.scan(/\sid="([^"]+)"/).flatten
    assert_equal ids.uniq, ids
    assert_equal 2, html.scan(/class="obsidian-transclusion obsidian-embed"/).length
    assert_equal 2, html.scan('data-source-id="target.md"').length
    refute_includes html, "<p><section"
  end

  def test_aliases_are_catalog_terms_not_implicit_targets
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n[[Readable Alias]]"),
      note("target.md", "---\npublish: true\naliases: [Readable Alias]\nupdated: 2026-07-30\n---\n# Target")
    )

    assert result.success?
    assert result.diagnostics.any? { |item| item.code == "unresolved_link" }
    assert_includes page(result, "/").content, "obsidian-link--unresolved"
  end

  def test_ambiguous_basename_fails_in_production
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home\n[[same]]"),
      note("a/same.md", "---\npublish: true\n---\n# A"),
      note("b/same.md", "---\npublish: true\n---\n# B")
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "ambiguous_target" }
  end

  def test_missing_embed_is_placeholder_in_development_and_error_in_production
    source = note("index.md", "---\npublish: true\n---\n# Home\n![[missing]]")

    production = compile(source)
    refute production.success?
    assert production.diagnostics.any? { |item| item.code == "missing_embed" }

    development = compile(source, environment: "development")
    assert development.success?
    assert_includes page(development, "/").content, "obsidian-embed--unresolved"
  end

  def test_embed_cycles_fail_in_production
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home\n![[other]]"),
      note("other.md", "---\npublish: true\n---\n# Other\n![[index]]")
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "embed_cycle" }
  end

  def test_wikilink_source_spans_use_character_columns_after_cjk_text
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n中文前缀：[[Architecture|编译器]]、[[Getting Started|开始使用]]。"),
      note("Architecture.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Architecture"),
      note("Getting Started.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Getting Started")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal ["Architecture.md", "Getting Started.md"], result.relations.map(&:target_id).sort
    html = page(result, "/").content
    assert_includes html, "编译器"
    assert_includes html, "开始使用"
  end

  def test_heading_chains_select_the_terminal_heading_and_duplicate_ids_are_stable
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n![[target#Second parent#Repeated]]"),
      note("target.md", <<~MARKDOWN)
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Target
        ## First parent
        ### Repeated
        First body.
        ## Second parent
        ### Repeated
        Second body.
      MARKDOWN
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    target_html = page(result, "/target/").content
    assert_includes target_html, 'id="repeated"'
    assert_includes target_html, 'id="repeated-2"'
    target_document = Nokogiri::HTML5.fragment(target_html)
    assert_equal ["#target", "#first-parent", "#repeated", "#second-parent", "#repeated-2"],
      target_document.css("h1 .anchor, h2 .anchor, h3 .anchor").map { |anchor| anchor["href"] }
    embedded = page(result, "/").content
    assert_includes embedded, "Second body."
    refute_includes embedded, "First body."
    assert_includes embedded, "/target/#repeated-2"
    assert_equal "Second parent#Repeated", result.relations.find { |relation| relation.kind == :embed }.fragment
  end

  def test_missing_fragment_embed_is_fatal_in_production_and_a_placeholder_in_development
    entries = [
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n![[target#Missing section]]"),
      note("target.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Target")
    ]

    production = compile(*entries)
    refute production.success?
    assert production.diagnostics.any? { |item| item.code == "missing_embed_fragment" }

    development = compile(*entries, environment: "development")
    assert development.success?
    assert_includes page(development, "/").content, "obsidian-embed--unresolved"
  end

  def test_heading_and_block_id_collision_is_fatal
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      updated: 2026-07-30
      ---
      # Home
      ## Collision
      A block with the same public anchor. ^collision
    MARKDOWN

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "anchor_collision" }
  end

  def test_numeric_block_ids_can_be_transcluded
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n![[target#^123]]"),
      note("target.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Target\nNumeric block. ^123")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    html = page(result, "/").content
    assert_includes html, "Numeric block."
    assert_includes html, "/target/#123"
  end

  def test_standalone_block_id_attaches_to_the_previous_block
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n![[target#^reading-list]]"),
      note("target.md", <<~MARKDOWN)
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Target

        - First item
        - Second item

        ^reading-list
      MARKDOWN
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    target = Nokogiri::HTML5.fragment(page(result, "/target/").content)
    assert_equal "ul", target.at_css("#reading-list")&.name
    embedded = Nokogiri::HTML5.fragment(page(result, "/").content)
    assert_equal %w[First\ item Second\ item], embedded.css(".obsidian-transclusion__content li").map { |item| item.text.strip }
  end

  def test_standalone_block_id_preserves_a_heading_anchor_and_heading_section
    result = compile(
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Home
        ![[target#Section]]
        ![[target#^heading-block]]
      MARKDOWN
      note("target.md", <<~MARKDOWN)
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Target

        ## Section

        ^heading-block

        Section body.
      MARKDOWN
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    target = Nokogiri::HTML5.fragment(page(result, "/target/").content)
    heading = target.at_css("h2#section")
    refute_nil heading
    assert_equal "#section", heading.at_css("a.anchor")["href"]
    block_anchor = target.at_css("#heading-block")
    assert_equal "span", block_anchor&.name
    assert_equal heading, block_anchor.next_element

    embedded = Nokogiri::HTML5.fragment(page(result, "/").content)
    transclusions = embedded.css(".obsidian-transclusion__content")
    assert_equal 2, transclusions.length
    assert_includes transclusions[0].text, "Section body."
    assert_equal "Section", transclusions[1].text.strip
  end

  def test_callout_and_embed_block_ids_survive_node_replacement
    result = compile(
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Home
        ![[target#^callout-block]]
        ![[target#^folded-block]]
        ![[target#^embedded-block]]
      MARKDOWN
      note("target.md", <<~MARKDOWN),
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Target

        > [!note] Outer callout
        > Outer body.
        > > [!tip] Nested callout
        > > Nested body.

        ^callout-block

        > [!warning]- Folded callout
        > Folded body.

        ^folded-block

        ![[leaf]]

        ^embedded-block
      MARKDOWN
      note("leaf.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Leaf\nLeaf body.")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    target = Nokogiri::HTML5.fragment(page(result, "/target/").content)
    assert_equal "aside", target.at_css("#callout-block")&.name
    assert_equal "details", target.at_css("#folded-block")&.name
    assert_equal "section", target.at_css("#embedded-block")&.name

    embedded = Nokogiri::HTML5.fragment(page(result, "/").content)
    text = embedded.css(".obsidian-transclusion__content").map(&:text).join(" ")
    assert_includes text, "Outer body."
    assert_includes text, "Nested body."
    assert_includes text, "Folded body."
    assert_includes text, "Leaf body."
    refute result.diagnostics.any? { |item| item.code == "block_anchor_realization" }
  end

  def test_list_item_block_transclusion_preserves_its_list_container
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n![[target#^first-item]]"),
      note("target.md", <<~MARKDOWN)
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Target
        - First ^first-item
        - Second
      MARKDOWN
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    embedded = Nokogiri::HTML5.fragment(page(result, "/").content)
    content = embedded.at_css(".obsidian-transclusion__content")
    list = content.at_xpath("./ul")
    refute_nil list
    assert_equal ["First"], list.xpath("./li").map { |item| item.text.strip }
    refute_includes content.text, "Second"
  end
end
