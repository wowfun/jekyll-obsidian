# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "test_helper"

class SiteUrlVerifierTest < Minitest::Test
  def test_root_site_accepts_valid_csp_canonical_and_xml_urls
    Dir.mktmpdir("obsidian-url-verifier") do |site|
      FileUtils.mkdir_p(File.join(site, "assets", "website"))
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self'">
        <link rel="canonical" href="https://example.test/">
        <meta property="og:url" content="https://example.test/">
        <meta name="website:catalog" content="/assets/website/catalog.v1.json">
        </head><body><a href="/">Home</a><a id="section" href="#section">Section</a></body></html>
      HTML
      File.write(File.join(site, "assets", "website", "catalog.v1.json"), '{"schema_version":1,"notes":[]}')
      File.write(File.join(site, "assets", "website", "graph.v1.json"), '{"schema_version":1,"nodes":[],"edges":[]}')
      File.write(File.join(site, "assets", "website", "search.v1.json"), '{"schema_version":1,"documents":[]}')
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
      FileUtils.mkdir_p(File.join(site, "assets", "website"))
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self';">
        <link rel="canonical" href="https://example.test/">
        <meta property="og:url" content="https://example.test/wrong/">
        </head><body><img alt="missing" srcset="/missing-small.png 1x, /missing-large.png 2x"></body></html>
      HTML
      File.write(File.join(site, "assets", "website", "catalog.v1.json"), '{"schema_version":1,"notes":[]}')
      File.write(File.join(site, "assets", "website", "graph.v1.json"), '{"schema_version":1,"nodes":[],"edges":[]}')
      File.write(File.join(site, "assets", "website", "search.v1.json"), '{"schema_version":1,"documents":[]}')

      ruby = File.join(Gem.ruby)
      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
      _stdout, stderr, status = Open3.capture3(ruby, script, site, "https://example.test", "")
      refute status.success?
      assert_includes stderr, "CSP directive style-src"
      assert_includes stderr, "og:url"
      assert_includes stderr, "missing-small.png"
    end
  end

  def test_rejects_http_images_that_the_production_csp_would_block
    Dir.mktmpdir("website-http-image-verifier") do |site|
      FileUtils.mkdir_p(File.join(site, "assets", "website"))
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self'">
        <link rel="canonical" href="http://example.test/">
        <meta property="og:url" content="http://example.test/">
        </head><body>
        <img alt="same origin" src="http://example.test/image.png">
        <img alt="blocked" src="http://assets.example.test/image.png">
        </body></html>
      HTML
      File.write(File.join(site, "assets", "website", "catalog.v1.json"), '{"schema_version":1,"notes":[]}')
      File.write(File.join(site, "assets", "website", "graph.v1.json"), '{"schema_version":1,"nodes":[],"edges":[]}')
      File.write(File.join(site, "assets", "website", "search.v1.json"), '{"schema_version":1,"documents":[]}')

      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "http://example.test", "")

      refute status.success?
      assert_includes stderr, "image URL must use HTTPS"
      assert_includes stderr, "http://assets.example.test/image.png"
      refute_includes stderr, "http://example.test/image.png"
    end
  end

  def test_accepts_media_fragments_and_resolves_root_relative_css_from_site_root
    Dir.mktmpdir("obsidian-url-verifier") do |site|
      FileUtils.mkdir_p(File.join(site, "assets", "website"))
      File.binwrite(File.join(site, "paper.pdf"), "%PDF")
      File.write(File.join(site, "assets", "font.woff2"), "font")
      File.write(File.join(site, "assets", "site.css"), "a{background:url('/project/assets/font.woff2')} b{fill:url(#paint)}")
      File.write(File.join(site, "assets", "website", "catalog.v1.json"), '{"schema_version":1,"notes":[]}')
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self'">
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

  def test_accepts_the_exact_comments_csp_profile
    Dir.mktmpdir("website-comments-url-verifier") do |site|
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self' https://giscus.app; style-src 'self' 'unsafe-inline' https://giscus.app; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self' https://giscus.app">
        <link rel="canonical" href="https://example.test/">
        <meta property="og:url" content="https://example.test/">
        <meta name="giscus:backlink" content="https://example.test/">
        </head><body>
        <section data-website-comments-load><a href="https://github.com/example/community/discussions">GitHub Discussions</a></section>
        </body></html>
      HTML

      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      assert status.success?, stderr
    end
  end

  def test_accepts_each_analytics_provider_with_its_exact_csp_profile
    cases = {
      "cloudflare" => {
        identifier: "site-token",
        script: "https://static.cloudflareinsights.com",
        connect: "https://cloudflareinsights.com"
      },
      "google" => {
        identifier: "G-ABC123",
        script: "https://www.googletagmanager.com",
        connect: "https://*.analytics.google.com https://*.google-analytics.com https://www.googletagmanager.com"
      }
    }
    cases.each do |provider, values|
      Dir.mktmpdir("website-#{provider}-analytics-verifier") do |site|
        File.write(File.join(site, "index.html"), <<~HTML)
          <!doctype html><html><head>
          <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self' #{values.fetch(:script)}; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self' #{values.fetch(:connect)}; frame-src 'self'">
          <link rel="canonical" href="https://example.test/">
          <meta property="og:url" content="https://example.test/">
          <meta name="website:analytics" data-provider="#{provider}" content="#{values.fetch(:identifier)}">
          </head><body>Home</body></html>
        HTML

        script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
        _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
        assert status.success?, "#{provider}: #{stderr}"
      end
    end
  end

  def test_rejects_analytics_identifier_as_a_url_and_permissions_without_matching_meta
    cases = {
      "analytics-id-treated-as-url" => <<~HTML,
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self' https://static.cloudflareinsights.com; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self' https://cloudflareinsights.com; frame-src 'self'">
        <link rel="canonical" href="https://example.test/"><meta property="og:url" content="https://example.test/">
        <meta name="website:analytics" data-provider="cloudflare" content="site-token">
        </head><body></body></html>
      HTML
      "permissions-without-meta" => <<~HTML
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self' https://static.cloudflareinsights.com; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self' https://cloudflareinsights.com; frame-src 'self'">
        <link rel="canonical" href="https://example.test/"><meta property="og:url" content="https://example.test/">
        </head><body></body></html>
      HTML
    }

    Dir.mktmpdir("website-valid-analytics-meta") do |site|
      File.write(File.join(site, "index.html"), cases.fetch("analytics-id-treated-as-url"))
      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      assert status.success?, stderr
    end

    Dir.mktmpdir("website-unscoped-analytics-csp") do |site|
      File.write(File.join(site, "index.html"), cases.fetch("permissions-without-meta"))
      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      refute status.success?
      assert_includes stderr, "CSP directive script-src"
    end
  end

  def test_rejects_comments_permissions_without_a_hook_and_hook_without_permissions
    cases = {
      "permission-only" => <<~HTML,
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self' https://giscus.app; style-src 'self' 'unsafe-inline' https://giscus.app; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self' https://giscus.app">
        <link rel="canonical" href="https://example.test/"><meta property="og:url" content="https://example.test/">
        </head><body></body></html>
      HTML
      "hook-only" => <<~HTML
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self'">
        <link rel="canonical" href="https://example.test/"><meta property="og:url" content="https://example.test/">
        </head><body><section data-website-comments-load></section></body></html>
      HTML
    }
    cases.each do |label, html|
      Dir.mktmpdir("website-comments-#{label}") do |site|
        File.write(File.join(site, "index.html"), html)
        script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
        _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
        refute status.success?, label
        assert_includes stderr, "CSP directive script-src", label
      end
    end
  end

  def test_rejects_arbitrary_external_script_on_a_comments_page
    Dir.mktmpdir("website-comments-external-script") do |site|
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self' https://giscus.app; style-src 'self' 'unsafe-inline' https://giscus.app; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self' https://giscus.app">
        <link rel="canonical" href="https://example.test/"><meta property="og:url" content="https://example.test/">
        <meta name="giscus:backlink" content="https://example.test/">
        <script src="https://analytics.example/client.js"></script>
        </head><body><section data-website-comments-load></section></body></html>
      HTML

      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      refute status.success?
      assert_includes stderr, "external script source is not allowed"
    end
  end

  def test_noindex_pages_require_a_canonical_to_an_existing_indexable_page
    Dir.mktmpdir("website-noindex-canonical") do |site|
      FileUtils.mkdir_p(File.join(site, "zh-CN"))
      csp = "default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self'"
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="#{csp}">
        <link rel="canonical" href="https://example.test/">
        <meta property="og:url" content="https://example.test/">
        </head><body>Default</body></html>
      HTML
      fallback_path = File.join(site, "zh-CN", "index.html")
      fallback = lambda do |canonical|
        canonical_link = canonical ? %(<link rel="canonical" href="#{canonical}">) : ""
        File.write(fallback_path, <<~HTML)
          <!doctype html><html><head>
          <meta http-equiv="Content-Security-Policy" content="#{csp}">
          #{canonical_link}
          <meta property="og:url" content="https://example.test/zh-CN/">
          <meta name="robots" content="noindex">
          </head><body>Fallback</body></html>
        HTML
      end
      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)

      fallback.call("https://example.test/")
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      assert status.success?, stderr

      fallback.call(nil)
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      refute status.success?
      assert_includes stderr, "canonical"

      fallback.call("https://example.test/missing/")
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      refute status.success?
      assert_includes stderr, "canonical target does not exist"

      fallback.call("https://example.test/zh-CN/")
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      refute status.success?
      assert_includes stderr, "canonical target must be indexable"
    end
  end

  def test_accepts_exact_page_scoped_video_and_player_permissions
    Dir.mktmpdir("website-external-media-verifier") do |site|
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self' https://cdn.example; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self' https://www.youtube-nocookie.com">
        <link rel="canonical" href="https://example.test/">
        <meta property="og:url" content="https://example.test/">
        </head><body>
        <video controls preload="metadata"><source src="https://cdn.example/demo.mp4?token=signed" type="video/mp4"></video>
        <iframe class="website-external-player website-external-player--youtube" data-website-external-player="youtube" src="https://www.youtube-nocookie.com/embed/NnTvZWp5Q7o" title="Demo" loading="lazy" referrerpolicy="strict-origin-when-cross-origin" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>
        </body></html>
      HTML

      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      assert status.success?, stderr
    end
  end

  def test_rejects_unscoped_or_noncanonical_external_players
    cases = {
      "wide-csp" => [
        "frame-src 'self' https:",
        '<iframe src="https://video.example/embed/1" title="Video"></iframe>'
      ],
      "missing-contract" => [
        "frame-src 'self' https://www.youtube-nocookie.com",
        '<iframe src="https://www.youtube-nocookie.com/embed/NnTvZWp5Q7o" title="Video"></iframe>'
      ]
    }
    cases.each do |label, (frame_src, frame)|
      Dir.mktmpdir("website-external-player-#{label}") do |site|
        File.write(File.join(site, "index.html"), <<~HTML)
          <!doctype html><html><head>
          <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; #{frame_src}">
          <link rel="canonical" href="https://example.test/"><meta property="og:url" content="https://example.test/">
          </head><body>#{frame}</body></html>
        HTML
        script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
        _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
        refute status.success?, label
        assert_includes stderr, "external iframe", label
      end
    end
  end

  def test_generated_markdown_links_must_resolve_to_real_files
    Dir.mktmpdir("website-markdown-resource-verifier") do |site|
      File.write(File.join(site, "index.md"), "# Home\n")
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self'">
        <link rel="canonical" href="https://example.test/">
        <meta property="og:url" content="https://example.test/">
        </head><body><a href="/index.md" target="_blank" rel="noopener">View as Markdown</a></body></html>
      HTML
      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)

      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      assert status.success?, stderr

      FileUtils.rm(File.join(site, "index.md"))
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      refute status.success?
      assert_includes stderr, "index.md"
    end
  end


  def test_accepts_sandboxed_web_frames_and_lazy_tweets_with_exact_permissions
    Dir.mktmpdir("website-web-tweet-verifier") do |site|
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self' https://platform.twitter.com; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self' https://frame.example https://platform.twitter.com">
        <link rel="canonical" href="https://example.test/">
        <meta property="og:url" content="https://example.test/">
        </head><body>
        <figure class="website-external-frame">
          <iframe class="website-external-frame__viewport" data-website-external-frame="web" src="https://frame.example/embed#section" title="Example" loading="lazy" referrerpolicy="strict-origin-when-cross-origin" sandbox="#{JekyllObsidian::ExternalMedia::IFRAME_SANDBOX}" allowfullscreen height="480"></iframe>
          <a class="website-external-frame__fallback" href="https://frame.example/embed#section" target="_blank" rel="noopener noreferrer">Open embedded page</a>
        </figure>
        <figure class="website-tweet" data-website-tweet="1580548874246443010">
          <div data-website-tweet-mount></div>
          <a data-website-tweet-fallback href="https://x.com/obsdmd/status/1580548874246443010">View post on X</a>
        </figure>
        </body></html>
      HTML

      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      assert status.success?, stderr
    end
  end

  def test_rejects_tweet_permissions_without_a_compiler_marker
    Dir.mktmpdir("website-invalid-tweet-verifier") do |site|
      File.write(File.join(site, "index.html"), <<~HTML)
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; base-uri 'self'; form-action 'self'; script-src 'self' https://platform.twitter.com; style-src 'self' 'unsafe-inline'; img-src 'self' https:; media-src 'self'; object-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'self' https://platform.twitter.com">
        <link rel="canonical" href="https://example.test/"><meta property="og:url" content="https://example.test/">
        </head><body><p>No Tweet here.</p></body></html>
      HTML

      script = File.expand_path("../../scripts/verify-site-urls.rb", __dir__)
      _stdout, stderr, status = Open3.capture3(Gem.ruby, script, site, "https://example.test", "")
      refute status.success?
      assert_includes stderr, "script-src"
      assert_includes stderr, "frame-src"
    end
  end
end
