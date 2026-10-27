# frozen_string_literal: true

module JekyllObsidian
  module MarkdownOptions
    LOCAL = DeepFreeze.call(
      parse: {
        smart: false,
        relaxed_tasklist_matching: true,
        relaxed_autolinks: true,
        sourcepos_chars: true
      },
      render: {
        unsafe: true,
        hardbreaks: true,
        tasklist_classes: true,
        escaped_char_spans: true,
        sourcepos: true
      },
      extension: {
        strikethrough: true,
        table: true,
        autolink: true,
        tasklist: true,
        footnotes: true,
        math_dollars: true,
        math_code: true,
        math_latex: true,
        wikilinks_title_after_pipe: true,
        highlight: true,
        cjk_friendly_emphasis: true
      }
    )

    # Export splices require byte columns while retaining the authored grammar.
    SOURCE_BYTES = DeepFreeze.call(LOCAL.merge(parse: LOCAL.fetch(:parse).merge(sourcepos_chars: false)))
  end
end
