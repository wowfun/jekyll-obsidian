# frozen_string_literal: true

require "test_helper"

class PublicationBoundaryTest < Minitest::Test
  def test_only_boolean_publish_true_enters_any_output
    result = compile(
      note("index.md", "---\npublish: true\ntitle: Home\nupdated: 2026-07-30\n---\n# Home\nPublic marker."),
      note("private.md", "Private marker without front matter."),
      note("draft.md", "---\npublish: false\n---\nDraft marker."),
      attachment("secret.txt", "Attachment secret")
    )

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal ["index.md"], result.notes.map(&:id)
    bytes = (result.pages.map(&:content) + result.generated_files.map(&:content)).join("\n")
    assert_includes bytes, "Public marker"
    refute_includes bytes, "Private marker"
    refute_includes bytes, "Draft marker"
    refute_includes bytes, "Attachment secret"
    assert_empty result.copied_assets
  end

  def test_string_publish_is_a_fatal_frontmatter_error
    result = compile(note("index.md", "---\npublish: \"true\"\n---\nNot public."))

    refute result.success?
    diagnostic = result.diagnostics.find { |item| item.code == "invalid_publish" }
    refute_nil diagnostic
    assert_equal :error, diagnostic.severity
  end

  def test_unknown_and_jekyll_control_properties_never_escape
    result = compile(note("index.md", <<~MARKDOWN))
      ---
      publish: true
      title: Safe
      layout: attacker
      render_with_liquid: true
      unknown_private_key: do-not-leak
      updated: 2026-07-30
      ---
      Literal {{ site.secret }}.
    MARKDOWN

    output = page(result, "/")
    assert result.success?
    assert_equal "Safe", output.data.fetch("title")
    refute output.data.key?("unknown_private_key")
    refute output.data.key?("render_with_liquid")
    refute_includes JSON.generate(output.data), "do-not-leak"
    assert_includes output.content, "{{ site.secret }}"
  end

  def test_input_and_result_are_deeply_frozen_and_repeatable
    entries = [
      note(
        "index.md",
        "---\npublish: true\ntags: [stable]\nupdated: 2026-07-30\n---\n# Same\n[[other]]\n[[missing]]\n![[media/pixel.png]]"
      ),
      note("other.md", "---\npublish: true\nupdated: 2026-07-29\n---\n# Other"),
      attachment("media/pixel.png", "pixel", media_type: "image/png")
    ]
    first = compile(*entries)
    second = compile(*entries)

    assert first.success?, first.diagnostics.map(&:message).join("\n")
    assert_equal Marshal.dump(first), Marshal.dump(second)
    entries.each.with_index { |entry, index| assert_deeply_frozen(entry, "entry[#{index}]") }
    assert_deeply_frozen(first, "result")
    refute_empty first.pages
    refute_empty first.generated_files
    refute_empty first.copied_assets
    refute_empty first.diagnostics
    refute_empty first.relations
    refute_empty first.notes
    assert_raises(FrozenError) { first.pages << :mutation }
    assert_raises(FrozenError) { first.pages.first.content << "mutation" }
    assert_raises(FrozenError) { first.pages.first.data["website"] = {} }
    assert_raises(FrozenError) { first.notes.first.properties["tags"] << "mutation" }
  end

  def test_snapshot_paths_use_full_unicode_case_folding_for_collisions
    result = compile(
      note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home"),
      attachment("media/Straße.png", "one", media_type: "image/png"),
      attachment("media/STRASSE.png", "two", media_type: "image/png")
    )

    refute result.success?
    assert result.diagnostics.any? { |item| item.code == "path_collision" }
  end

  private

  def assert_deeply_frozen(value, label, seen = {})
    return if seen[value.object_id]

    seen[value.object_id] = true
    assert value.frozen?, "expected #{label} (#{value.class}) to be frozen"
    case value
    when Array
      value.each.with_index { |item, index| assert_deeply_frozen(item, "#{label}[#{index}]", seen) }
    when Hash
      value.each do |key, item|
        assert_deeply_frozen(key, "#{label} key", seen)
        assert_deeply_frozen(item, "#{label}[#{key.inspect}]", seen)
      end
    when Struct
      value.each_pair { |name, item| assert_deeply_frozen(item, "#{label}.#{name}", seen) }
    end
  end
end
