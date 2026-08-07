# frozen_string_literal: true

require_relative "test_helper"
require "jekyll_obsidian/adapter"

class DocumentationCoverageTest < Minitest::Test
  DOCS_ROOT = File.expand_path("../docs", __dir__)
  USER_GUIDES = [
    "Getting Started",
    "Integration",
    "Syntax",
    "Customization",
    "Portfolio",
    "Analytics",
    "Comments",
    "Localization",
    "Deployment"
  ].freeze

  CONFIG_DOCUMENTATION = {
    "source" => ["Customization.md", "Site identity", "`website.source`"],
    "syntax_profile" => ["Customization.md", "Site identity", "`website.syntax_profile`"],
    "theme" => ["Customization.md", "Site themes", "`website.theme`"],
    "repository" => ["Customization.md", "Site identity", "`website.repository`"],
    "edit_branch" => ["Customization.md", "Site identity", "`website.edit_branch`"],
    "content" => ["Customization.md", "Publication defaults", "`website.content.publish_by_default`"],
    "features" => ["Customization.md", "Site themes", "`website.features`"],
    "i18n" => ["Localization.md", "Enable localization", "`website.i18n`"],
    "comments" => ["Comments.md", "Configure the site", "`website.comments`"],
    "contacts" => ["Customization.md", "Site identity", "`website.contacts`"],
    "navigation" => ["Customization.md", "Minimal navigation", "`website.navigation`"],
    "analytics" => ["Analytics.md", "Configuration and security", "`website.analytics`"]
  }.freeze

  def test_every_user_guide_has_a_simplified_chinese_source
    USER_GUIDES.each do |name|
      english = File.join(DOCS_ROOT, "docs", "#{name}.md")
      chinese = File.join(DOCS_ROOT, "_translations", "zh-CN", "docs", "#{name}.md")

      assert_path_exists english, "missing English user guide #{name}"
      assert_path_exists chinese, "missing Simplified Chinese user guide #{name}"
      assert_includes File.read(english), "publish: true"
      assert_includes File.read(chinese), "publish: true"
    end
  end

  def test_every_user_guide_is_linked_from_both_documentation_indexes
    english = [
      File.read(File.join(DOCS_ROOT, "index.md")),
      File.read(File.join(DOCS_ROOT, "docs", "index.md"))
    ].join("\n")
    chinese = [
      File.read(File.join(DOCS_ROOT, "_translations", "zh-CN", "index.md")),
      File.read(File.join(DOCS_ROOT, "_translations", "zh-CN", "docs", "index.md"))
    ].join("\n")

    USER_GUIDES.each do |name|
      assert_includes english, "[[#{name}", "#{name} is missing from the English documentation indexes"
      assert_includes chinese, "[[#{name}", "#{name} is missing from the Chinese documentation indexes"
    end
  end

  def test_every_supported_website_key_has_one_canonical_guide
    JekyllObsidian::Adapter::CONFIG_KEYS.each do |key|
      relative_path, heading, marker = CONFIG_DOCUMENTATION.fetch(key)
      document = File.read(File.join(DOCS_ROOT, "docs", relative_path))

      assert_includes document, "## #{heading}", "#{key} points at a missing canonical heading in #{relative_path}"
      assert_includes document, marker, "#{key} is missing from #{relative_path}"
    end
  end

  def test_every_supported_page_property_is_in_the_property_reference
    document = File.read(File.join(DOCS_ROOT, "docs", "Customization.md"))
    canonical_heading = "## Page properties"
    assert_includes document, canonical_heading

    JekyllObsidian::FrontMatter::SUPPORTED.each do |property|
      assert_includes document, "`#{property}`", "missing page property #{property}"
    end
  end

  def test_every_feature_key_is_in_the_theme_reference
    document = File.read(File.join(DOCS_ROOT, "docs", "Customization.md"))
    canonical_heading = "## Site themes"
    assert_includes document, canonical_heading

    JekyllObsidian::VaultCompiler::FEATURE_KEYS.each do |feature|
      assert_includes document, "`#{feature}`", "missing feature key #{feature}"
    end
  end
end
