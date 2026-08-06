# frozen_string_literal: true

require "fileutils"
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

  def test_rejects_control_characters_in_output_names
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

  private

  def audit(site)
    script = File.expand_path("../../scripts/audit-site.sh", __dir__)
    Open3.capture3(script, site)
  end
end
