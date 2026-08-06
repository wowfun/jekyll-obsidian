# frozen_string_literal: true

require "test_helper"

class ContentPolicyTest < Minitest::Test
  def test_default_policy_requires_an_explicit_opt_in
    resolution = JekyllObsidian::ContentPolicy.resolve(nil)

    assert_empty resolution.diagnostics
    refute resolution.policy.publish?("index.md", {})
    assert resolution.policy.publish?("index.md", "publish" => true)
    refute resolution.policy.publish?("index.md", "publish" => false)
  end

  def test_configured_directories_publish_recursively_with_explicit_overrides
    resolution = JekyllObsidian::ContentPolicy.resolve(
      "publish_by_default" => ["notes"]
    )
    policy = resolution.policy

    assert_empty resolution.diagnostics
    assert policy.publish?("notes/start.md", {})
    assert policy.publish?("notes/guides/deep.md", {})
    refute policy.publish?("notes.md", {})
    refute policy.publish?("notes-archive/old.md", {})
    refute policy.publish?("drafts/private.md", {})
    refute policy.publish?("notes/draft.md", "publish" => false)
    assert policy.publish?("drafts/exception.md", "publish" => true)
  end

  def test_dot_publishes_the_complete_content_tree_by_default
    resolution = JekyllObsidian::ContentPolicy.resolve(
      "publish_by_default" => ["."]
    )

    assert_empty resolution.diagnostics
    assert resolution.policy.publish?("index.md", {})
    assert resolution.policy.publish?("blog/deep/note.md", {})
    refute resolution.policy.publish?("draft.md", "publish" => false)
  end

  def test_content_classification_uses_the_same_normalized_configuration
    resolution = JekyllObsidian::ContentPolicy.resolve(
      "default_type" => "page",
      "directories" => { "post" => ["journal"], "doc" => ["manual"] }
    )
    policy = resolution.policy

    assert_equal "page", policy.classify("index.md", "content_type" => "post")
    assert_equal "post", policy.classify("journal/entry.md", {})
    assert_equal "doc", policy.classify("manual/guides/start.md", {})
    assert_equal "page", policy.classify("about.md", {})
    assert_equal "doc", policy.classify("journal/reference.md", "content_type" => "doc")
  end

  def test_invalid_publication_directories_fail_closed
    wrong_type = JekyllObsidian::ContentPolicy.resolve("publish_by_default" => ".")
    missing_value = JekyllObsidian::ContentPolicy.resolve("publish_by_default" => nil)
    traversal = JekyllObsidian::ContentPolicy.resolve("publish_by_default" => ["../notes", "/absolute"])
    unknown = JekyllObsidian::ContentPolicy.resolve("publish_everything" => true)

    assert wrong_type.diagnostics.any? { |item| item.code == "invalid_publish_by_default" }
    assert missing_value.diagnostics.any? { |item| item.code == "invalid_publish_by_default" }
    assert_equal 2, traversal.diagnostics.count { |item| item.code == "invalid_content_directory" }
    assert unknown.diagnostics.any? { |item| item.code == "invalid_content_config" }
    refute wrong_type.policy.publish?("index.md", {})
    refute traversal.policy.publish?("notes/start.md", {})
  end

  def test_compiler_applies_directory_defaults_without_widening_the_asset_closure
    result = compile(
      note("index.md", "# Home\n![[assets/public.png]]"),
      note("draft.md", "---\npublish: false\n---\n# Draft\n![[assets/private.png]]"),
      attachment("assets/public.png", "public", media_type: "image/png"),
      attachment("assets/private.png", "private", media_type: "image/png"),
      content: { "publish_by_default" => ["."] }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal ["index.md"], result.notes.map(&:id)
    assert_equal ["assets/public.png"], result.copied_assets.map(&:source_path)
    refute result.pages.any? { |output| output.route == "/draft/" }
    refute result.generated_files.any? { |output| output.route == "/draft.md" }
    refute generated_json(result, "/assets/website/search.v1.json").to_s.include?("Draft")
    refute generated_json(result, "/assets/website/graph.v1.json").to_s.include?("draft.md")
    refute result.generated_files.find { |output| output.route == "/sitemap.xml" }.content.include?("/draft/")
  end

  def test_default_published_pages_can_use_navigation_frontmatter
    result = compile(
      note("index.md", "# Home"),
      note("about.md", "---\nnavigation:\n  label: About\n---\n# About"),
      content: { "publish_by_default" => ["."] }
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert page(result, "/about/")
    refute result.diagnostics.any? { |item| item.code == "unpublished_page_navigation" }
  end

  def test_invalid_publish_values_still_fail_a_default_published_build
    result = compile(
      note("index.md", "---\npublish: \"false\"\n---\n# Home"),
      content: { "publish_by_default" => ["."] }
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "invalid_publish" }
  end
end
