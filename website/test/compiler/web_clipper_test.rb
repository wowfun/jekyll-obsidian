# frozen_string_literal: true

require "test_helper"

class WebClipperTest < Minitest::Test
  CLIPPING = <<~MARKDOWN.freeze
    ---
    title: Original clipping
    source: https://example.test/original
    source_title: Original source title
    author:
      - "[[Diane Sarkis]]"
    published: 2026-10-22
    created: 2026-10-24
    description: Clipped summary
    tags: [agents, subagents]
    ---
    One authored body.
  MARKDOWN
  CONTENT = {
    "publish_by_default" => ["clippings"],
    "directories" => { "post" => ["clippings"] },
    "directory_tags" => { "clippings" => ["source/clippings"] }
  }.freeze

  def test_clipper_metadata_publishes_without_rewriting_source_in_both_locales_and_themes
    %w[minimal docs].each do |theme|
      manifest = "tag_aliases: {agents: topics/agents}\n"
      result = compile(
        locale_manifest("_locale.yml", "name: English\n#{manifest}"),
        locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n#{manifest}"),
        note("clippings/article.md", CLIPPING),
        note("clippings/draft.md", CLIPPING.sub("title:", "publish: false\ntitle:")),
        note("clippings-extra/private.md", CLIPPING),
        note("clippings/index.md", "---\ncontent_type: page\ntitle: Clippings\ntab: {id: clippings#{theme == 'minimal' ? ', layout: archive' : ''}}\n---\n"),
        content: CONTENT, theme: theme, home: theme == "minimal" ? { "layout" => "archive", "hide_tab_sources" => true } : {},
        blog: { "page_size" => 50, "facets" => { "source" => "source/", "topic" => "topics/" } },
        i18n: { "enabled" => true, "locales" => %w[en zh-CN], "shared_directories" => ["clippings"] }
      )
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      ["", "/zh-CN"].each do |prefix|
        data = page(result, "#{prefix}/clippings/article/").data.fetch("website")
        assert_equal "https://example.test/original", data.fetch("source_url")
        assert_equal "Original source title", data.fetch("source_title")
        assert_match(/^2026-10-22/, data.fetch("published_at"))
        assert_equal [{ "kind" => "author", "name" => "Diane Sarkis" }], data.fetch("authors")
        assert_equal %w[agents source/clippings subagents], data.fetch("tags")
        assert_equal "und", data.dig("i18n", "content_lang")
        assert_equal "auto", data.dig("i18n", "content_dir")
        assert_equal false, data.dig("i18n", "fallback")
        assert_empty data.fetch("display_properties")
        if theme == "minimal"
          assert_equal %w[clippings agents], data.fetch("archive_facets").map { |facet| facet.fetch("id") }
          assert_equal 1, page(result, "#{prefix}/clippings/").data.dig("website", "theme_data", "archive", "total")
          assert_equal 1, page(result, "#{prefix}/").data.dig("website", "theme_data", "archive", "total")
          archive = page(result, "#{prefix}/clippings/").data.dig("website", "theme_data", "archive")
          cards = generated_json(result, archive.fetch("url").delete_suffix("manifest.json") + archive.fetch("chunks").first).fetch("cards")
          assert_equal "Original source title", cards.first.fetch("source_title")
        end
        refute page(result, "#{prefix}/clippings/draft/")
        refute page(result, "#{prefix}/clippings-extra/private/")
      end
      original = JekyllObsidian::FrontMatter.parse("clippings/article.md", CLIPPING).properties
      assert_equal ["[[Diane Sarkis]]"], original.fetch("author")
      assert_equal %w[agents subagents], original.fetch("tags")
      refute original.key?("publish")
      refute original.key?("date")
    end
  end

  def test_explicit_date_and_source_url_take_precedence_and_source_is_kept
    result = compile(note("clippings/article.md", CLIPPING.sub("title:", "date: 2026-10-20\nsource_url: https://example.test/override\ntitle:")), content: CONTENT)
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    data = page(result, "/clippings/article/").data.fetch("website")
    assert_match(/^2026-10-20/, data.fetch("published_at"))
    assert_equal "https://example.test/override", data.fetch("source_url")
    assert_equal "https://example.test/original", result.notes.first.properties.fetch("source")
  end

  def test_clipper_date_and_source_validation_is_not_bypassed_by_explicit_fields
    ["published: yesterday", "published: true", "source: Original article", "source: javascript:alert(1)", "source: https://user:password@example.test/", "source_title: [invalid]", "source_title: 123"].each do |property|
      result = compile(note("clippings/article.md", "---\n#{property}\ndate: 2026-10-20\nsource_url: https://example.test/valid\n---\nBody"), content: CONTENT)
      refute result.success?, property
      assert result.diagnostics.any? { |item| item.code == "invalid_property" }
      if property.start_with?("source:")
        assert result.diagnostics.any? { |item| item.code == "invalid_property" && item.message == "source must be an absolute HTTP(S) URL without credentials" }, property
      end
    end
  end

  def test_effective_source_url_is_identical_on_pages_archives_and_favorites_without_changing_properties
    sources = [
      {},
      { "source" => "https://example.test/original" },
      { "source_url" => "https://example.test/explicit" },
      { "source" => "https://example.test/original", "source_url" => "https://example.test/explicit" }
    ]
    sources.each do |properties|
      metadata = properties.map { |key, value| "#{key}: #{value}" }.join("\n")
      result = compile(
        note("clippings/article.md", "---\npublish: true\ncontent_type: post\ndate: 2026-10-20\nimage: cover.png\n#{metadata}\n---\nBody"),
        note("clippings/index.md", "---\npublish: true\ncontent_type: page\ntab: {id: clippings, layout: archive}\n---\n"),
        attachment("clippings/cover.png", "PNG", media_type: "image/png"),
        locale_manifest("_locale.yml", "name: English\n"),
        locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
        home: { "layout" => "archive" },
        features: { "favorites" => true }, blog: { "page_size" => 1 },
        i18n: { "enabled" => true, "locales" => %w[en zh-CN], "shared_directories" => ["clippings"] }
      )
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      expected = properties["source_url"] || properties["source"]
      ["", "/zh-CN"].each do |prefix|
        article = page(result, "#{prefix}/clippings/article/")
        data = article.data.fetch("website")
        assert_equal "https://example.test/assets/vault/clippings/cover.png", article.data.fetch("image")
        assert_equal [expected, expected], [data["source_url"], data.fetch("favorite_card")["source_url"]]
        ["/", "/clippings/", "/favorites/"].each do |route|
          theme_data = page(result, "#{prefix}#{route}").data.dig("website", "theme_data")
          archive = theme_data.fetch("archive")
          cards = generated_json(result, archive.fetch("url").delete_suffix("manifest.json") + archive.fetch("chunks").first).fetch("cards")
          assert_equal [expected], cards.map { |card| card["source_url"] }, "#{prefix}#{route}"
          next if route == "/favorites/"

          displayed = theme_data.fetch("archive_groups").flat_map { |group| group.fetch("posts") }
          assert_equal [expected], displayed.map { |card| card["source_url"] }
          assert_equal [data.fetch("favorite_card")], displayed.map { |card| card.fetch("favorite_card") }
        end
      end
      assert_equal properties, result.notes.find { |item| item.id == "clippings/article.md" }.properties.slice("source", "source_url")
    end
  end

  def test_directory_tags_are_recursive_additive_deduplicated_and_do_not_publish_notes
    resolution = JekyllObsidian::ContentPolicy.resolve("directory_tags" => { "clippings" => ["source/clippings"], "clippings/work" => ["work"] })
    assert_empty resolution.diagnostics
    assert_equal %w[agents source/clippings work], resolution.policy.tags_for("clippings/work/item.md", %w[agents source/clippings])
    assert_empty resolution.policy.tags_for("clippings-other/item.md", nil)
    refute resolution.policy.publish?("clippings/work/item.md", {})
    [nil, [], { "../clippings" => [] }, { "clippings" => "tag" }, { "clippings" => [false] }, { "clippings" => [""] }].each do |value|
      refute_empty JekyllObsidian::ContentPolicy.resolve("directory_tags" => value).diagnostics
    end
  end

  def test_source_titles_are_trimmed_once_for_pages_and_archive_cards
    ["   ", "\n", "\t", "\u00a0", "\u2028", "\u2029", "\ufeff", " \u00a0\ufeff ",
      "  Original title \n", "\ufeff\u00a0Original title \ufeff"].each do |title|
      source = CLIPPING.sub("source_title: Original source title", "source_title: #{title.to_json}")
      original = source.dup
      result = compile(note("clippings/article.md", source), content: CONTENT, home: { "layout" => "archive" })
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      expected = title.include?("Original") ? "Original title" : ""
      assert_equal expected, page(result, "/clippings/article/").data.dig("website", "source_title")
      archive = page(result, "/").data.dig("website", "theme_data", "archive")
      card = generated_json(result, archive.fetch("url").delete_suffix("manifest.json") + archive.fetch("chunks").first).fetch("cards").first
      assert_equal expected, card.fetch("source_title")
      assert_equal original, source
    end
  end

  def test_bare_aliases_can_gain_a_namespace_without_allowing_chains_or_namespace_switches
    assert_empty JekyllObsidian::TagPolicy.resolve("tag_aliases" => { "agents" => "topics/agents" }).errors
    [{ "source/agents" => "topics/agents" }, { "agents" => "topics/old", "topics/old" => "topics/agents" }, { "agents" => "agents" }].each do |aliases|
      refute_empty JekyllObsidian::TagPolicy.resolve("tag_aliases" => aliases).errors
    end
  end
end
