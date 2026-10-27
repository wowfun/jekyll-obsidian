# frozen_string_literal: true

require "test_helper"

class PublishedMarkdownTest < Minitest::Test
  def test_image_projection_uses_the_same_table_footnote_and_math_grammar_as_html
    url = "https://example.test/assets/vault/image.png"
    table = "| Image | Text |\n| --- | --- |\n| A\\|B ![图\\|200](image.png) ![second](image.png) C | End |\n"
    second_cell = "| Text | Image |\n| --- | --- |\n| Start | A\\|B ![图\\|200][picture] C |\n\n[picture]: image.png\n"
    quoted = table.lines.map { |line| "> #{line}" }.join
    footnote = "Text[^1]\n\n[^1]: ![图](image.png)\n"
    math = "![real](image.png)\n\n$![literal](image.png)$\n\n$$\n![literal](image.png)\n$$\n"
    { table => table.gsub("(image.png)", "(#{url})"), quoted => quoted.gsub("(image.png)", "(#{url})"),
      second_cell => second_cell.sub("![图\\|200][picture]", "![图\\|200](#{url})"), footnote => footnote.sub("(image.png)", "(#{url})"),
      math => math.sub("![real](image.png)", "![real](#{url})") }.each do |body, expected|
      result = compile(note("index.md", "---\npublish: true\n---\n# Images\n\n#{body}"),
        attachment("image.png", "PNG", media_type: "image/png"))
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      actual = result.generated_files.find { |file| file.route == "/index.md" }.content
      assert_equal "# Images\n\n#{expected}", actual
    end
  end

  def test_destination_size_suffix_is_a_literal_filename_and_non_images_keep_authored_urls
    invalid = compile(note("index.md", "---\npublish: true\n---\n![alt](image.png|640)\n"),
      attachment("image.png", "PNG", media_type: "image/png"))
    refute invalid.success?
    assert invalid.diagnostics.any? { |item| item.code == "missing_embed" }

    body = "![PDF](paper.pdf#page=2)\n\n![Video](clip.mp4)\n"
    result = compile(note("index.md", "---\npublish: true\n---\n# Media\n\n#{body}"),
      attachment("paper.pdf", "%PDF", media_type: "application/pdf"),
      attachment("clip.mp4", "VIDEO", media_type: "video/mp4"))
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal "# Media\n\n#{body}", result.generated_files.find { |file| file.route == "/index.md" }.content
    assert_includes page(result, "/").content, "/assets/vault/paper.pdf#page=2"
    assert_includes page(result, "/").content, "/assets/vault/clip.mp4"
  end

  def test_image_projection_preserves_unicode_prose_and_all_markdown_line_endings
    ["\n", "\r\n", "\r"].each do |newline|
      body = ["# Unicode", "", "中文 😀 e\u0301\t![图](<assets/图 片.png>) 尾声", "",
        "引用 ![图片][picture] 后文", "", "[picture]: <assets/图 片.png>", "", "`![code](missing.png)`"].join(newline)
      result = compile(note("index.md", "---\npublish: true\n---\n#{body}"),
        attachment("assets/图 片.png", "PNG", media_type: "image/png"))
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      url = "https://example.test/assets/vault/assets/%E5%9B%BE%20%E7%89%87.png"
      expected = body.sub("![图](<assets/图 片.png>)", "![图](#{url})").sub("![图片][picture]", "![图片](#{url})") + "\n"
      actual = result.generated_files.find { |file| file.route == "/index.md" }.content
      assert actual.valid_encoding?, newline.inspect
      assert_equal expected, actual, newline.inspect
    end
  end

  def test_literal_pipes_in_markdown_destinations_are_not_embed_options
    # Snapshot entries avoid filesystem restrictions on literal pipes on Windows.
    ["https://example.test", ""].each do |origin|
      result = compile(
        note("clippings/article.md", "---\npublish: true\n---\n中文 ![inline|300x200](assets/a.png|b.png)\n\n![reference|120][picture]\n\n[ordinary][picture]\n\n[picture]: assets/a%7Cb.png\n\n![literal][literal]\n\n[literal]: assets/a|b.png\n"),
        attachment("clippings/assets/a.png", "wrong image", media_type: "image/png"),
        attachment("clippings/assets/a.png|b.png", "right image", media_type: "image/png"),
        attachment("clippings/assets/a|b.png", "other image", media_type: "image/png"),
        locale_manifest("_locale.yml", "name: English\n"),
        locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
        url: origin, environment: origin.empty? ? "development" : "production", baseurl: "/garden",
        i18n: { "enabled" => true, "locales" => %w[en zh-CN], "shared_directories" => ["clippings"] }
      )
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      ["", "/zh-CN"].each do |prefix|
        html = Nokogiri::HTML5.fragment(page(result, "#{prefix}/clippings/article/").content)
        paths = %w[/garden/assets/vault/clippings/assets/a.png%7Cb.png /garden/assets/vault/clippings/assets/a%7Cb.png /garden/assets/vault/clippings/assets/a%7Cb.png]
        assert_equal paths, html.css("img").map { |image| image["src"] }
        assert_equal %w[300 120], html.css("img").first(2).map { |image| image["width"] }
        assert_equal "200", html.at_css("img")["height"]
        text = result.generated_files.find { |file| file.route == "#{prefix}/clippings/article.md" }.content
        images = []
        Commonmarker.parse(text).walk { |node| images << node.url if node.type == :image }
        assert_equal paths.map { |path| "#{origin}#{path}" }, images
        assert_includes text, "![inline|300x200](#{origin}#{paths[0]})"
        assert_includes text, "![reference|120](#{origin}#{paths[1]})"
        assert_includes text, "[ordinary][picture]"
        assert_includes text, "[picture]: assets/a%7Cb.png"
      end
    end
  end

  def test_route_contract_uses_a_markdown_suffix_without_changing_page_routes
    assert_equal "/index.md", JekyllObsidian::PublishedMarkdown.route("/")
    assert_equal "/docs/Syntax.md", JekyllObsidian::PublishedMarkdown.route("/docs/Syntax/")
    assert_equal "/reference.html.md", JekyllObsidian::PublishedMarkdown.route("/reference.html")
  end

  def test_content_preserves_authored_markdown_and_adds_only_a_missing_h1
    with_h1 = JekyllObsidian::PublishedMarkdown.content(
      title: "Ignored",
      body: "# Authored\r\n\r\n![[Local note]]\r\n\r\n",
      has_h1: true
    )
    assert_equal "# Authored\r\n\r\n![[Local note]]\n", with_h1

    without_h1 = JekyllObsidian::PublishedMarkdown.content(
      title: "Guide [draft] #1",
      body: "Keep [[wikilinks]] and ==OFM==.\n\n",
      has_h1: false
    )
    assert_equal "# Guide \\[draft\\] \\#1\n\nKeep [[wikilinks]] and ==OFM==.\n", without_h1
  end

  def test_compiler_generates_one_frontmatter_free_resource_for_each_authored_public_note
    result = compile(
      note("index.md", "---\npublish: true\ntitle: Home\n---\n# Home\n\nRoot body.\n\n"),
      note("docs/Syntax.md", "---\npublish: true\ntitle: Syntax [guide]\n---\nBody keeps [[docs/Syntax]] and ==highlight==.\n\n"),
      baseurl: "/manual",
      theme: "docs"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    markdown = result.generated_files.select { |file| file.media_type == "text/markdown" }
    assert_equal %w[/docs/Syntax.md /index.md], markdown.map(&:route)
    assert_equal "# Home\n\nRoot body.\n", markdown.find { |file| file.route == "/index.md" }.content
    assert_equal(
      "# Syntax \\[guide\\]\n\nBody keeps [[docs/Syntax]] and ==highlight==.\n",
      markdown.find { |file| file.route == "/docs/Syntax.md" }.content
    )
    refute markdown.any? { |file| file.route.match?(%r{(?:404|tags|sitemap)}) }
    assert_equal "/manual/index.md", page(result, "/").data.dig("website", "markdown_url")
    assert_equal "/manual/docs/Syntax.md", page(result, "/docs/Syntax/").data.dig("website", "markdown_url")
  end

  def test_markdown_files_cannot_share_a_destination_with_a_page_directory
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("guide.md", "---\npublish: true\npermalink: /guide/\n---\n# Guide"),
      note("nested.md", "---\npublish: true\npermalink: /guide.md/\n---\n# Nested")
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "route_collision" }
  end

  def test_local_images_use_published_attachment_addresses_in_both_locales
    ["https://example.test", ""].each do |origin|
      body = "中文 ![inline *alt*](<assets/图 片.gif> \"animated\")\r\n\r\n![reference][shared]\r\n\r\n[ordinary][shared]\r\n\r\n[shared]: <assets/图 片.gif> 'title'\r\n\r\n`![code](assets/图.png)`\r\n\r\n<!-- ![comment](assets/图.png) -->\r\n"
      original = "---\npublish: true\n---\n#{body}"
      result = compile(
        note("clippings/article.md", original),
        attachment("clippings/assets/图 片.gif", "GIF89a", media_type: "image/gif"),
        locale_manifest("_locale.yml", "name: English\n"),
        locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
        url: origin, environment: origin.empty? ? "development" : "production", baseurl: "/garden", i18n: { enabled: true, locales: %w[en zh-CN], shared_directories: ["clippings"] }
      )
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      asset = "/garden/assets/vault/clippings/assets/%E5%9B%BE%20%E7%89%87.gif"
      %w[/clippings/article.md /zh-CN/clippings/article.md].each do |route|
        text = result.generated_files.find { |file| file.route == route }.content
        parsed = Commonmarker.parse(text)
        images = []
        parsed.walk { |node| images << node.url if node.type == :image }
        assert_equal ["#{origin}#{asset}"] * 2, images, text
        assert_includes text, "[ordinary][shared]"
        assert_includes text, "[shared]: <assets/图 片.gif> 'title'"
        assert_includes text, "`![code](assets/图.png)`"
        assert_includes text, "<!-- ![comment](assets/图.png) -->"
        html = page(result, route.delete_suffix(".md") + "/").content
        assert_includes html, asset
      end
      assert_equal "---\npublish: true\n---\n#{body}", original
    end
  end
end
