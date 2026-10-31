# frozen_string_literal: true
require "test_helper"

class GraphBudgetsTest < Minitest::Test
  def test_high_degree_hubs_publish_bounded_local_graphs_and_a_global_summary
    children = (1..1_000).map { |i| note("n#{i}.md", "---\npublish: true\n---\n# #{'Long label ' * 40}#{i}\n\n[[index]]") }
    result = compile(note("index.md", "---\npublish: true\n---\n# Hub"), *children)
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    local = page(result, "/").data.dig("website", "local_graph")
    assert_operator local.fetch("nodes").size, :<=, 32
    assert_operator local.fetch("edges").size, :<=, 64
    assert_operator JSON.generate(local).bytesize, :<=, 65_536
    assert_equal true, local.fetch("truncated")
    assert_equal 1_001, local.fetch("total_nodes")
    assert_equal (["index.md"] + (1..1_000).map { |i| "n#{i}.md" }.sort.first(31)).sort, local.fetch("nodes").map { |node| node.fetch("id") }
    graph = generated_json(result, "/assets/website/graph.v1.json")
    assert_equal true, graph.fetch("truncated")
    assert_equal 1_001, graph.fetch("total_nodes")
    assert_empty graph.fetch("nodes")
    assert_empty graph.fetch("edges")
    assert_operator JSON.generate(graph).bytesize, :<, 256
  end
end
