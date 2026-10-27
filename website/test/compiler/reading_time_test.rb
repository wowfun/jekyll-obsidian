# frozen_string_literal: true

require "test_helper"

class ReadingTimeTest < Minitest::Test
  def test_empty_content_and_integer_minute_boundaries
    { "" => 0, " \n!? 😀" => 0, "中" => 1, "word" => 1,
      "中" * 800 => 2, "中" * 801 => 3,
      "word " * 400 => 2, "word " * 401 => 3,
      "中" * 400 + "word " * 200 => 2,
      "中" * 401 + "word " * 200 => 3,
      "中" * 400 + "word " * 201 => 3,
      "中" * 40 + "word " * 380 => 2 }.each do |text, expected|
      assert_equal expected, minutes("<p>#{text}</p>"), "length=#{text.length}"
    end
  end

  def test_reference_article_length_uses_our_reading_rate
    # Measured on 2026-10-24 from the body of:
    # https://claude.com/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop
    # Synthetic text preserves the measured counts without copying the article
    # or making the suite depend on a network request or future editorial changes.
    assert_equal 15, minutes("<p>#{'word ' * 2895}</p>")
    assert_equal 15, minutes("<h1>#{'word ' * 11}</h1><p>#{'word ' * 2895}</p>")
  end

  def test_unicode_scripts_and_adjacent_words
    %w[中 あ ア 한 𠀀].each { |character| assert_equal 3, minutes(character * 801) }
    %W[café cafe\u0301 привет مرحبا １２３].each { |word| assert_equal 3, minutes("#{word} " * 401) }
    assert_equal 3, minutes("中文Ruby" * 201)
    assert_equal 0, minutes("\u0301" * 401), "standalone combining marks are not words"
  end

  def test_blocks_cells_and_line_breaks_separate_words_but_inline_markup_does_not
    %w[p li div h2 blockquote].each do |tag|
      assert_equal 3, minutes("<#{tag}>word</#{tag}>" * 401), tag
    end
    assert_equal 3, minutes("<table><tr>#{'<td>word</td>' * 401}</tr></table>")
    assert_equal 3, minutes("word<br>" * 401)
    assert_equal 2, minutes("<strong>wo</strong><em>rd</em> " * 400)
    assert_equal 2, minutes("<pre><code>#{'<span>wo</span><span>rd</span> ' * 400}</code></pre>")
    assert_equal 3, minutes("<pre><code>#{'word ' * 401}</code></pre>")
    assert_equal 3, minutes("<code>word</code> " * 401)
  end

  def test_hidden_generated_and_non_text_content_is_excluded_without_changing_the_dom
    ignored = "word " * 401
    wrappers = [
      "<script>#{ignored}</script>", "<style>#{ignored}</style>", "<template>#{ignored}</template>",
      "<div hidden>#{ignored}</div>", "<span aria-hidden='true'>#{ignored}</span>",
      "<span class='visually-hidden'>#{ignored}</span>", "<!-- #{ignored} -->",
      "<img alt='#{ignored}' src='https://example.test/image.png'>",
      "<svg><text>#{ignored}</text></svg>", "<canvas>#{ignored}</canvas>",
      "<audio>#{ignored}</audio>", "<video>#{ignored}</video>",
      "<iframe>#{ignored}</iframe>", "<object>#{ignored}</object>",
      "<span data-math-style='inline'>#{ignored}</span>", "<span class='math'>#{ignored}</span>",
      "<math><mtext>#{ignored}</mtext></math>",
      "<pre data-website-mermaid='true'><code>#{ignored}</code></pre>",
      "<figure class='website-external-pdf'>#{ignored}</figure>",
      "<figure class='website-external-frame'>#{ignored}</figure>",
      "<figure class='website-tweet'>#{ignored}</figure>",
      "<a class='website-download-card'>#{ignored}</a>",
      "<a class='website-transclusion__source'>#{ignored}</a>",
      "<a class='anchor'>#{ignored}</a>", "<button>#{ignored}</button>"
    ]
    wrappers.each do |html|
      fragment = Nokogiri::HTML5.fragment("<p>Visible</p>#{html}")
      before = fragment.to_html
      assert_equal 1, JekyllObsidian::ReadingTime.minutes(fragment), html[0, 65]
      assert_equal before, fragment.to_html
    end
    assert_equal 3, minutes("<figure><img src='image.png'><figcaption>#{ignored}</figcaption></figure>")
    assert_equal 1, minutes("<a href='https://example.test/#{ignored.tr(' ', '/')}'>Label</a>")
  end

  def test_compiler_counts_expanded_body_and_code_but_not_frontmatter_or_generated_source
    result = compile(
      note("index.md", "---\npublish: true\n---\nHome"),
      note("host.md", "---\npublish: true\ndescription: #{'metadata ' * 401}\n---\n![[target]]\n\n```ruby\nword\n```"),
      note("target.md", "---\npublish: true\n---\n#{'word ' * 400}")
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal 2, page(result, "/target/").data.dig("website", "reading_time_minutes")
    assert_equal 3, page(result, "/host/").data.dig("website", "reading_time_minutes")
    assert_equal 1, page(result, "/").data.dig("website", "reading_time_minutes")
    search = generated_json(result, "/assets/website/search.v1.json")
    refute_includes JSON.generate(search), '"reading_time_minutes"'
  end

  def test_disabling_the_hint_keeps_the_estimate_available_to_custom_templates
    result = compile(note("long.md", "---\npublish: true\n---\n#{'word ' * 401}"), features: { "reading_time" => false })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal false, result.features.fetch("reading_time")
    assert_equal 3, page(result, "/long/").data.dig("website", "reading_time_minutes")
  end

  def test_compiler_excludes_rendered_math_mermaid_and_media
    text = "word " * 401
    result = compile(note("note.md", <<~MARKDOWN))
      ---
      publish: true
      ---
      Visible

      $#{text.strip}$

      ```mermaid
      #{text}
      ```

      ![#{text}](https://example.test/image.png)

      ![#{text}](https://example.test/paper.pdf)
    MARKDOWN
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal 1, page(result, "/note/").data.dig("website", "reading_time_minutes")
  end

  def test_each_translation_uses_its_rendered_body_and_fallback_uses_default_body
    result = compile(
      note("index.md", "---\npublish: true\n---\nHome"),
      note("long.md", "---\npublish: true\n---\n#{'word ' * 401}"),
      note("fallback.md", "---\npublish: true\n---\n#{'word ' * 401}"),
      note("_translations/zh-CN/long.md", "---\npublish: true\n---\n#{'中' * 800}"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\nmessages:\n  reading_time: '约 {minutes} 分钟阅读'\n"),
      i18n: { "enabled" => true, "locales" => %w[en zh-CN] }
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal 3, page(result, "/long/").data.dig("website", "reading_time_minutes")
    assert_equal 2, page(result, "/zh-CN/long/").data.dig("website", "reading_time_minutes")
    fallback = page(result, "/zh-CN/fallback/").data.fetch("website")
    assert_equal 3, fallback.fetch("reading_time_minutes")
    assert_equal true, fallback.dig("i18n", "fallback")
    assert_equal "约 {minutes} 分钟阅读", fallback.dig("i18n", "messages", "reading_time")
  end

  def test_reading_time_message_requires_one_minutes_placeholder
    ["", "  ", "About {minute} min", "About 3 min", "{minutes} {unknown}", "{{minutes}}", "{minutes} {minutes}"].each do |message|
      result = compile(note("long.md", "---\npublish: true\n---\n#{'word ' * 401}"),
        locale_manifest("_locale.yml", "name: English\nmessages:\n  reading_time: #{message.to_json}\n"),
        i18n: { "enabled" => true, "locales" => %w[en] })
      refute result.success?, message.inspect
      assert result.diagnostics.any? { |item| item.code == "invalid_locale_message" && item.message.include?("reading_time") }
    end
  end

  def test_one_locale_can_customize_reading_time_without_translation_copies
    result = compile(note("long.md", "---\npublish: true\n---\n#{'word ' * 401}"),
      locale_manifest("_locale.yml", "name: العربية\ndir: rtl\nmessages:\n  reading_time: 'قراءة {minutes} دقائق'\n"),
      lang: "ar", i18n: { "enabled" => true, "locales" => ["ar"] })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    data = page(result, "/long/").data.fetch("website")
    assert_equal "قراءة {minutes} دقائق", data.dig("i18n", "messages", "reading_time")
    assert_equal({ "lang" => "ar", "dir" => "rtl" }, data.dig("i18n", "reading_time_language"))
    assert_equal 3, data.fetch("reading_time_minutes")
    refute result.pages.any? { |output| output.route.start_with?("/ar/") }
  end

  def test_duplicate_reading_time_placeholder_explains_the_error
    result = compile(note("note.md", "---\npublish: true\n---\nText"),
      locale_manifest("_locale.yml", "name: English\nmessages:\n  reading_time: '{minutes} {minutes}'\n"),
      i18n: { "enabled" => true, "locales" => %w[en] })
    diagnostic = result.diagnostics.find { |item| item.code == "invalid_locale_message" }
    refute_nil diagnostic
    assert_includes diagnostic.message, "duplicate placeholders: minutes"
  end

  private

  def minutes(html)
    JekyllObsidian::ReadingTime.minutes(Nokogiri::HTML5.fragment(html))
  end
end
