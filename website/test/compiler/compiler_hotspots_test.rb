# frozen_string_literal: true
require "test_helper"

class CompilerHotspotsTest < Minitest::Test
  def test_many_heading_links_use_indexed_association_and_preserve_chain_resolution
    body = "---\npublish: true\n---\n# Home\n\n" + (1..500).map { |i| "## Section #{i}\n\n### Detail\n\n[[index#Section #{i}#Detail]]\n" }.join("\n")
    original = Nokogiri::XML::Node.instance_method(:at_css)
    scans = 0
    Nokogiri::XML::Node.define_method(:at_css) do |*selectors|
      scans += 1 if selectors.any? { |selector| selector.is_a?(String) && selector.match?(/h\d\[data-sourcepos/) }
      original.bind_call(self, *selectors)
    end
    result = compile(note("index.md", body))
    assert result.success?, result.diagnostics.map(&:message).join("\n")
    assert_equal 0, scans, "headings must share one source-position map"
    fragment = Nokogiri::HTML5.fragment(page(result, "/").content)
    assert_equal 1_001, fragment.css("h1[id], h2[id], h3[id]").size
    assert_equal 500, fragment.css("a.website-link").size
    assert_equal "#detail-500", URI(fragment.css("a.website-link").last["href"]).fragment&.prepend("#")
  ensure
    Nokogiri::XML::Node.define_method(:at_css, original) if original
  end
end
