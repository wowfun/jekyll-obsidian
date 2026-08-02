# frozen_string_literal: true

require "test_helper"

class OfmScannerTest < Minitest::Test
  def test_comments_can_span_lines_without_hiding_tokens_after_the_closer
    result = JekyllObsidian::OfmScanner.prepare(<<~MARKDOWN)
      before %% hidden ![[no-comment]] #no-comment
      still hidden %% ![[yes-comment]] #yes-comment
      before <!-- hidden ![[no-html-comment]] #no-html-comment
      still hidden --> ![[yes-html-comment]] #yes-html-comment
    MARKDOWN

    assert_equal ["yes-comment", "yes-html-comment"], result.embeds.map(&:target)
    assert_equal ["yes-comment", "yes-html-comment"], result.tags
    refute_includes result.markdown, "hidden"
    assert_equal 4, result.markdown.lines.length
  end

  def test_fence_closer_may_be_longer_but_not_shorter_than_its_opener
    result = JekyllObsidian::OfmScanner.prepare(<<~MARKDOWN)
      ````md
      ![[inside-one]] #inside-one
      ```
      ![[inside-two]] #inside-two
      `````
      ![[outside]] #outside
    MARKDOWN

    assert_equal ["outside"], result.embeds.map(&:target)
    assert_equal ["outside"], result.tags
  end

  def test_raw_html_is_isolated_without_hiding_markdown_on_the_same_line
    result = JekyllObsidian::OfmScanner.prepare(<<~MARKDOWN)
      ![[before]] #before <span data-label=">">![[inside-inline]] #inside-inline</span> ![[after]] #after
      <section>
      ![[inside-block]] #inside-block
      <span>![[inside-nested]] #inside-nested</span>
      </section> ![[after-block]] #after-block
    MARKDOWN

    assert_equal %w[before after after-block], result.embeds.map(&:target)
    assert_equal %w[before after after-block], result.tags
    assert_includes result.markdown, "![[inside-inline]]"
    assert_includes result.markdown, "![[inside-block]]"
  end

  def test_inline_code_delimiters_can_span_lines
    result = JekyllObsidian::OfmScanner.prepare(<<~MARKDOWN)
      `code ![[inside]] #inside
      still code` ![[outside]] #outside
    MARKDOWN

    assert_equal ["outside"], result.embeds.map(&:target)
    assert_equal ["outside"], result.tags
  end

  def test_multiline_html_opening_tags_keep_their_contents_isolated
    result = JekyllObsidian::OfmScanner.prepare(<<~MARKDOWN)
      <span
        data-label="example">
      ![[inside]] #inside
      </span> ![[outside]] #outside
    MARKDOWN

    assert_equal ["outside"], result.embeds.map(&:target)
    assert_equal ["outside"], result.tags
  end

  def test_block_id_replacement_preserves_the_line_ending
    result = JekyllObsidian::OfmScanner.prepare("- First ^first\n- Second\n")

    assert_equal "- First <span data-obsidian-block-id=\"first\"></span>\n- Second\n", result.markdown
    assert_equal 2, result.markdown.lines.length
  end

  def test_list_container_indentation_distinguishes_paragraphs_from_code
    result = JekyllObsidian::OfmScanner.prepare(<<~MARKDOWN)
      - item

          ![[visible.png]] #visible

            ![[hidden.png]] #hidden
    MARKDOWN

    assert_equal ["visible.png"], result.embeds.map(&:target)
    assert_equal ["visible"], result.tags
    assert_equal 5, result.embeds.first.source_span.start_column
  end

  def test_blockquote_and_list_fences_isolate_tokens_with_their_container_prefix
    result = JekyllObsidian::OfmScanner.prepare(<<~MARKDOWN)
      > ````md
      > ![[quote-hidden-one]] #quote-hidden-one
      > ```
      > ![[quote-hidden-two]] #quote-hidden-two
      > `````
      ![[quote-visible]] #quote-visible

      - ~~~md
        ![[list-hidden]] #list-hidden
        ~~~
      ![[list-visible]] #list-visible

      > - ~~~md
      >   ![[nested-hidden]] #nested-hidden
      >   ~~~
      ![[nested-visible]] #nested-visible
    MARKDOWN

    assert_equal %w[quote-visible list-visible nested-visible], result.embeds.map(&:target)
    assert_equal %w[quote-visible list-visible nested-visible], result.tags
  end
end
