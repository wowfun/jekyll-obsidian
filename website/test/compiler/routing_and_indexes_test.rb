# frozen_string_literal: true

require "test_helper"

class RoutingAndIndexesTest < Minitest::Test
  def test_url_builder_covers_github_and_custom_domain_root_and_project_sites
    cases = [
      ["GitHub user site", "https://owner.github.io", "", "/Notes/Caf%C3%A9/", "https://owner.github.io/Notes/Caf%C3%A9/"],
      ["GitHub project site", "https://owner.github.io", "/repo", "/repo/Notes/Caf%C3%A9/", "https://owner.github.io/repo/Notes/Caf%C3%A9/"],
      ["custom-domain root site", "https://garden.example", "", "/Notes/Caf%C3%A9/", "https://garden.example/Notes/Caf%C3%A9/"],
      ["custom-domain project site", "https://garden.example", "/repo", "/repo/Notes/Caf%C3%A9/", "https://garden.example/repo/Notes/Caf%C3%A9/"]
    ]

    cases.each do |label, origin, baseurl, expected_href, expected_absolute_url|
      builder = JekyllObsidian::UrlBuilder.new(origin: origin, baseurl: baseurl)
      route = builder.route_for_note("Notes/Cafe\u0301.md")

      assert_equal "/Notes/Caf%C3%A9/", route, label
      assert_equal expected_href, builder.href(route), label
      assert_equal expected_absolute_url, builder.absolute_url(route), label
      assert_equal 1, builder.href(route).scan(%r{#{Regexp.escape(baseurl)}/}).length, label unless baseurl.empty?
    end
  end

  def test_url_builder_keeps_non_default_ports_for_each_scheme
    assert_equal "https://example.test:80/note/", JekyllObsidian::UrlBuilder.new(origin: "https://example.test:80", baseurl: "").absolute_url("/note/")
    assert_equal "http://example.test:443/note/", JekyllObsidian::UrlBuilder.new(origin: "http://example.test:443", baseurl: "").absolute_url("/note/")
    assert_equal "https://example.test/note/", JekyllObsidian::UrlBuilder.new(origin: "https://example.test:443", baseurl: "").absolute_url("/note/")
    assert_nil JekyllObsidian::UrlBuilder.new(origin: "", baseurl: "/project").absolute_url("/note/")
  end

  def test_implicit_source_relative_resolution_precedes_basename_fallback
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("guides/page.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Page\n[[child]]"),
      note("guides/child.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Local child")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_includes page(result, "/guides/page/").content, 'href="/guides/child/"'
  end

  def test_routes_separate_permalink_route_href_and_absolute_url
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\n[[Notes/Café]]"),
      note("Notes/Café.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Café"),
      baseurl: "/project"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    home = page(result, "/")
    cafe = page(result, "/Notes/Caf%C3%A9/")
    refute_nil cafe
    assert_equal "/Notes/Caf%C3%A9/", cafe.route
    assert_includes home.content, 'href="/project/Notes/Caf%C3%A9/"'
    assert_equal "/project/Notes/Caf%C3%A9/", cafe.data.dig("website", "href")
    assert_equal "https://example.test/project/Notes/Caf%C3%A9/", cafe.data.dig("website", "absolute_url")
  end

  def test_permalink_is_strict_and_cannot_contain_baseurl_or_placeholders
    invalid = [
      "project/note/", "/project/note", "/x?query=1/", "/x#fragment/",
      "https://evil.test/", "/../escape/", "/:title/"
    ]

    invalid.each do |permalink|
      result = compile(note("index.md", "---\npublish: true\npermalink: #{permalink.inspect}\n---\n# Bad"))
      refute result.success?, "expected #{permalink.inspect} to fail"
      assert result.diagnostics.any? { |item| item.code == "invalid_permalink" }
    end
  end

  def test_root_index_cannot_move_the_home_route
    result = compile(
      note("index.md", "---\npublish: true\npermalink: /elsewhere/\n---\n# Home"),
      theme: "minimal"
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "invalid_home_permalink" }
  end

  def test_equivalent_routes_collide_fail_closed
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("Foo.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Upper"),
      note("foo.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Lower")
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "route_collision" }
  end

  def test_versioned_indexes_are_stable_and_note_level
    result = compile(
      note("index.md", "---\npublish: true\naliases: [Start]\ntags: [garden, cjk/中文]\ndescription: Intro\nupdated: 2026-07-30\n---\n# Home\nAuthored words."),
      note("other.md", "---\npublish: true\nupdated: 2026-07-29\n---\n# Other\n![[index]]"),
      theme: "minimal"
    )

    catalog = generated_json(result, "/assets/website/catalog.v1.json")
    graph = generated_json(result, "/assets/website/graph.v1.json")
    search = generated_json(result, "/assets/website/search.v1.json")
    assert_equal 1, catalog.fetch("schema_version")
    assert_equal 1, graph.fetch("schema_version")
    assert_equal 1, search.fetch("schema_version")
    assert_equal %w[index.md other.md], catalog.fetch("notes").map { |item| item.fetch("id") }
    home_search = search.fetch("documents").find { |item| item.fetch("id") == "index.md" }
    assert_includes home_search.fetch("text"), "Authored words"
    other_search = search.fetch("documents").find { |item| item.fetch("id") == "other.md" }
    refute_includes other_search.fetch("text"), "Authored words"
    assert_equal "embed", graph.fetch("edges").first.fetch("kind")
  end

  def test_tag_anchors_are_stable_when_slug_forms_collide
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("blog/tags.md", <<~MARKDOWN),
      ---
      publish: true
      content_type: post
      date: 2026-07-30
      tags: ["a b", "a-b"]
      updated: 2026-07-30
      ---
      # Tagged post
      MARKDOWN
      theme: "minimal"
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    anchors = page(result, "/blog/").data.dig("website", "theme_data", "topic_summaries")
      .map { |topic| topic.fetch("anchor") }
    assert_includes anchors, "a-b"
    assert_includes anchors, "a-b-2"
    tag_links = page(result, "/blog/tags/").data.dig("website", "tag_links")
    assert_equal ["a-b", "a-b-2"], tag_links.map { |item| item.fetch("anchor") }
  end
end
