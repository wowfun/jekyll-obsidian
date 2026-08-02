# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "test_helper"

class SiteUrlVerifierTest < Minitest::Test
  def test_root_site_accepts_valid_csp_canonical_and_xml_urls
    Dir.mktmpdir("obsidian-url-verifier") do |site|
      FileUtils.mkdir_p(File.join(site, "assets", "obsidian"))
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self' https:; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self'">
        <link rel="canonical" href="https://example.test/">
        <meta property="og:url" content="https://example.test/">
        <meta name="obsidian:catalog" content="/assets/obsidian/catalog.v1.json">
        </head><body><a href="/">Home</a><a id="section" href="#section">Section</a></body></html>
      HTML
      File.write(File.join(site, "assets", "obsidian", "catalog.v1.json"), '{"schema_version":1,"notes":[]}')
      File.write(File.join(site, "assets", "obsidian", "graph.v1.json"), '{"schema_version":1,"nodes":[],"edges":[]}')
      File.write(File.join(site, "assets", "obsidian", "search.v1.json"), '{"schema_version":1,"documents":[]}')
      File.write(File.join(site, "sitemap.xml"), <<~XML)
        <?xml version="1.0"?><urlset><url><loc>https://example.test/</loc></url></urlset>
      XML

      ruby = File.join(Gem.ruby)
      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
      stdout, stderr, status = Open3.capture3(ruby, script, site, "https://example.test", "")
      assert status.success?, "#{stdout}\n#{stderr}"
      assert_includes stdout, "site URL verification: ok"
    end
  end

  def test_rejects_incomplete_csp_mismatched_og_and_missing_srcset_target
    Dir.mktmpdir("obsidian-url-verifier") do |site|
      FileUtils.mkdir_p(File.join(site, "assets", "obsidian"))
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self';">
        <link rel="canonical" href="https://example.test/">
        <meta property="og:url" content="https://example.test/wrong/">
        </head><body><img alt="missing" srcset="/missing-small.png 1x, /missing-large.png 2x"></body></html>
      HTML
      File.write(File.join(site, "assets", "obsidian", "catalog.v1.json"), '{"schema_version":1,"notes":[]}')
      File.write(File.join(site, "assets", "obsidian", "graph.v1.json"), '{"schema_version":1,"nodes":[],"edges":[]}')
      File.write(File.join(site, "assets", "obsidian", "search.v1.json"), '{"schema_version":1,"documents":[]}')

      ruby = File.join(Gem.ruby)
      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
      _stdout, stderr, status = Open3.capture3(ruby, script, site, "https://example.test", "")
      refute status.success?
      assert_includes stderr, "CSP directive style-src"
      assert_includes stderr, "og:url"
      assert_includes stderr, "missing-small.png"
    end
  end

  def test_accepts_media_fragments_and_resolves_root_relative_css_from_site_root
    Dir.mktmpdir("obsidian-url-verifier") do |site|
      FileUtils.mkdir_p(File.join(site, "assets", "obsidian"))
      File.binwrite(File.join(site, "paper.pdf"), "%PDF")
      File.write(File.join(site, "assets", "font.woff2"), "font")
      File.write(File.join(site, "assets", "site.css"), "a{background:url('/project/assets/font.woff2')} b{fill:url(#paint)}")
      File.write(File.join(site, "assets", "obsidian", "catalog.v1.json"), '{"schema_version":1,"notes":[]}')
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self' https:; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self'">
        <link rel="canonical" href="https://example.test/project/">
        <meta property="og:url" content="https://example.test/project/">
        <link rel="stylesheet" href="/project/assets/site.css">
        </head><body><object data="/project/paper.pdf#page=3"></object></body></html>
      HTML

      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "/project")
      assert status.success?, stderr
    end
  end
end
