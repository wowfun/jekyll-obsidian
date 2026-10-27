# frozen_string_literal: true

require "test_helper"

class PublicationPolicyTest < Minitest::Test
  def test_favorites_are_excluded_from_single_and_multilingual_sitemaps
    [nil, { "enabled" => true, "locales" => %w[en zh-CN] }].each do |i18n|
      result = compile(note("index.md", "---\npublish: true\n---\nHome"),
        locale_manifest("_locale.yml", "name: English\n"),
        locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
        features: { "favorites" => true }, i18n: i18n)
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      assert_equal "noindex", page(result, "/favorites/").data.dig("website", "robots")
      sitemap = result.generated_files.find { |file| file.route == "/sitemap.xml" }.content
      refute_includes sitemap, "/favorites/"
    end
  end

  def test_both_sitemap_writers_honor_noindex_tokens
    request = JekyllObsidian::BuildRequest.new(snapshot: JekyllObsidian::Snapshot.new(entries: []),
      config: JekyllObsidian::BuildConfig.new(**DEFAULT_CONFIG))
    pages = [nil, "index, follow", "noindex, nofollow", "NOINDEX follow", "notnoindex"].map.with_index do |robots, i|
      JekyllObsidian::PageOutput.new(route: "/page-#{i}/", content: "", data: { "website" => { "kind" => "note", "robots" => robots } })
    end
    [JekyllObsidian::VaultCompiler, JekyllObsidian::LocalizedCompiler].each do |klass|
      sitemap = klass.new(request).prepare.send(:sitemap_xml, pages)
      [0, 1, 4].each { |i| assert_includes sitemap, "/page-#{i}/" }
      [2, 3].each { |i| refute_includes sitemap, "/page-#{i}/" }
    end
  end

end
