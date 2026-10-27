# frozen_string_literal: true

require "test_helper"

class FooterConfigurationTest < Minitest::Test
  def entries
    [
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("blog/post.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-20\n---\n# Post"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\nmessages:\n  footer_sites: 站点\n"),
      locale_manifest("_translations/fr/_locale.yml", "name: Français\n")
    ]
  end

  def test_empty_footer_and_contacts_are_empty_on_every_page
    [nil, {}, { "links" => [] }].each do |footer|
      %w[minimal docs].each do |theme|
        result = compile(*entries, theme: theme, footer: footer)
        assert result.success?, result.diagnostics.map(&:message).join("\n")
        result.pages.each { |output| assert_equal({ "contacts" => [], "links" => [] }, output.data.dig("website", "footer")) }
      end
    end
  end

  def test_footer_is_resolved_once_per_build_and_invalid_localized_config_is_a_diagnostic
    [nil, { "enabled" => false }, { "enabled" => true, "locales" => %w[en zh-CN fr] }].each do |i18n|
      [{ "links" => [{ "label" => "Docs", "url" => "https://example.test/docs/" }] }, { "links" => false }].each do |footer|
        calls = 0
        trace = TracePoint.new(:call) { |event| calls += 1 if event.self.equal?(JekyllObsidian::FooterLinks) && event.method_id == :resolve }
        result = nil
        trace.enable { result = compile(*entries, i18n: i18n, footer: footer) }
        assert_equal 1, calls, "i18n=#{i18n.inspect}, footer=#{footer.inspect}"
        if footer["links"] == false
          refute result.success?
          assert_equal ["invalid_footer"], result.diagnostics.select { |item| item.severity == :error }.map(&:code)
        else
          assert result.success?, result.diagnostics.map(&:message).join("\n")
        end
      end
    end
  end

  def test_localized_footer_is_shared_by_all_pages_and_preserves_explicit_sibling_urls
    links = [
      { "label" => "Sibling", "url" => "https://example.test/feedgarden/", "locale_urls" => { "zh-CN" => "https://example.test/feedgarden/zh-CN/" } },
      { "label" => "Root", "url" => "https://example.test/" }
    ]
    %w[minimal docs].each do |theme|
      ["", "/feedgarden"].each do |baseurl|
        result = compile(*entries, theme: theme, baseurl: baseurl, footer: { "links" => links },
          contacts: [{ "label" => "Website", "url" => "https://example.test/" }],
          i18n: { "enabled" => true, "locales" => %w[en zh-CN fr] })
        assert result.success?, result.diagnostics.map(&:message).join("\n")
        result.pages.each do |output|
          footer = output.data.dig("website", "footer")
          chinese = output.route.start_with?("/zh-CN/")
          assert_equal "https://example.test/feedgarden/#{chinese ? 'zh-CN/' : ''}", footer.fetch("links")[0].fetch("url"), output.route
          assert_equal "https://example.test/", footer.fetch("links")[1].fetch("url")
          assert_equal "https://example.test/", footer.fetch("contacts")[0].fetch("url")
          assert_nil output.data.dig("website", "theme_data", "contacts")
          assert_equal chinese ? "站点" : "Sites", output.data.dig("website", "i18n", "messages", "footer_sites")
        end
      end
    end
  end

  def test_default_language_override_works_without_multilingual_output
    result = compile(*entries, theme: "minimal", footer: { "links" => [
      { "label" => "\ufeff Docs \u00a0", "url" => "https://example.test/", "locale_urls" => { "en" => "https://example.test/en/?a=1&b=2#start" } }
    ] })
    assert result.success?
    assert_equal "Docs", page(result, "/").data.dig("website", "footer", "links", 0, "label")
    assert_equal "https://example.test/en/?a=1&b=2#start", page(result, "/").data.dig("website", "footer", "links", 0, "url")
  end

  def test_locale_overrides_are_case_insensitive_and_reject_ambiguous_keys
    link = { "label" => "Docs", "url" => "https://example.test/", "locale_urls" => {
      "zh-cn" => "https://example.test/chinese/", "de" => "https://example.test/german/"
    } }
    result = compile(*entries, footer: { "links" => [link] }, i18n: { "enabled" => true, "locales" => %w[en zh-CN fr] })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal "https://example.test/chinese/", page(result, "/zh-CN/").data.dig("website", "footer", "links", 0, "url")
    assert_equal "https://example.test/", page(result, "/").data.dig("website", "footer", "links", 0, "url")
    link = link.merge("locale_urls" => link["locale_urls"].merge("ZH-CN" => "https://example.test/conflict/"))
    result = compile(*entries, footer: { "links" => [link] })
    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "invalid_footer" && item.message.include?("case") }
  end

  def test_footer_presentation_runs_once_per_locale_and_reuses_immutable_page_data
    [nil, { "enabled" => true, "locales" => %w[en zh-CN fr] }].each do |i18n|
      calls = 0
      trace = TracePoint.new(:call) { |event| calls += 1 if event.self.equal?(JekyllObsidian::FooterLinks) && event.method_id == :present }
      result = nil
      trace.enable { result = compile(*entries, i18n: i18n, footer: { "links" => [{ "label" => "Docs", "url" => "https://example.test/" }] }) }
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      assert_equal i18n ? 3 : 1, calls
      result.pages.group_by { |output| output.data.dig("website", "i18n", "locale") }.each_value do |pages|
        footers = pages.map { |output| output.data.dig("website", "footer") }
        assert footers.all?(&:frozen?)
        assert_equal 1, footers.map(&:object_id).uniq.length
      end
    end
  end

  def test_footer_limits_and_single_line_labels
    valid = { "label" => "x" * 64, "url" => "https://example.test/".ljust(2048, "x") }
    result = compile(*entries, footer: { "links" => [valid] * 12 })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    invalid = [[valid] * 13, [valid.merge("label" => "x" * 65)], [valid.merge("url" => valid["url"] + "x")],
      [valid.merge("locale_urls" => { "en" => valid["url"] + "x" })]]
    ["\n", "\r", "\t", "\u2028", "\u2029"].each { |space| invalid << [valid.merge("label" => "Docs#{space}Archive")] }
    invalid.each do |links|
      result = compile(*entries, footer: { "links" => links })
      refute result.success?
      assert result.diagnostics.any? { |item| item.code == "invalid_footer" }
    end
  end

  def test_invalid_shapes_labels_and_urls_produce_actionable_diagnostics
    valid = { "label" => "Docs", "url" => "https://example.test/" }
    invalid = [[], "footer", { "unknown" => [] }, { "links" => nil }, { "links" => {} }, { "links" => [nil] }]
    [nil, "", "  ", "\u00a0", "\ufeff", " \ufeff\u00a0 ", 12, "bad\u0000label"].each { |label| invalid << { "links" => [valid.merge("label" => label)] } }
    [nil, "", "/docs/", "//example.test/", "http://example.test/", "javascript:alert(1)", "https:///docs", "https://user:secret@example.test/"].each do |url|
      invalid << { "links" => [valid.merge("url" => url)] }
    end
    [nil, [], { "bad locale" => "https://example.test/" }, { "zh-CN" => "http://example.test/" }].each do |overrides|
      invalid << { "links" => [valid.merge("locale_urls" => overrides)] }
    end
    invalid << { "links" => [valid.merge("target" => "_blank")] }
    invalid.each do |footer|
      result = compile(*entries, footer: footer)
      refute result.success?, footer.inspect
      diagnostic = result.diagnostics.find { |item| item.code == "invalid_footer" }
      refute_nil diagnostic, footer.inspect
      assert_includes diagnostic.message, "website.footer"
    end
  end
end
