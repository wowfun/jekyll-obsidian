# frozen_string_literal: true

require "test_helper"

class NotePropertiesTest < Minitest::Test
  def test_scalar_projection_rejects_unsupported_types_explicitly
    [:symbol, {}, [], Object.new].each do |value|
      error = assert_raises(ArgumentError) { JekyllObsidian::NoteProperties.scalar(value) }
      assert_match(/Unsupported property scalar type/, error.message)
    end
  end

  def test_custom_values_are_typed_without_becoming_page_control_fields
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      title: Properties
      layout: attacker
      render_with_liquid: true
      zero: 0
      enabled: false
      absent: null
      empty: ""
      values: [0, false, null, "", "2026-10-10", 2026-10-10]
      day: 2026-10-10
      instant: 2026-10-10T13:45:00+08:00
      quoted_day: "2026-10-10"
      repo_url: https://github.com/example/project
      unsafe: javascript:alert(1)
      literal: "<script>{{ site.secret }}</script>"
      nothing: []
      ---
      # Properties
    MARKDOWN
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    output = page(result, "/")
    fields = output.data.dig("website", "display_properties")
    refute output.data.fetch("website").key?("properties"), "page display data must not reuse the site configuration key"
    refute_nil fields
    assert_equal %w[zero enabled absent empty values day instant quoted_day repo_url unsafe literal nothing], fields.map { |field| field.fetch("name") }
    assert_equal %w[number boolean null empty_string text date], fields[4].fetch("values").map { |value| value.fetch("kind") }
    assert_equal "0", fields[0].fetch("values")[0].fetch("text")
    assert_equal "false", fields[1].fetch("values")[0].fetch("text")
    assert_equal "date", fields[5].fetch("values")[0].fetch("kind")
    assert_equal "2026-10-10", fields[5].fetch("values")[0].fetch("datetime")
    assert_equal "datetime", fields[6].fetch("values")[0].fetch("kind")
    assert_equal "text", fields[7].fetch("values")[0].fetch("kind")
    assert_equal "https://github.com/example/project", fields[8].fetch("values")[0].fetch("external_url")
    assert_equal "text", fields[9].fetch("values")[0].fetch("kind")
    assert_equal "<script>{{ site.secret }}</script>", fields[10].fetch("values")[0].fetch("text")
    assert_raises(FrozenError) { fields[10].fetch("values")[0].fetch("text") << "mutation" }
    assert_raises(FrozenError) { result.notes.first.properties.fetch("literal") << "mutation" }
    assert_empty fields[11].fetch("values")
    refute output.data.key?("repo_url")
    assert_equal "website-minimal", output.data.fetch("layout")
  end

  def test_hidden_fields_are_filtered_before_public_projection_in_both_themes
    %w[minimal docs].each do |theme|
      result = compile(note("index.md", "---\npublish: true\nsecret: hidden-marker\nvisible: value\nsource_url: https://example.test/source\n---\n# Home"), theme: theme, properties: { "hidden" => ["secret"] })
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      output = page(result, "/")
      assert_equal ["visible"], output.data.dig("website", "display_properties").map { |field| field.fetch("name") }
      refute_includes JSON.generate(output.data), "hidden-marker"
      assert_equal "https://example.test/source", output.data.dig("website", "source_url")
      assert_equal "hidden-marker", result.notes.first.properties["secret"]
    end
  end

  def test_invalid_hidden_configuration_fails_with_a_clear_diagnostic
    [[], { "unknown" => [] }, { "hidden" => "secret" }, { "hidden" => [false] }, { "hidden" => [" key"] }, { "hidden" => ["key", "key"] }].each do |properties|
      result = compile(note("index.md", "---\npublish: true\n---\n# Home"), properties: properties)
      refute result.success?, properties.inspect
      assert result.diagnostics.any? { |item| item.code == "invalid_properties_config" }
    end
  end

  def test_wiki_values_keep_aliases_fragments_duplicates_and_author_order_without_relation_rail
    result = compile(
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        references:
          - "[[target#Heading|First label]]"
          - ordinary
          - "[[target#Heading|Second label]]"
          - "[[private|Authored private label]]"
        ---
        # Home
      MARKDOWN
      note("target.md", "---\npublish: true\ntitle: Target title\n---\n# Target\n\n## Heading"),
      note("private.md", "---\ntitle: Private title marker\n---\nPrivate body marker"),
      baseurl: "/garden", features: { "relations" => false }
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    values = page(result, "/").data.dig("website", "display_properties")[0].fetch("values")
    assert_equal ["First label", "ordinary", "Second label", "Authored private label"], values.map { |value| value.fetch("text") }
    assert_equal ["/garden/target/#heading", nil, "/garden/target/#heading", nil], values.map { |value| value["url"] }
    assert_empty page(result, "/").data.dig("website", "links")
    refute_includes JSON.generate(page(result, "/").data), "Private title marker"
    assert result.diagnostics.any? { |item| item.code == "unresolved_property_link" }
  end

  def test_locale_overlay_preserves_yaml_dates_and_only_localizes_wiki_routes
    result = compile(
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      note("index.md", "---\npublish: true\nday: 2026-10-10\nquoted: \"2026-10-10\"\ninstant: 2026-10-10T13:45:00+08:00\nproject: \"[[target]]\"\nurl: https://example.test/garden/target/\nsecret: hidden-marker\n---\n# Home"),
      note("target.md", "---\npublish: true\n---\n# Target"),
      note("_translations/zh-CN/index.md", "---\nextra: 0\n---\n# 首页"),
      note("_translations/zh-CN/target.md", "# 目标"),
      baseurl: "/garden", i18n: { "enabled" => true, "locales" => %w[en zh-CN] }, properties: { "hidden" => ["secret"] }
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    fields = page(result, "/zh-CN/").data.dig("website", "display_properties")
    assert_equal %w[day quoted instant project url extra], fields.map { |field| field.fetch("name") }
    assert_equal %w[date text datetime wiki_link url number], fields.map { |field| field.fetch("values")[0].fetch("kind") }
    assert_equal "/garden/zh-CN/target/", fields[3].fetch("values")[0].fetch("url")
    assert_equal "目标", fields[3].fetch("values")[0].fetch("text")
    assert_equal "https://example.test/garden/target/", fields[4].fetch("values")[0].fetch("external_url")
    refute_includes JSON.generate(page(result, "/zh-CN/").data), "hidden-marker"
  end

  def test_non_http_urls_credentials_and_embedded_link_syntax_remain_text
    values = ["javascript:alert(1)", "data:text/html,test", "https://user:pass@example.test/", "prefix https://example.test/", "prefix [[target]]", "https://example.test/a b"]
    values.each do |value|
      result = compile(note("index.md", "---\npublish: true\nvalue: #{JSON.generate(value)}\n---\n# Home"))
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      projected = page(result, "/").data.dig("website", "display_properties")[0].fetch("values")[0]
      assert_equal({ "kind" => "text", "text" => value }, projected)
    end
  end

  def test_source_and_custom_urls_agree_on_clickable_http_values
    valid = ["http://example.test/", "https://example.test/a%20b?q=1#fragment", "HTTPS://example.test/", "https://[::1]:8443/path"]
    invalid = ["ordinary", "prefix https://example.test/", "https://user:pass@example.test/", "https://example.test/a b", "https://", "https:///missing-host", "javascript:alert(1)", "//example.test/", "https://example.test/\n"]
    { true => valid, false => invalid }.each do |accepted, values|
      values.each do |value|
        parsed = JekyllObsidian::FrontMatter.parse("index.md", "---\nsource_url: #{JSON.generate(value)}\n---\n# Home")
        assert_equal accepted, parsed.diagnostics.empty?, value.inspect
        display = JekyllObsidian::NoteProperties.scalar(value)
        assert_equal accepted ? "url" : "text", display.fetch("kind"), value.inspect
        assert_equal value, display.fetch("text")
      end
    end
  end

  def test_objects_nested_lists_and_nonfinite_numbers_remain_invalid
    ["{key: value}", "[1, [2]]", ".inf", ".nan"].each do |value|
      result = compile(note("index.md", "---\npublish: true\nvalue: #{value}\n---\n# Home"))
      refute result.success?
      assert result.diagnostics.any? { |item| item.code == "invalid_property" }
    end
  end

  def test_no_custom_fields_produce_no_property_rows
    result = compile(note("index.md", "---\npublish: true\ntitle: Home\nupdated: 2026-10-10\n---\n# Home"))
    assert result.success?
    assert_empty page(result, "/").data.dig("website", "display_properties")
  end

  def test_hidden_wiki_properties_keep_their_public_relations
    result = compile(
      note("index.md", "---\npublish: true\nproject: \"[[target]]\"\n---\n# Home"),
      note("target.md", "---\npublish: true\n---\n# Target"),
      properties: { "hidden" => ["project"] }
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_empty page(result, "/").data.dig("website", "display_properties")
    assert_equal ["target.md"], page(result, "/").data.dig("website", "links").map { |link| link.fetch("id") }
    assert_equal ["index.md"], page(result, "/target/").data.dig("website", "backlinks").map { |link| link.fetch("id") }
  end

  def test_body_properties_related_and_authors_share_encoded_resolved_fragments
    %w[minimal docs].each do |theme|
      result = compile(
        note("index.md", "---\npublish: true\n---\n# Home"),
        note("story.md", <<~MARKDOWN),
          ---
          publish: true
          content_type: post
          date: 2026-10-10
          author: ["[[target#你好 世界|Author heading]]", "[[target#^UPPER_block|Author block]]"]
          categories: ["[[target#^UPPER_block|Category block]]"]
          references: ["[[target#你好 世界|Property heading]]", "[[target#^UPPER_block|Property block]]"]
          related: ["[[target#你好 世界|Related heading]]"]
          ---
          [[target#你好 世界|Body heading]] and [[target#^UPPER_block|Body block]].
        MARKDOWN
        note("target.md", "---\npublish: true\n---\n# Target\n\n## 你好 世界\n\nBlock paragraph. ^UPPER_block"),
        theme: theme, baseurl: "/garden"
      )
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      output = page(result, "/story/")
      heading = "/garden/target/#%E4%BD%A0%E5%A5%BD-%E4%B8%96%E7%95%8C"
      block = "/garden/target/#UPPER_block"
      assert_equal [heading, block], Nokogiri::HTML5.fragment(output.content).css("a.website-link").map { |node| node["href"] }
      assert_equal [heading, block], output.data.dig("website", "display_properties")[0].fetch("values").map { |value| value.fetch("url") }
      assert_equal heading, output.data.dig("website", "related_articles")[0].fetch("url")
      assert_equal [heading, block], output.data.dig("website", "authors").map { |author| author.fetch("url") }
    end
  end
end
