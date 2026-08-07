# frozen_string_literal: true

require "test_helper"

class MediaAndFeedTest < Minitest::Test
  def test_portfolio_cards_publish_supported_animated_image_formats_without_rewriting_their_urls
    formats = {
      "gif" => "image/gif",
      "webp" => "image/webp",
      "avif" => "image/avif",
      "png" => "image/png",
      "apng" => "image/apng"
    }
    entries = [note("index.md", "---\npublish: true\n---\n# Home")]
    formats.each_with_index do |(extension, media_type), index|
      entries << note(
        "portfolio/#{extension}.md",
        "---\npublish: true\nnav_order: #{index}\nimage: media/animated.#{extension}\n---\n# #{extension.upcase}"
      )
      entries << attachment("media/animated.#{extension}", "#{extension}-bytes", media_type: media_type)
    end

    result = compile(*entries, theme: "minimal")

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    cards = page(result, "/portfolio/").data.dig("website", "theme_data", "portfolio_projects")
      .to_h { |card| [File.basename(card.fetch("id"), ".md"), card] }
    assets = result.copied_assets.to_h { |asset| [File.extname(asset.source_path).delete_prefix("."), asset] }
    formats.each do |extension, media_type|
      assert_equal(
        "https://example.test/assets/vault/media/animated.#{extension}",
        cards.fetch(extension).fetch("image")
      )
      assert_equal media_type, assets.fetch(extension).media_type
    end
  end

  def test_only_reachable_media_is_projected
    result = compile(
      note("index.md", "---\npublish: true\nimage: media/cover.png\nupdated: 2026-07-30\n---\n# Home\n![[media/song.mp3]]\n[[files/board.canvas]]"),
      attachment("media/cover.png", "png", media_type: "image/png"),
      attachment("media/song.mp3", "mp3", media_type: "audio/mpeg"),
      attachment("files/board.canvas", "{\"nodes\":[]}", media_type: "application/json"),
      attachment("media/private.png", "secret", media_type: "image/png")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    routes = result.copied_assets.map(&:route)
    assert_equal [
      "/assets/vault/files/board.canvas",
      "/assets/vault/media/cover.png",
      "/assets/vault/media/song.mp3"
    ], routes
    refute routes.any? { |route| route.include?("private") }
    assert_includes page(result, "/").content, "website-download-card"
    assert_includes page(result, "/").content, "<audio"
    assert_equal "https://example.test/assets/vault/media/cover.png", page(result, "/").data.fetch("image")
  end

  def test_production_requires_an_origin_but_development_omits_absolute_metadata
    production = compile(note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"), url: "")
    refute production.success?
    assert production.diagnostics.any? { |item| item.code == "missing_origin" }

    development = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      url: "",
      environment: "development"
    )
    assert development.success?, development.diagnostics.map(&:message).join("\n")
    assert_nil page(development, "/").data.dig("website", "absolute_url")
  end

  def test_media_options_and_dangerous_schemes
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      updated: 2026-07-30
      ---
      # Home
      ![[photo.png|320x180]]
      ![[paper.pdf#page=3&height=480]]
      [bad](javascript:alert(1))
    MARKDOWN

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "unsafe_url" }
  end

  def test_markdown_image_dimensions_and_media_extensions_have_one_canonical_kind
    result = compile(
      note("index.md", <<~MARKDOWN),
        ---
        publish: true
        updated: 2026-07-30
        ---
        # Home
        ![Field sketch|320x180](media/sketch.png)
        ![[media/interview.webm]]
        ![[media/walkthrough.webm]]
        ![[media/voice.3gp]]
        ![[media/clip.3gp]]
      MARKDOWN
      attachment("media/sketch.png", "png", media_type: "image/png"),
      attachment("media/interview.webm", "audio", media_type: "audio/webm"),
      attachment("media/walkthrough.webm", "video", media_type: "video/webm"),
      attachment("media/voice.3gp", "audio", media_type: "audio/3gpp"),
      attachment("media/clip.3gp", "video", media_type: "video/3gpp")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    document = Nokogiri::HTML5.fragment(page(result, "/").content)
    image = document.at_css('img[alt="Field sketch"]')
    assert_equal "320", image["width"]
    assert_equal "180", image["height"]
    assert_equal 2, document.css("audio").length
    assert_equal 2, document.css("video").length
    assert_equal %w[audio/3gpp audio/3gpp], document.css("audio source").map { |node| node["type"] }.sort
    assert_equal %w[video/webm video/webm], document.css("video source").map { |node| node["type"] }.sort
  end

  def test_only_explicitly_supported_attachment_types_are_published
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n![[archive.bin]]\n![[database.base]]"),
      attachment("archive.bin", "unknown", media_type: "application/octet-stream"),
      attachment("database.base", "{}", media_type: "application/json")
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "unsupported_attachment" }
    assert_instance_of JekyllObsidian::BuildFailure, result
  end

  def test_feed_omits_only_notes_without_a_deterministic_time
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("posts/dated.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-30\n---\n# Dated"),
      note("posts/timeless.md", "---\npublish: true\ncontent_type: post\n---\n# Timeless"),
      theme: "minimal",
      environment: "development"
    )

    assert result.success?
    feed = result.generated_files.find { |item| item.route == "/feed.xml" }
    refute_nil feed
    assert_includes feed.content, "Dated"
    refute_includes feed.content, "Timeless"
    assert result.diagnostics.any? { |item| item.code == "feed_omitted_missing_time" }
  end

  def test_post_first_commit_enables_feed_without_synthesizing_updated
    result = compile(
      note(
        "posts/git.md",
        "---\npublish: true\ncontent_type: post\n---\n# Git dated",
        first_committed_at: "2026-07-01T01:02:03Z"
      ),
      theme: "minimal"
    )

    assert_nil page(result, "/posts/git/").data.dig("website", "updated")
    feed = result.generated_files.find { |item| item.route == "/feed.xml" }
    refute_nil feed
    assert_includes feed.content, "<updated>2026-07-01T01:02:03Z</updated>"
    refute_includes feed.content, "#{Time.now.year + 1}"
  end

  def test_yaml_date_is_rfc3339_utc_midnight_and_datetime_keeps_its_offset
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("posts/date.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-30\nupdated: 2026-07-30\n---\n# Date"),
      note("posts/timed.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-30\nupdated: '2026-07-30T04:05:06+08:00'\n---\n# Timed"),
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    feed = result.generated_files.find { |item| item.route == "/feed.xml" }
    refute_nil feed
    assert_includes feed.content, "<updated>2026-07-30T00:00:00Z</updated>"
    assert_includes feed.content, "<updated>2026-07-30T04:05:06+08:00</updated>"
  end

  def test_public_text_rejects_xml_forbidden_control_characters_before_feed_generation
    body_result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\nbad\u0001text")
    )

    refute body_result.success?
    assert body_result.diagnostics.any? { |item| item.code == "invalid_character" }
    assert_instance_of JekyllObsidian::BuildFailure, body_result

    property_result = compile(
      note("index.md", <<~'MARKDOWN')
        ---
        publish: true
        title: "bad\x01title"
        aliases: ["bad\x01alias"]
        description: "bad\x01description"
        updated: 2026-07-30
        ---
        # Safe fallback
      MARKDOWN
    )

    refute property_result.success?
    invalid_properties = property_result.diagnostics.select { |item| item.code == "invalid_property" }
    assert_operator invalid_properties.length, :>=, 3

    config_result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      title: "Bad\u0001Title"
    )
    refute config_result.success?
    assert config_result.diagnostics.any? { |item| item.code == "invalid_config_character" }
    assert_instance_of JekyllObsidian::BuildFailure, config_result
  end
end
