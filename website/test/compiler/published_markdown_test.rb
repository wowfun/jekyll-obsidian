# frozen_string_literal: true

require "test_helper"

class PublishedMarkdownTest < Minitest::Test
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
end
