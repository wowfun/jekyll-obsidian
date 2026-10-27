# frozen_string_literal: true

require "test_helper"

class SharedContentTest < Minitest::Test
  I18N = { "enabled" => true, "locales" => %w[en zh-CN], "shared_directories" => ["clippings"] }.freeze

  def manifests
    [locale_manifest("_locale.yml", "name: English\n"),
     locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\ndir: ltr\n")]
  end

  def clipping(path = "clippings/item.md", language: "zh-CN")
    note(path, "---\npublish: true\ncontent_type: post\ntitle: Shared article\ndate: 2026-10-24\ntags: [source/clippings]\n#{language.nil? ? '' : "lang: #{language}\n"}---\n正文 [[clippings/other]]")
  end

  def test_shared_pages_keep_localized_resources_but_one_authored_identity
    %w[minimal docs].each do |theme|
      result = compile(*manifests, clipping, clipping("clippings/other.md"),
        clipping("clippings-extra/item.md"), i18n: I18N, theme: theme, baseurl: "/garden")
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      %w[en zh-CN].each do |locale|
        prefix = locale == "en" ? "" : "/zh-CN"
        output = page(result, "#{prefix}/clippings/item/")
        website = output.data.fetch("website")
        assert_equal locale, website.dig("i18n", "locale")
        assert_equal "zh-CN", website.dig("i18n", "content_lang")
        assert_equal "ltr", website.dig("i18n", "content_dir")
        assert_equal true, website.dig("i18n", "shared")
        assert_equal false, website.dig("i18n", "fallback")
        refute website.dig("i18n", "localizations").any? { |item| item.fetch("fallback") }
        assert_equal "https://example.test/garden/clippings/item/", website.fetch("canonical_url")
        assert_empty website.fetch("alternates")
        assert_includes website.dig("source_links", "source"), "/vault/clippings/item.md"
        refute_includes website.dig("source_links", "source"), "_translations"
        assert_includes output.content, "/garden#{prefix}/clippings/other/"
        assert_equal "Shared article", output.data.fetch("title")
      end
      assert_equal "noindex", page(result, "/zh-CN/clippings/item/").data.dig("website", "robots")
      assert_equal true, page(result, "/zh-CN/clippings-extra/item/").data.dig("website", "i18n", "fallback")
      sitemap = result.generated_files.find { |file| file.route == "/sitemap.xml" }.content
      assert_includes sitemap, "https://example.test/garden/clippings/item/"
      refute_includes sitemap, "/zh-CN/clippings/"
      search = generated_json(result, "/assets/website/i18n/zh-CN/search.v1.json")
      assert_includes JSON.generate(search), "/garden/zh-CN/clippings/item/"
    end
  end

  def test_shared_folder_tab_and_home_both_include_posts_without_source_exclusion
    root = note("clippings/index.md", "---\npublish: true\ncontent_type: page\ntitle: Clippings\ntab: {id: clippings, order: 8, layout: archive}\n---\n")
    result = compile(*manifests, root, clipping,
      note("index.md", "---\npublish: true\n---\n"), i18n: I18N,
      home: { "layout" => "archive", "hide_tab_sources" => true }, blog: { "page_size" => 1 })
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    ["", "/zh-CN"].each do |prefix|
      home = page(result, "#{prefix}/").data.fetch("website")
      tab = page(result, "#{prefix}/clippings/").data.fetch("website")
      assert_equal 1, home.dig("theme_data", "archive", "total")
      assert_empty home.dig("theme_data", "archive", "tab_sources")
      assert_equal 1, tab.dig("theme_data", "archive", "total")
      assert_equal false, tab.dig("i18n", "fallback")
      assert_equal "#{prefix}/clippings/", home.fetch("navigation").find { |item| item["id"] == "clippings" }.fetch("url")
    end
  end

  def test_shared_languages_have_independent_direction_and_unknown_defaults
    { nil => ["und", "auto"], "ar" => ["ar", "rtl"], "ar-Latn" => ["ar-Latn", "ltr"],
      "en" => ["en", "ltr"], "de-1901" => ["de-1901", "ltr"], "de-1996" => ["de-1996", "ltr"],
      "en-x-arab" => ["en-x-arab", "ltr"], "ar-u-nu-latn" => ["ar-u-nu-latn", "rtl"],
      "zz" => ["zz", "auto"] }.each do |language, expected|
      result = compile(*manifests, clipping(language: language), i18n: I18N)
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      localized = page(result, "/zh-CN/clippings/item/").data.dig("website", "i18n")
      assert_equal expected, localized.values_at("content_lang", "content_dir")
      assert_equal "ltr", localized.fetch("dir")
    end
  end

  def test_shared_directory_validation_runs_even_when_localization_is_disabled
    [nil, "clippings", [""], ["."], ["../clippings"], ["/clippings"], ["C:/clippings"],
      ["clippings/"], ["clippings//nested"], ["clippings\\nested"], ["_translations"], [12]].each do |value|
      [true, false].each do |enabled|
        result = compile(*manifests, clipping, i18n: I18N.merge("enabled" => enabled, "shared_directories" => value))
        refute result.success?, "accepted #{value.inspect}"
        assert result.diagnostics.any? { |item| item.code == "invalid_shared_directories" }
      end
    end
    result = compile(*manifests, clipping("nested/clippings/item.md"),
      i18n: I18N.merge("shared_directories" => ["nested/clippings"]))
    assert result.success?
    assert_equal true, page(result, "/zh-CN/nested/clippings/item/").data.dig("website", "i18n", "shared")
  end

  def test_shared_translation_copies_are_errors_even_when_unpublished
    [true, false].each do |publish|
      result = compile(*manifests, clipping,
        note("_translations/zh-CN/clippings/item.md", "---\npublish: #{publish}\n---\nCopy"), i18n: I18N)
      refute result.success?
      diagnostic = result.diagnostics.find { |item| item.code == "shared_translation_conflict" }
      assert_equal "_translations/zh-CN/clippings/item.md", diagnostic.path
    end
  end

  def test_shared_directories_match_exact_snapshot_case_and_keep_fallbacks_noindex
    { "clippings" => false, "Clippings" => true }.each do |directory, shared|
      result = compile(*manifests, note("Clippings/item.md", "---\npublish: true\n---\nBody"),
        i18n: I18N.merge("shared_directories" => [directory]))
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      data = page(result, "/zh-CN/Clippings/item/").data.fetch("website")
      assert_equal shared, data.dig("i18n", "shared")
      assert_equal !shared, data.dig("i18n", "fallback")
      assert_equal "noindex", data.fetch("robots")
      assert_equal "https://example.test/Clippings/item/", data.fetch("canonical_url")
      sitemap = result.generated_files.find { |file| file.route == "/sitemap.xml" }.content
      refute_includes sitemap, "/zh-CN/Clippings/"
    end
  end

  def test_invalid_original_language_is_rejected
    ["null", "[]", "true", "'zh CN'", "'en<script>'"].each do |value|
      result = compile(*manifests, clipping(language: value), i18n: I18N)
      refute result.success?
      assert result.diagnostics.any? { |item| item.code == "invalid_property" && item.message.include?("lang") }
    end
  end
end
