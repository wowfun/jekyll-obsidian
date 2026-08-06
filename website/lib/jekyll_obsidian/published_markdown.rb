# frozen_string_literal: true

module JekyllObsidian
  # Owns the one plain-Markdown representation shared by generated resources
  # and the page actions that copy them. Callers only provide authored source
  # facts; route and byte normalization stay behind this interface.
  module PublishedMarkdown
    ESCAPABLE_PUNCTUATION = /([!"#$%&'()*+,\-.\/:;<=>?@\[\\\]^_`{|}~])/
    TRAILING_NEWLINES = /(?:\r\n|\n|\r)+\z/
    module_function

    def content(title:, body:, has_h1:)
      authored = body.to_s.sub(TRAILING_NEWLINES, "")
      return "#{authored}\n" if has_h1

      heading = "# #{escape_heading(title)}"
      authored.empty? ? "#{heading}\n" : "#{heading}\n\n#{authored}\n"
    end

    def route(page_route)
      return "/index.md" if page_route == "/"
      return "#{page_route.delete_suffix('/')}.md" if page_route.end_with?("/")

      "#{page_route}.md"
    end

    def escape_heading(title)
      title.to_s.gsub(/[\r\n]+/, " ").gsub(ESCAPABLE_PUNCTUATION, '\\\\\1')
    end
    private_class_method :escape_heading
  end
end
