# frozen_string_literal: true

require "test_helper"

class ExternalMediaTest < Minitest::Test
  def test_direct_audio_formats_use_native_controls_and_exact_csp
    %w[3gp flac m4a mp3 ogg wav].each do |extension|
      url = "https://cdn.example/interview.#{extension.upcase}?token=signed"
      result = compile(note("index.md", "---\npublish: true\n---\n![Interview](#{url})\n"))
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      output = page(result, "/")
      audio = Nokogiri::HTML5.fragment(output.content).at_css("audio.website-external-audio")
      assert_equal "controls", audio["controls"]
      assert_equal "metadata", audio["preload"]
      assert_equal "Interview", audio["aria-label"]
      assert_equal url, audio.at_css("source")["src"]
      assert_equal JekyllObsidian::MediaPolicy.media_type("a.#{extension}"), audio.at_css("source")["type"]
      assert_equal ["https://cdn.example"], output.data.dig("website", "content_security", "media_sources")
      assert_equal url, audio.at_css("a")["href"]
    end
  end

  def test_remote_pdf_keeps_signed_query_and_normalizes_page_and_height
    url = "https://cdn.example/paper.PDF?token=signed#height=560&page=3"
    result = compile(note("index.md", "---\npublish: true\n---\n![Paper](#{url})\n"))
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    output = page(result, "/")
    document = Nokogiri::HTML5.fragment(output.content)
    card = document.at_css("[data-website-pdf-source]")
    assert_equal "https://cdn.example/paper.PDF?token=signed#page=3", card["data-website-pdf-source"]
    assert_equal "560", card["data-pdf-height"]
    assert_empty card.css("iframe, object")
    assert card.at_css("button[data-pdf-preview][hidden]")
    assert_equal "https://cdn.example/paper.PDF?token=signed#page=3", document.at_css("a.website-external-pdf__fallback")["href"]
    assert_equal ["blob:"], output.data.dig("website", "content_security", "frame_sources")
    assert_equal ["https://cdn.example"], output.data.dig("website", "content_security", "connect_sources")
    assert_empty output.data.dig("website", "content_security", "media_sources")
  end

  def test_arxiv_pdf_urls_work_without_an_extension_but_abstract_urls_stay_links
    %w[2609.12345 2609.1234v2 hep-th/9901001 math.GT/0309136v1].each do |identifier|
      descriptor = JekyllObsidian::ExternalMedia.resolve("https://arxiv.org/pdf/#{identifier}")
      assert_equal :pdf, descriptor.kind
      assert_equal 640, descriptor.height
    end
    result = compile(note("index.md", "---\npublish: true\n---\n[Abstract](https://arxiv.org/abs/2609.12345)\n"))
    assert result.success?
    refute_includes page(result, "/").content, "<iframe"
  end

  def test_invalid_remote_pdf_options_and_audio_fragments_fail_predictably
    %w[page=0 page=-1 page=1&page=2 height=63 height=4097 toolbar=0 page=1&unknown=x].each do |fragment|
      result = compile(note("index.md", "---\npublish: true\n---\n![](https://cdn.example/paper.pdf##{fragment})\n"))
      refute result.success?, fragment
      assert result.diagnostics.any? { |item| item.code == "invalid_external_media" }, fragment
    end
    result = compile(note("index.md", "---\npublish: true\n---\n![](https://cdn.example/interview.mp3#t=3)\n"))
    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "invalid_external_media" }
  end

  def test_local_pdf_options_follow_the_same_policy_as_remote_options
    %w[page=0 page=-1 page=1&page=2 height=63 height=4097 toolbar=0].each do |fragment|
      result = compile(note("index.md", "---\npublish: true\n---\n![[paper.pdf##{fragment}]]\n"))
      refute result.success?, fragment
      assert result.diagnostics.any? { |item| item.code == "invalid_pdf_options" }, fragment
    end
  end

  def test_transclusion_carries_audio_and_pdf_origins_to_the_host
    result = compile(
      note("index.md", "---\npublish: true\n---\n![[media]]\n"),
      note("media.md", "---\npublish: true\n---\n![Audio](https://cdn.example/a.ogg)\n\n![PDF](https://papers.example/a.pdf)\n")
    )
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal ["https://cdn.example"], page(result, "/").data.dig("website", "content_security", "media_sources")
    assert_equal ["blob:"], page(result, "/").data.dig("website", "content_security", "frame_sources")
    assert_equal ["https://papers.example"], page(result, "/").data.dig("website", "content_security", "connect_sources")
  end

  def test_external_images_keep_image_semantics_and_obsidian_dimensions
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      ---
      # Home
      ![Animation|320x180](https://media.example/loop.gif)
      ![250](https://media.example/photo.webp)
    MARKDOWN

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    document = Nokogiri::HTML5.fragment(page(result, "/").content)
    animation = document.at_css("img[src='https://media.example/loop.gif']")
    assert_equal "Animation", animation["alt"]
    assert_equal "320", animation["width"]
    assert_equal "180", animation["height"]
    photo = document.at_css("img[src='https://media.example/photo.webp']")
    assert_equal "", photo["alt"]
    assert_equal "250", photo["width"]
    assert_equal "lazy", photo["loading"]
  end

  def test_https_direct_video_uses_native_controls_but_a_normal_link_stays_a_link
    url = "https://cdn.example/media/clip.mp4?token=signed"
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      ---
      # Home
      ![Product tour](#{url})
      [Download](#{url})
    MARKDOWN

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    output = page(result, "/")
    document = Nokogiri::HTML5.fragment(output.content)
    video = document.at_css("video.website-external-video")
    assert_equal "controls", video["controls"]
    assert_equal "metadata", video["preload"]
    assert video.key?("playsinline")
    assert_equal "Product tour", video["aria-label"]
    assert_equal url, video.at_css("source")["src"]
    assert_equal "video/mp4", video.at_css("source")["type"]
    download = document.css("a").find { |link| link.text == "Download" }
    assert_equal url, download["href"]
    assert_equal ["https://cdn.example"], output.data.dig("website", "content_security", "media_sources")
    assert_empty result.relations
    assert_empty result.projected_files
  end

  def test_external_image_urls_require_encoded_pipes_and_keep_alt_dimensions
    invalid = compile(note("index.md", "---\npublish: true\n---\n![Diagram|10x20](https://example.test/a|b.png)\n"))
    refute invalid.success?
    assert invalid.diagnostics.any? { |item| item.code == "invalid_external_media" }

    url = "https://example.test/a%7Cb.png"
    result = compile(note("index.md", "---\npublish: true\n---\n![Diagram|10x20](#{url})\n"))
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    image = Nokogiri::HTML5.fragment(page(result, "/").content).at_css("img")
    assert_equal url, image["src"]
    assert_equal "Diagram", image["alt"]
    assert_equal "10", image["width"]
    assert_equal "20", image["height"]
  end

  def test_common_video_urls_become_canonical_lazy_players
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      ---
      # Home
      ![YouTube demo](https://www.youtube.com/watch?v=NnTvZWp5Q7o&t=1m30s)
      ![](https://www.bilibili.com/video/BV1E7411e7hC?p=2)
      ![](https://vimeo.com/212731897)
    MARKDOWN

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    output = page(result, "/")
    document = Nokogiri::HTML5.fragment(output.content)
    frames = document.css("iframe.website-external-player")
    assert_equal 3, frames.length
    assert_equal "https://www.youtube-nocookie.com/embed/NnTvZWp5Q7o?start=90", frames[0]["src"]
    assert_equal "YouTube demo", frames[0]["title"]
    assert_equal "strict-origin-when-cross-origin", frames[0]["referrerpolicy"]
    assert_equal "https://player.bilibili.com/player.html?bvid=BV1E7411e7hC&p=2", frames[1]["src"]
    assert_equal "Bilibili video player", frames[1]["title"]
    assert_equal "https://player.vimeo.com/video/212731897?dnt=1", frames[2]["src"]
    assert_equal %w[
      https://player.bilibili.com
      https://player.vimeo.com
      https://www.youtube-nocookie.com
    ], output.data.dig("website", "content_security", "frame_sources")
  end

  def test_raw_iframe_html_is_rebuilt_through_provider_and_sandbox_policies
    result = compile(note("index.md", <<~HTML))
      ---
      publish: true
      ---
      # Home
      <iframe src="https://www.youtube.com/embed/NnTvZWp5Q7o" title="Copied player" onload="alert(1)"></iframe>
      <iframe src="https://example.test/arbitrary"></iframe>
    HTML

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    output = page(result, "/")
    document = Nokogiri::HTML5.fragment(output.content)
    provider = document.at_css("iframe.website-external-player--youtube")
    assert_equal "https://www.youtube-nocookie.com/embed/NnTvZWp5Q7o", provider["src"]
    assert_equal "Copied player", provider["title"]
    refute provider.key?("onload")

    frame = document.at_css("iframe[data-website-external-frame='web']")
    assert_equal "https://example.test/arbitrary", frame["src"]
    assert_equal JekyllObsidian::ExternalMedia::IFRAME_SANDBOX, frame["sandbox"]
    assert_equal "480", frame["height"]
    refute frame.key?("srcdoc")
    assert_equal %w[https://example.test https://www.youtube-nocookie.com],
      output.data.dig("website", "content_security", "frame_sources")
  end

  def test_raw_iframe_rejects_insecure_or_unclosed_elements
    [
      '<iframe src="http://example.test"></iframe>',
      '<iframe src="https://user:secret@example.test"></iframe>',
      '<iframe src="https://example.test">',
      '<iframe src="https://example.test"'
    ].each do |markup|
      result = compile(note("index.md", "---\npublish: true\n---\n# Home\n#{markup}\n"))
      refute result.success?, markup
      assert result.diagnostics.any? { |item| item.code == "invalid_external_media" }, markup
    end
  end

  def test_obsidian_tweet_syntax_builds_a_lazy_widget_marker_and_exact_csp
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      ---
      # Home
      ![](https://twitter.com/obsdmd/status/1580548874246443010?s=20)
    MARKDOWN

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    output = page(result, "/")
    document = Nokogiri::HTML5.fragment(output.content)
    tweet = document.at_css("[data-website-tweet='1580548874246443010']")
    refute_nil tweet
    fallback = tweet.at_css("[data-website-tweet-fallback]")
    assert_equal "https://x.com/obsdmd/status/1580548874246443010", fallback["href"]
    assert_equal ["https://platform.twitter.com"], output.data.dig("website", "content_security", "script_sources")
    assert_equal ["https://platform.twitter.com"], output.data.dig("website", "content_security", "frame_sources")
  end

  def test_x_web_status_url_builds_a_tweet_instead_of_an_image
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      ---
      # Home
      ![](https://x.com/i/web/status/1580548874246443010)
    MARKDOWN

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    document = Nokogiri::HTML5.fragment(page(result, "/").content)
    tweet = document.at_css("[data-website-tweet='1580548874246443010']")
    refute_nil tweet
    assert_equal "https://x.com/i/web/status/1580548874246443010",
      tweet.at_css("[data-website-tweet-fallback]")["href"]
    refute document.at_css("img")
  end

  def test_block_external_media_rejects_inline_markdown_ancestors
    [
      '[![Demo](https://www.youtube.com/watch?v=NnTvZWp5Q7o)](https://example.test)',
      '**![](https://vimeo.com/212731897)**',
      '# ![](https://x.com/obsdmd/status/1580548874246443010)',
      '<em>![](https://x.com/obsdmd/status/1580548874246443010)</em>',
      '<a href="https://example.test">![](https://www.youtube.com/watch?v=NnTvZWp5Q7o)</a>'
    ].each do |markup|
      result = compile(note("index.md", "---\npublish: true\n---\n# Home\n#{markup}\n"))

      refute result.success?, markup
      assert result.diagnostics.any? { |item| item.code == "invalid_external_media" }, markup
    end
  end

  def test_invalid_provider_urls_fail_instead_of_rendering_broken_images
    cases = [
      "https://www.youtube.com/watch?v=too-short",
      "https://b23.tv/short-code",
      "https://www.youtube.com.evil.test/watch?v=NnTvZWp5Q7o"
    ]
    cases.each do |url|
      result = compile(note("index.md", "---\npublish: true\n---\n# Home\n![](#{url})"))
      if url.include?("evil.test")
        assert result.success?, result.diagnostics.map(&:message).join("\n")
        assert_includes page(result, "/").content, "<img"
      else
        refute result.success?, url
        assert result.diagnostics.any? { |item| item.code == "invalid_external_media" }, url
      end
    end
  end

  def test_https_image_without_an_authority_is_a_controlled_diagnostic
    result = compile(note("index.md", "---\npublish: true\n---\n# Home\n![Broken](https:foo)"))

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "invalid_external_media" }
  end

  def test_transclusion_carries_player_csp_to_the_host_page
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home\n![[player]]"),
      note("player.md", "---\npublish: true\n---\n# Player\n![](https://vimeo.com/212731897)")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal ["https://player.vimeo.com"],
      page(result, "/").data.dig("website", "content_security", "frame_sources")
    assert_includes page(result, "/").content, "player.vimeo.com/video/212731897"
  end
end
