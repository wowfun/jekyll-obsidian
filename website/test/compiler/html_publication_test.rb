# frozen_string_literal: true

require "test_helper"

class HtmlPublicationTest < Minitest::Test
  def test_publishes_a_standalone_html_file_at_its_configured_route
    result = compile(
      note(
        "index.md",
        "---\npublish: true\n---\n# Home\n\n[[slides/status.html|Open the slides]]\n\n[Open with Markdown](slides/status.html)"
      ),
      attachment(
        "slides/status.html",
        "<!doctype html><title>Status</title><script>window.deckReady = true</script>",
        media_type: "text/html"
      ),
      html: { "slides/status.html" => "/status.html" }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    projected_routes = result.projected_files.filter_map do |file|
      file.route if file.source_path == "slides/status.html"
    end
    assert_equal ["/status.html"], projected_routes
    assert_equal 2, page(result, "/").content.scan('href="/status.html"').length

    manifest = generated_json(result, "/assets/website/raw-html.v1.json")
    assert_equal 1, manifest.fetch("schema_version")
    assert_equal [{ "route" => "/status.html", "output" => "/status.html" }], manifest.fetch("documents")
    assert_equal ["/status.html"], manifest.fetch("files")
    refute_includes result.generated_files.find { |file| file.route == "/sitemap.xml" }.content, "/status.html"
    discovery = result.generated_files.select do |file|
      file.route.match?(%r{/(?:catalog|graph|search)\.v1\.json\z}) || file.route == "/feed.xml"
    end
    discovery.each { |file| refute_includes file.content, "/status.html", file.route }
    navigation = Array(page(result, "/").data.dig("website", "navigation"))
    refute navigation.any? { |item| item["url"] == "/status.html" }
  end

  def test_publishes_a_directory_bundle_without_claiming_markdown
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home\n\n[[slides/status.html|Open slides]]"),
      note("slides/runtime/speaker-notes.md", "---\npublish: false\n---\nPrivate notes"),
      locale_manifest("slides/runtime/_locale.yml", "name: Bundle metadata\n"),
      attachment("slides/runtime/index.html", "<!doctype html><link rel=\"stylesheet\" href=\"./theme.css\"><script src=\"./deck.js\"></script>", media_type: "text/html"),
      attachment("slides/runtime/theme.css", "body { color: rebeccapurple; }", media_type: "text/css"),
      attachment("slides/runtime/deck.js", "window.deckReady = true", media_type: "text/javascript"),
      attachment("slides/runtime/data.deck", "opaque slide data"),
      html: { "slides/runtime" => "/presentations/runtime/" }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    routes = result.projected_files.filter_map do |file|
      file.route if file.source_path.start_with?("slides/runtime/")
    end
    assert_equal [
      "/presentations/runtime/data.deck",
      "/presentations/runtime/deck.js",
      "/presentations/runtime/index.html",
      "/presentations/runtime/theme.css"
    ], routes
    refute result.projected_files.any? { |file| file.source_path.end_with?(".md") }
    refute result.projected_files.any? { |file| File.basename(file.source_path) == "_locale.yml" }

    manifest = generated_json(result, "/assets/website/raw-html.v1.json")
    assert_equal [
      { "route" => "/presentations/runtime/", "output" => "/presentations/runtime/index.html" }
    ], manifest.fetch("documents")
    assert_equal routes, manifest.fetch("files")
  end

  def test_frontmatter_image_reuses_its_bundle_route_without_a_second_projection
    result = compile(
      note(
        "index.md",
        "---\npublish: true\nimage: slides/runtime/assets/cover.svg\n---\n# Home"
      ),
      attachment("slides/runtime/index.html", "<!doctype html><title>Runtime</title>", media_type: "text/html"),
      attachment("slides/runtime/assets/cover.svg", "<svg/>", media_type: "image/svg+xml"),
      html: { "slides/runtime" => "/talks/runtime/" }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    cover_files = result.projected_files.select { |file| file.source_path == "slides/runtime/assets/cover.svg" }
    assert_equal ["/talks/runtime/assets/cover.svg"], cover_files.map(&:route)
    assert_equal "https://example.test/talks/runtime/assets/cover.svg", page(result, "/").data.fetch("image")
  end

  def test_markdown_image_embeds_a_bundle_asset_from_its_mapped_route
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home\n\n![Cover](slides/runtime/assets/cover.svg)"),
      attachment("slides/runtime/index.html", "<!doctype html><title>Runtime</title>", media_type: "text/html"),
      attachment("slides/runtime/assets/cover.svg", "<svg/>", media_type: "image/svg+xml"),
      html: { "slides/runtime" => "/talks/runtime/" }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    image = Nokogiri::HTML5.fragment(page(result, "/").content).at_css('img[alt="Cover"]')
    refute_nil image
    assert_equal "/talks/runtime/assets/cover.svg", image["src"]
    cover_files = result.projected_files.select { |file| file.source_path == "slides/runtime/assets/cover.svg" }
    assert_equal ["/talks/runtime/assets/cover.svg"], cover_files.map(&:route)
  end

  def test_rejects_overlapping_html_sources
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      attachment("slides/index.html", "<!doctype html><title>All slides</title>", media_type: "text/html"),
      attachment("slides/runtime/index.html", "<!doctype html><title>Runtime</title>", media_type: "text/html"),
      html: {
        "slides" => "/presentations/",
        "slides/runtime" => "/runtime/"
      }
    )

    refute result.success?
    diagnostic = result.diagnostics.find { |item| item.code == "overlapping_html_source" }
    refute_nil diagnostic
    assert_equal "slides/runtime", diagnostic.path
    assert_includes diagnostic.message, "slides"
  end

  def test_normalizes_unicode_html_file_routes
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      attachment("slides/产品演示.html", "<!doctype html><title>产品演示</title>", media_type: "text/html"),
      html: { "slides/产品演示.html" => "/talks/产品 演示.html" }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal ["/talks/%E4%BA%A7%E5%93%81%20%E6%BC%94%E7%A4%BA.html"], result.projected_files.map(&:route)
  end

  def test_reports_explicit_html_configuration_errors
    invalid_config = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      html: ["slides/status.html"]
    )
    invalid_source = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      html: { "_translations" => "/translations/" }
    )
    missing_source = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      html: { "slides/status.html" => "/status.html" }
    )
    missing_index = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      attachment("slides/runtime/deck.js", "window.deckReady = true", media_type: "text/javascript"),
      html: { "slides/runtime" => "/runtime/" }
    )

    assert_includes invalid_config.diagnostics.map(&:code), "invalid_html_config"
    assert_includes invalid_source.diagnostics.map(&:code), "invalid_html_source"
    assert_includes missing_source.diagnostics.map(&:code), "missing_html_source"
    assert_includes missing_index.diagnostics.map(&:code), "missing_html_source"
  end

  def test_rejects_an_unsafe_bundle_member_path_with_a_diagnostic
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      attachment("slides/runtime/index.html", "<!doctype html><title>Runtime</title>", media_type: "text/html"),
      attachment("slides/runtime/bad\nfile.deck", "opaque slide data"),
      html: { "slides/runtime" => "/runtime/" }
    )

    refute result.success?
    diagnostic = result.diagnostics.find { |item| item.code == "invalid_html_source" }
    refute_nil diagnostic
    assert_equal "slides/runtime/bad\nfile.deck", diagnostic.path
  end

  def test_rejects_reserved_unsafe_and_baseurl_prefixed_routes
    entries = [
      note("index.md", "---\npublish: true\n---\n# Home"),
      attachment("slides/status.html", "<!doctype html><title>Status</title>", media_type: "text/html")
    ]

    [
      ["/assets/website/status.html", ""],
      ["/status.html?mode=present", ""],
      ["/project/status.html", "/project"]
    ].each do |route, baseurl|
      result = compile(*entries, baseurl: baseurl, html: { "slides/status.html" => route })

      assert_includes result.diagnostics.map(&:code), "invalid_html_route", route
    end
  end

  def test_rejects_raw_html_embeds_with_a_specific_diagnostic
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home\n\n![[slides/status.html]]"),
      attachment("slides/status.html", "<!doctype html><title>Status</title>", media_type: "text/html"),
      html: { "slides/status.html" => "/status.html" }
    )

    refute result.success?
    assert_includes result.diagnostics.map(&:code), "html_embed_unsupported"
  end

  def test_reports_both_owners_when_an_html_bundle_collides_with_a_markdown_index
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      note("docs/index.md", "---\npublish: true\n---\n# Docs"),
      attachment("slides/runtime/index.html", "<!doctype html><title>Runtime</title>", media_type: "text/html"),
      html: { "slides/runtime" => "/docs/" }
    )

    refute result.success?
    diagnostic = result.diagnostics.find { |item| item.code == "route_collision" }
    refute_nil diagnostic
    assert_includes diagnostic.message, "slides/runtime/index.html"
    assert_includes diagnostic.message, "docs/index.md"
  end

  def test_reports_a_route_collision_when_two_html_sources_share_a_target
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      attachment("slides/a.html", "<!doctype html><title>A</title>", media_type: "text/html"),
      attachment("slides/b.html", "<!doctype html><title>B</title>", media_type: "text/html"),
      html: {
        "slides/a.html" => "/same.html",
        "slides/b.html" => "/same.html"
      }
    )

    refute result.success?
    diagnostic = result.diagnostics.find { |item| item.code == "route_collision" }
    refute_nil diagnostic
    assert_includes diagnostic.message, "slides/a.html"
    assert_includes diagnostic.message, "slides/b.html"
  end

  def test_localized_sites_publish_one_shared_html_projection
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home\n\n[[slides/status.html|Open slides]]"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\nhreflang: zh-Hans\ndir: ltr\n"),
      attachment("slides/status.html", "<!doctype html><title>Status</title>", media_type: "text/html"),
      theme: "docs",
      i18n: { "locales" => %w[en zh-CN] },
      html: { "slides/status.html" => "/status.html" }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    projected_routes = result.projected_files.filter_map do |file|
      file.route if file.source_path == "slides/status.html"
    end
    manifest_routes = result.generated_files.filter_map do |file|
      file.route if file.route.end_with?("raw-html.v1.json")
    end
    assert_equal ["/status.html"], projected_routes
    assert_equal ["/assets/website/raw-html.v1.json"], manifest_routes
    assert_includes page(result, "/zh-CN/").content, 'href="/status.html"'
    refute_includes page(result, "/zh-CN/").content, 'href="/zh-CN/status.html"'
    refute result.pages.any? { |page_output| page_output.route.include?("status") }
  end

  def test_html_routes_cannot_overwrite_localized_pages
    result = compile(
      note("index.md", "---\npublish: true\n---\n# Home"),
      locale_manifest("_locale.yml", "name: English\n"),
      locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
      attachment("slides/index.html", "<!doctype html><title>Slides</title>", media_type: "text/html"),
      theme: "docs",
      i18n: { "locales" => %w[en zh-CN] },
      html: { "slides" => "/zh-CN/" }
    )

    refute result.success?
    diagnostic = result.diagnostics.find { |item| item.code == "route_collision" }
    refute_nil diagnostic
    assert_includes diagnostic.message, "slides/index.html"
    assert_includes diagnostic.message, "index.md"
  end

  def test_html_authorization_does_not_create_a_raw_only_site
    result = compile(
      note("index.md", "---\npublish: false\n---\n# Private"),
      attachment("slides/index.html", "<!doctype html><title>Slides</title>", media_type: "text/html"),
      html: { "slides" => "/slides/" }
    )

    refute result.success?
    assert_includes result.diagnostics.map(&:code), "missing_public_notes"
  end
end
