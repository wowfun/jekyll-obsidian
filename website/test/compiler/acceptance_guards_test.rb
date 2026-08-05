# frozen_string_literal: true

require "test_helper"

class AcceptanceGuardsTest < Minitest::Test
  SMALL_VAULT_SIZE = 72
  LARGE_VAULT_SIZE = SMALL_VAULT_SIZE * 2
  COMMONMARKER_PROBE_LOCK = Mutex.new

  def test_commonmarker_parses_each_public_note_once_and_never_parses_private_notes
    result = nil
    parsed_markdown = with_commonmarker_parse_probe do |calls|
      result = compile(
        note("index.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Home\nPUBLIC_HOME_SENTINEL"),
        note("public.md", "---\npublish: true\nupdated: 2026-07-30\n---\n# Public\nPUBLIC_NOTE_SENTINEL"),
        note("private.md", "# Private\nPRIVATE_NO_FRONTMATTER_SENTINEL"),
        note("draft.md", "---\npublish: false\n---\n# Draft\nPRIVATE_DRAFT_SENTINEL")
      )
      calls
    end

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal 2, parsed_markdown.length
    assert_equal 1, parsed_markdown.count { |markdown| markdown.include?("PUBLIC_HOME_SENTINEL") }
    assert_equal 1, parsed_markdown.count { |markdown| markdown.include?("PUBLIC_NOTE_SENTINEL") }
    refute parsed_markdown.any? { |markdown| markdown.include?("PRIVATE_NO_FRONTMATTER_SENTINEL") }
    refute parsed_markdown.any? { |markdown| markdown.include?("PRIVATE_DRAFT_SENTINEL") }
  end

  def test_synthetic_vault_relation_pipeline_grows_near_linearly
    small_profile = profile_synthetic_vault(SMALL_VAULT_SIZE)
    large_profile = profile_synthetic_vault(LARGE_VAULT_SIZE)

    assert_equal SMALL_VAULT_SIZE, small_profile.fetch(:parse_count)
    assert_equal LARGE_VAULT_SIZE, large_profile.fetch(:parse_count)
    assert_equal SMALL_VAULT_SIZE - 1, small_profile.fetch(:relation_count)
    assert_equal LARGE_VAULT_SIZE - 1, large_profile.fetch(:relation_count)
    assert_equal SMALL_VAULT_SIZE - 1, small_profile.fetch(:graph_edge_count)
    assert_equal LARGE_VAULT_SIZE - 1, large_profile.fetch(:graph_edge_count)
    assert_equal SMALL_VAULT_SIZE, small_profile.fetch(:note_count)
    assert_equal LARGE_VAULT_SIZE, large_profile.fetch(:note_count)

    # Pages, indexes, relation rails and graph JSON may add fixed overhead, but
    # doubling a one-link-per-note vault must not produce quadratic output.
    assert_operator large_profile.fetch(:payload_bytes), :>, small_profile.fetch(:payload_bytes)
    assert_operator large_profile.fetch(:payload_bytes), :<=, small_profile.fetch(:payload_bytes) * 3

    # Timing is deliberately only a secondary guard. Deterministic parse,
    # relation, graph and byte counts above are the primary complexity signal.
    small_seconds = small_profile.fetch(:seconds)
    large_seconds = large_profile.fetch(:seconds)
    assert_operator large_seconds, :<=, (small_seconds * 5.0) + 0.25,
      "doubling the synthetic vault took #{large_seconds.round(3)}s after #{small_seconds.round(3)}s"
  end

  private

  def profile_synthetic_vault(size)
    entries = synthetic_chain(size)
    compile(*entries, theme: "minimal") # Warm Commonmarker and Ruby before taking the sample.

    result = nil
    elapsed = nil
    parsed_markdown = with_commonmarker_parse_probe do |calls|
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = compile(*entries, theme: "minimal")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      calls
    end

    assert result.success?, result.diagnostics.map(&:message).join("\n")
    graph = generated_json(result, "/assets/website/graph.v1.json")
    {
      parse_count: parsed_markdown.length,
      relation_count: result.relations.length,
      graph_edge_count: graph.fetch("edges").length,
      note_count: result.notes.length,
      payload_bytes: result.pages.sum { |output| output.content.bytesize } +
        result.generated_files.sum { |output| output.content.bytesize },
      seconds: elapsed
    }
  end

  def synthetic_chain(size)
    Array.new(size) do |index|
      path = index.zero? ? "index.md" : format("notes/note-%04d.md", index)
      target = if index + 1 < size
        index.zero? ? "notes/note-0001" : format("note-%04d", index + 1)
      end
      link = target ? "\n[[#{target}]]" : ""
      note(path, "---\npublish: true\nupdated: 2026-07-30\n---\n# Note #{index}#{link}\n")
    end
  end

  def with_commonmarker_parse_probe
    COMMONMARKER_PROBE_LOCK.synchronize do
      singleton_class = Commonmarker.singleton_class
      original_parse = Commonmarker.method(:parse)
      calls = []
      singleton_class.send(:remove_method, :parse)
      singleton_class.send(:define_method, :parse) do |*arguments, **keywords, &block|
        calls << arguments.fetch(0).dup
        original_parse.call(*arguments, **keywords, &block)
      end
      yield calls
    ensure
      singleton_class.send(:remove_method, :parse) if singleton_class&.instance_methods(false)&.include?(:parse)
      singleton_class.send(:define_method, :parse, original_parse) if singleton_class && original_parse
    end
  end
end
