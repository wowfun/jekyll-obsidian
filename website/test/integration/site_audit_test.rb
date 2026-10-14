# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "test_helper"

class SiteAuditTest < Minitest::Test
  def test_accepts_a_minimal_allowlisted_site
    Dir.mktmpdir("garden-site-audit") do |site|
      File.write(File.join(site, "index.html"), "<!doctype html><title>Garden</title>")
      File.write(File.join(site, "index.md"), "# Garden\n")

      stdout, stderr, status = audit(site)
      assert status.success?, "#{stdout}\n#{stderr}"
      assert_includes stdout, "site audit: ok"
    end
  end

  def test_accepts_only_current_descriptor_and_generation_scoped_archive_artifact_names
    Dir.mktmpdir("garden-archive-audit") do |site|
      File.write(File.join(site, "index.html"), "<!doctype html><title>Garden</title>")
      directory = File.join(site, "assets", "website", "i18n", "zh-CN", "archive", "a" * 64)
      FileUtils.mkdir_p(directory)
      %w[manifest.json identities.json cards-0.json].each { |name| File.write(File.join(directory, name), "{}") }
      File.write(File.join(File.dirname(directory), "current.json"), "{}")
      primary = File.join(site, "assets", "website", "archive")
      FileUtils.mkdir_p(primary)
      File.write(File.join(primary, "current.json"), "{}")
      _stdout, stderr, status = audit(site)
      assert status.success?, stderr
      File.write(File.join(primary, "credentials.json"), "{}")
      _stdout, stderr, status = audit(site)
      refute status.success?
      assert_includes stderr, "extension allowlist"
      File.delete(File.join(primary, "credentials.json"))
      File.write(File.join(directory, "credentials.json"), "{}")
      _stdout, stderr, status = audit(site)
      refute status.success?
      assert_includes stderr, "extension allowlist"
    end
  end

  def test_rejects_control_characters_in_output_names
    skip "Windows does not allow control characters in filenames" if Gem.win_platform?
    Dir.mktmpdir("garden-site-audit") do |site|
      File.write(File.join(site, "index.html"), "<!doctype html><title>Garden</title>")
      File.write(File.join(site, "unsafe\nname.html"), "secret")

      _stdout, stderr, status = audit(site)
      refute status.success?
      assert_includes stderr, "unsafe output path"
    end
  end

  def test_rejects_files_outside_the_explicit_publication_types
    Dir.mktmpdir("garden-site-audit") do |site|
      File.write(File.join(site, "index.html"), "<!doctype html><title>Garden</title>")
      File.write(File.join(site, "credentials.pem"), "PRIVATE KEY")

      _stdout, stderr, status = audit(site)
      refute status.success?
      assert_includes stderr, "output is not on the extension allowlist"
    end
  end

  def test_rejects_markdown_without_a_published_page_counterpart
    Dir.mktmpdir("garden-site-audit") do |site|
      File.write(File.join(site, "index.html"), "<!doctype html><title>Garden</title>")
      File.write(File.join(site, "private.md"), "# Private\n")

      _stdout, stderr, status = audit(site)
      refute status.success?
      assert_includes stderr, "output is not on the extension allowlist"
    end
  end

  def test_accepts_unknown_extensions_only_when_the_raw_html_manifest_authorizes_them
    Dir.mktmpdir("garden-site-audit") do |site|
      FileUtils.mkdir_p(File.join(site, "assets", "website"))
      FileUtils.mkdir_p(File.join(site, "slides"))
      File.write(File.join(site, "index.html"), "<!doctype html><title>Garden</title>")
      File.write(File.join(site, "slides", "index.html"), "<!doctype html><title>Slides</title>")
      File.write(File.join(site, "slides", "timeline.deck"), "opaque slide data")
      File.write(
        File.join(site, "assets", "website", "raw-html.v1.json"),
        JSON.generate(
          "schema_version" => 1,
          "documents" => [{ "route" => "/slides/", "output" => "/slides/index.html" }],
          "files" => ["/slides/index.html", "/slides/timeline.deck"]
        )
      )

      stdout, stderr, status = audit(site)
      assert status.success?, "#{stdout}\n#{stderr}"
    end
  end

  def test_rejects_a_raw_html_manifest_that_names_a_missing_file
    Dir.mktmpdir("garden-site-audit") do |site|
      FileUtils.mkdir_p(File.join(site, "assets", "website"))
      File.write(File.join(site, "index.html"), "<!doctype html><title>Garden</title>")
      File.write(
        File.join(site, "assets", "website", "raw-html.v1.json"),
        JSON.generate(
          "schema_version" => 1,
          "documents" => [{ "route" => "/slides/", "output" => "/slides/index.html" }],
          "files" => ["/slides/index.html"]
        )
      )

      _stdout, stderr, status = audit(site)
      refute status.success?
      assert_includes stderr, "raw HTML manifest target is missing"
    end
  end

  private

  def audit(site)
    script = File.expand_path("../../scripts/audit-site.rb", __dir__)
    Open3.capture3(RbConfig.ruby, script, site)
  end
end
