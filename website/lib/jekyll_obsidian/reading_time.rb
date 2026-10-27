# frozen_string_literal: true

require "set"

module JekyllObsidian
  module ReadingTime
    CJK_CHARACTERS_PER_MINUTE = 400
    WORDS_PER_MINUTE = 200
    CJK_CHARACTER = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]/u
    WORD = /[\p{L}\p{N}][\p{L}\p{N}\p{M}]*/u
    BLOCK_ELEMENTS = Set.new(%w[
      address article aside blockquote br caption dd details div dl dt fieldset
      figcaption figure footer form h1 h2 h3 h4 h5 h6 header hr li main nav ol p
      pre section summary table tbody td tfoot th thead tr ul
    ]).freeze
    EXCLUDED = [
      "script", "style", "template", "[hidden]", '[aria-hidden="true"]', ".visually-hidden",
      "img", "svg", "canvas", "audio", "video", "iframe", "object", "embed",
      "[data-math-style]", ".math", "math", "[data-website-mermaid]",
      ".website-external-pdf", ".website-external-frame", ".website-tweet",
      ".website-download-card", ".website-transclusion__source",
      ".website-embed--cycle", ".website-embed--limited", ".website-embed--unresolved", "a.anchor",
      "button", "input", "select", "textarea"
    ].join(", ").freeze

    module_function

    # Work on the final body fragment, including expanded notes, without changing
    # the DOM or reparsing Markdown. Inline markup must not split words in code.
    def minutes(fragment)
      excluded = fragment.css(EXCLUDED).to_set
      text = +""
      append_text(fragment, text, excluded)
      characters = text.scan(CJK_CHARACTER).length
      words = text.gsub(CJK_CHARACTER, " ").scan(WORD).length
      # Add exact fractions before rounding so mixed text at exactly two minutes
      # stays hidden. No intermediate rounding or floating-point drift.
      (Rational(characters, CJK_CHARACTERS_PER_MINUTE) + Rational(words, WORDS_PER_MINUTE)).ceil
    end

    def append_text(node, text, excluded)
      return if excluded.include?(node)
      if node.text?
        text << node.text
      elsif node.element? || node.fragment?
        block = BLOCK_ELEMENTS.include?(node.name)
        text << " " if block
        node.children.each { |child| append_text(child, text, excluded) }
        text << " " if block
      end
    end
    private_class_method :append_text
  end
end
