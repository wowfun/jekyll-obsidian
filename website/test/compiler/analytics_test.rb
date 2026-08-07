# frozen_string_literal: true

require "test_helper"

class AnalyticsTest < Minitest::Test
  HOME = "---\npublish: true\n---\n# Home\n"

  def test_analytics_is_off_when_configuration_is_absent
    result = compile(note("index.md", HOME), theme: "minimal")

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    website = page(result, "/").data.fetch("website")
    refute website.key?("analytics")
    assert_empty website.dig("content_security", "connect_sources")
  end

  def test_cloudflare_projects_a_production_only_provider_and_exact_csp_needs
    result = compile(
      note("index.md", HOME),
      note("about.md", "---\npublish: true\n---\n# About\n"),
      theme: "minimal",
      analytics: { "provider" => "cloudflare", "token" => "abc123-site-token" }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    ["/", "/about/", "/404.html"].each do |route|
      website = page(result, route).data.fetch("website")
      assert_equal(
        { "provider" => "cloudflare", "identifier" => "abc123-site-token", "load" => true },
        website.fetch("analytics")
      )
      assert_equal ["https://static.cloudflareinsights.com"], website.dig("content_security", "script_sources")
      assert_equal ["https://cloudflareinsights.com"], website.dig("content_security", "connect_sources")
    end
  end

  def test_google_is_validated_but_does_not_load_or_expand_csp_in_development
    result = compile(
      note("index.md", HOME),
      theme: "docs",
      environment: "development",
      analytics: { "provider" => "google", "measurement_id" => "G-ABC123XYZ9" }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    website = page(result, "/").data.fetch("website")
    assert_equal(
      { "provider" => "google", "identifier" => "G-ABC123XYZ9", "load" => false },
      website.fetch("analytics")
    )
    assert_empty website.dig("content_security", "script_sources")
    assert_empty website.dig("content_security", "connect_sources")
  end

  def test_analytics_configuration_fails_closed
    cases = [
      [true, "must be a mapping"],
      [{ "provider" => "plausible" }, "provider must be"],
      [{ "provider" => "cloudflare" }, "analytics.token"],
      [{ "provider" => "cloudflare", "token" => 42 }, "analytics.token"],
      [{ "provider" => "cloudflare", "token" => "two tokens" }, "analytics.token"],
      [{ "provider" => "cloudflare", "token" => "token", "measurement_id" => "G-ABC123" }, "unknown analytics setting"],
      [{ "provider" => "google" }, "analytics.measurement_id"],
      [{ "provider" => "google", "measurement_id" => "UA-123" }, "must begin with G-"],
      [{ "provider" => "google", "measurement_id" => "G-ABC123", "token" => "token" }, "unknown analytics setting"]
    ]

    cases.each do |analytics, message|
      result = compile(note("index.md", HOME), analytics: analytics)

      refute result.success?, analytics.inspect
      assert result.diagnostics.any? { |item| item.code == "invalid_analytics" && item.message.include?(message) }, analytics.inspect
    end
  end
end
