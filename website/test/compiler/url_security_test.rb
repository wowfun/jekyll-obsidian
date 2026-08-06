# frozen_string_literal: true

require "test_helper"

class UrlSecurityTest < Minitest::Test
  def test_destination_registry_detects_exact_and_ancestor_collisions
    registry = JekyllObsidian::DestinationRegistry.new

    assert_nil registry.add("/guide/index.html", "/guide/")
    assert_equal "/guide/", registry.add("/guide/index.html", "/duplicate/")
    assert_equal "/guide/", registry.add("/guide", "/guide-file")
    assert_nil registry.add("/guides/index.html", "/guides/")

    ancestor_first = JekyllObsidian::DestinationRegistry.new
    assert_nil ancestor_first.add("/manual", "/manual-file")
    assert_equal "/manual-file", ancestor_first.add("/manual/start/index.html", "/manual/start/")
  end

  def test_permalink_rejects_encoded_separators_dot_segments_and_controls
    builder = JekyllObsidian::UrlBuilder.new(origin: "https://example.test", baseurl: "")
    invalid = [
      "/safe/%2e%2e/escape/",
      "/safe/%2E/escape/",
      "/safe/%2fescape/",
      "/safe/%5Cescape/",
      "/safe/%00/",
      "/safe/\u0001/",
      "/safe/%3Fquery/",
      "/safe/%23fragment/",
      "/safe/%3Atitle/"
    ]

    invalid.each do |permalink|
      assert_nil builder.validate_permalink(permalink), "expected #{permalink.inspect} to be rejected"
    end
    assert_equal "/Caf%C3%A9/", builder.validate_permalink("/Caf%C3%A9/")
  end

  def test_baseurl_rejects_obscured_path_boundaries_and_traversal
    invalid = [
      "/project/%2e%2e",
      "/project/%2E",
      "/project/%2Fchild",
      "/project/%5cchild",
      "/project/%00",
      "/project\n"
    ]

    invalid.each do |baseurl|
      result = compile(
        note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
        baseurl: baseurl
      )
      refute result.success?, "expected #{baseurl.inspect} to be rejected"
      assert result.diagnostics.any? { |item| item.code == "invalid_url_config" }
    end
  end

  def test_collision_key_is_canonical_and_rejects_unsafe_encoded_paths
    builder = JekyllObsidian::UrlBuilder.new(origin: "https://example.test", baseurl: "")

    assert_equal builder.collision_key("/Caf%C3%A9/"), builder.collision_key("/café/")
    assert_equal "/file?name/", builder.collision_key("/file%3Fname/")
    assert_raises(ArgumentError) { builder.collision_key("/file?name/") }
    assert_raises(ArgumentError) { builder.collision_key("/safe/%2Fhidden/") }
    assert_raises(ArgumentError) { builder.collision_key("/safe/%2e%2e/hidden/") }
    assert_raises(ArgumentError) { builder.collision_key("/safe/%00/") }
  end

  def test_notes_cannot_claim_generated_or_asset_namespaces
    reserved = [
      "/404.html/child/",
      "/feed.xml/",
      "/sitemap.xml/",
      "/assets/website/child/",
      "/assets/vault/child/"
    ]

    reserved.each do |permalink|
      result = compile(
        note("index.md", <<~MARKDOWN),
        ---
        publish: true
        permalink: #{permalink}
        updated: 2026-07-30
        ---
        # Reserved
        MARKDOWN
        note("posts/entry.md", "---\npublish: true\ncontent_type: post\ndate: 2026-07-30\n---\n# Entry"),
        theme: "minimal"
      )

      refute result.success?, "expected #{permalink.inspect} to be reserved"
      assert result.diagnostics.any? { |item| item.code == "route_collision" }
    end
  end

  def test_generated_index_names_do_not_reserve_unrelated_child_routes
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      note("graph/child.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Graph child"),
      note("tags/child.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Tags child"),
      note("notes/child.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Notes child")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert page(result, "/graph/child/")
    assert page(result, "/tags/child/")
    assert page(result, "/notes/child/")
  end
end
