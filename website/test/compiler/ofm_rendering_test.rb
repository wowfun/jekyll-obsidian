# frozen_string_literal: true

require "test_helper"

class OfmRenderingTest < Minitest::Test
  def test_non_folding_callout_is_a_note_not_a_nested_complementary_landmark
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      updated: 2026-07-30
      ---
      # Home
      > [!tip] Accessible callout
      > Supporting text.
    MARKDOWN

    html = page(result, "/").content
    assert_includes html, '<aside class="website-callout website-callout--tip callout" data-callout="tip" role="note">'
  end

  def test_comments_and_embeds_inside_code_or_raw_html_are_not_interpreted
    result = compile(
      note("index.md", <<~'MARKDOWN'),
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Home
        %% hidden source comment %%
        <!-- hidden html comment -->
        <!-- multiline html secret
        still hidden -->
        `![[target]]` and `%% visible code %%`

        ```sh
        ![[target]]
        %% visible fenced code %%
        ```

        <div>
        ![[target]] remains authored raw HTML text.
        </div>

        ![[target]]
      MARKDOWN
      note("target.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Target\nEmbedded once.")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal 1, result.relations.count { |relation| relation.kind == :embed }
    html = page(result, "/").content
    refute_includes html, "hidden source comment"
    refute_includes html, "hidden html comment"
    refute_includes html, "multiline html secret"
    refute_includes html, "still hidden"
    assert_includes html, "visible code"
    refute_includes html, "JEKYLL_OBSIDIAN_CODE_"
    assert_includes html, "![[target]] remains authored raw HTML text."
    assert_equal 1, html.scan("Embedded once.").length
    search = generated_json(result, "/assets/website/search.v1.json")
    refute_includes search.fetch("documents").first.fetch("text"), "JEKYLL_OBSIDIAN_CODE_"
  end

  def test_inline_tags_join_frontmatter_but_code_comments_and_html_do_not
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("blog/tags.md", <<~MARKDOWN),
      ---
      publish: true
      content_type: post
      date: 2026-07-30
      tags: [frontmatter]
      updated: 2026-07-30
      ---
      # Home
      Visible #field-notes and #guide/syntax.
      `#inline-code`

      ```text
      #fenced-code
      ```

      %% #comment-tag %%
      <div>
      #raw-html-tag
      </div>
      MARKDOWN
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    catalog = generated_json(result, "/assets/website/catalog.v1.json")
    tags = catalog.fetch("notes").first.fetch("tags")
    assert_equal ["field-notes", "frontmatter", "guide/syntax"], tags
    tag_names = page(result, "/blog/").data.dig("website", "theme_data", "topic_summaries")
      .map { |topic| topic.fetch("name") }
    assert_includes tag_names, "field-notes"
    refute_includes tag_names, "inline-code"
    refute_includes tag_names, "comment-tag"
    refute_includes tag_names, "raw-html-tag"
  end

  def test_block_ids_folded_custom_callouts_math_and_mermaid_survive
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      updated: 2026-07-30
      ---
      # Home
      A reference block. ^reference-block

      > [!field-observation]- Folded title
      > Folded body.

      Inline $a+b$.

      ```mermaid
      flowchart LR
        A --> B
      ```
    MARKDOWN

    html = page(result, "/").content
    assert_includes html, 'id="reference-block"'
    assert_includes html, '<details class="website-callout website-callout--field-observation callout"'
    assert_includes html, "Folded title"
    assert_includes html, "data-math-style"
    assert_includes html, "data-website-mermaid"
  end

  def test_custom_task_states_remain_distinguishable_and_accessible
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      updated: 2026-07-30
      ---
      # Home
      - [ ] Open
      - [x] Done
      - [?] Question
      - [/] In progress
      - [-] Cancelled
    MARKDOWN

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    document = Nokogiri::HTML5.fragment(page(result, "/").content)
    states = document.css("li.task-list-item").map { |item| item["data-task"] }
    assert_equal [" ", "x", "?", "/", "-"], states
    custom = document.at_css('li[data-task="?"] input')
    assert_equal "?", custom["data-task"]
    assert_equal "Task state: question", custom["aria-label"]
    refute custom.key?("checked")
    assert document.at_css('li[data-task="x"] input').key?("checked")
  end

  def test_raw_html_never_shifts_markdown_owned_transforms
    result = compile(
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Markdown heading
        <h2>Raw heading</h2>

        ## Markdown section

        <blockquote><p>[!warning] Raw quote</p></blockquote>

        > [!tip] Markdown callout
        > Body.

        <ul><li class="task-list-item"><input class="task-list-item-checkbox">Raw task</li></ul>

        > - [?] Quoted task

        <pre><code>raw code</code></pre>

        ```mermaid
        graph LR
        ```

        <a data-wikilink="true" href="/raw/">Raw link</a>
        [[target|Markdown link]]
      MARKDOWN
      note("target.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Target")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    document = Nokogiri::HTML5.fragment(page(result, "/").content)
    raw_heading = document.css("h2").find { |node| node.text == "Raw heading" }
    markdown_heading = document.css("h2").find { |node| node.text.include?("Markdown section") }
    refute_nil raw_heading
    refute_nil markdown_heading
    assert_nil raw_heading["id"]
    assert_equal "markdown-section", markdown_heading["id"]
    raw_quote = document.css("blockquote").find { |node| node.text.include?("Raw quote") }
    refute_nil raw_quote
    assert_equal "blockquote", raw_quote.name
    assert_equal "aside", document.at_css("aside[data-callout='tip']").name
    raw_task = document.css("li").find { |node| node.text.include?("Raw task") }
    quoted_task = document.css("li").find { |node| node.text.include?("Quoted task") }
    raw_code = document.css("pre").find { |node| node.text.include?("raw code") }
    assert_nil raw_task["data-task"]
    assert_equal "?", quoted_task["data-task"]
    assert_nil raw_code["lang"]
    assert_equal "mermaid", document.at_css("pre[data-website-mermaid]")["lang"]
    assert_equal "/raw/", document.css("a").find { |node| node.text == "Raw link" }["href"]
    assert_equal "/target/", document.css("a").find { |node| node.text == "Markdown link" }["href"]
    assert_empty document.css("[data-sourcepos]")
  end

  def test_indented_code_does_not_publish_embeds_or_index_tags
    result = compile(
      note("index.md", <<~'MARKDOWN'),
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Home

            ![[media/private.png]] #private-code-tag

        >     ![[media/private.png]] #private-quote-code-tag

        \![[media/private.png]] \#private-escaped-tag
      MARKDOWN
      attachment("media/private.png", "PRIVATE-ASSET", media_type: "image/png"),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_empty result.copied_assets
    assert_empty result.relations
    assert_includes page(result, "/").content, "![[media/private.png]] #private-code-tag"
    refute_includes generated_json(result, "/assets/website/catalog.v1.json").fetch("notes").first.fetch("tags"), "private-code-tag"
    refute_includes generated_json(result, "/assets/website/catalog.v1.json").fetch("notes").first.fetch("tags"), "private-quote-code-tag"
    refute_includes generated_json(result, "/assets/website/catalog.v1.json").fetch("notes").first.fetch("tags"), "private-escaped-tag"
  end

  def test_block_id_does_not_merge_adjacent_list_items
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      updated: 2026-07-30
      ---
      # Home
      - First ^first
      - Second
    MARKDOWN

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    document = Nokogiri::HTML5.fragment(page(result, "/").content)
    assert_equal ["First", "Second"], document.css("li").map { |item| item.text.strip }
    assert_equal "first", document.css("li").first["id"]
  end

  def test_list_paragraph_is_scanned_but_list_indented_code_remains_literal
    result = compile(
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Home
        - item

            ![[media/public.png]] #visible-list

              ![[media/private.png]] #hidden-list-code
      MARKDOWN
      attachment("media/public.png", "PUBLIC", media_type: "image/png"),
      attachment("media/private.png", "PRIVATE", media_type: "image/png"),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal ["/assets/vault/media/public.png"], result.copied_assets.map(&:route)
    tags = generated_json(result, "/assets/website/catalog.v1.json").fetch("notes").first.fetch("tags")
    assert_includes tags, "visible-list"
    refute_includes tags, "hidden-list-code"
    assert_includes page(result, "/").content, "![[media/private.png]] #hidden-list-code"
  end

  def test_container_fences_do_not_publish_their_tokens
    result = compile(
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Home
        > ~~~md
        > ![[media/private.png]] #hidden-fence
        > ~~~

        ![[media/public.png]] #visible-outside
      MARKDOWN
      attachment("media/public.png", "PUBLIC", media_type: "image/png"),
      attachment("media/private.png", "PRIVATE", media_type: "image/png"),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal ["/assets/vault/media/public.png"], result.copied_assets.map(&:route)
    tags = generated_json(result, "/assets/website/catalog.v1.json").fetch("notes").first.fetch("tags")
    assert_includes tags, "visible-outside"
    refute_includes tags, "hidden-fence"
  end
end
