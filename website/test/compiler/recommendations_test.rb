# frozen_string_literal: true
require "test_helper"

class RecommendationsTest < Minitest::Test
  def manifest(items)
    JekyllObsidian::SnapshotEntry.new(path: "_recommendations.json", bytes: JSON.generate(version: 1, items: items), kind: :recommendation_manifest)
  end

  def article(path, extra = "")
    note(path, "---\npublish: true\ncontent_type: post\ntitle: #{path}\ndate: 2026-10-15\n#{extra}---\nAn article.")
  end

  def test_public_localized_cards_expire_without_creating_graph_edges
    future = (Time.now + 3600).utc.iso8601
    %w[minimal docs].each do |theme|
      result = compile(article("a.md"), article("b.md"), note("private.md", "---\npublish: false\n---\nSecret"),
        manifest("a.md" => [
          { path: "b.md", expires_at: future }, { path: "b.md", expires_at: future },
          { path: "a.md", expires_at: future }, { path: "missing.md", expires_at: future },
          { path: "private.md", expires_at: future }
        ], "b.md" => [{ path: "a.md", expires_at: "2000-01-01T00:00:00Z" }]),
        locale_manifest("_locale.yml", "name: English\n"),
        locale_manifest("_translations/zh-CN/_locale.yml", "name: 简体中文\n"),
        note("_translations/zh-CN/b.md", "---\ntitle: 中文标题\n---\n正文"),
        theme: theme, i18n: { "enabled" => true, "locales" => %w[en zh-CN] })
      assert result.success?, result.diagnostics.map(&:message).join("\n")
      cards = page(result, "/zh-CN/a/").data.dig("website", "related_articles")
      assert_equal ["中文标题"], cards.map { |c| c.fetch("title") }
      assert_equal "/zh-CN/b/", cards.first.fetch("url")
      assert_equal future, cards.first.fetch("recommendation_expires_at")
      assert_empty page(result, "/b/").data.dig("website", "related_articles")
      assert_empty result.relations
      refute result.generated_files.any? { |f| f.route.include?("_recommendations") }
    end
  end

  def test_manual_related_wins_and_invalid_manifest_fails
    result = compile(article("a.md", "related: [\"[[b]]\"]\n"), article("b.md"),
      manifest("a.md" => [{ path: "a.md", expires_at: (Time.now + 3600).utc.iso8601 }]))
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    refute page(result, "/a/").data.dig("website", "related_articles").first.key?("recommendation_expires_at")
    bad = compile(article("a.md"), manifest("../a.md" => []))
    refute bad.success?
    assert bad.diagnostics.any? { |d| d.code == "invalid_recommendations" }
  end
end
