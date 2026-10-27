# frozen_string_literal: true

module JekyllObsidian
  # Owns the one plain-Markdown representation shared by generated resources
  # and the page actions that copy them. Callers only provide authored source
  # facts; route and byte normalization stay behind this interface.
  module PublishedMarkdown
    ESCAPABLE_PUNCTUATION = /([!"#$%&'()*+,\-.\/:;<=>?@\[\\\]^_`{|}~])/
    TRAILING_NEWLINES = /(?:\r\n|\n|\r)+\z/
    module_function

    def content(title:, body:, has_h1:, image_urls: {})
      authored = project_images(body.to_s, image_urls).sub(TRAILING_NEWLINES, "")
      return "#{authored}\n" if has_h1

      heading = "# #{escape_heading(title)}"
      authored.empty? ? "#{heading}\n" : "#{heading}\n\n#{authored}\n"
    end

    # Parse the original source: OFM preprocessing changes column offsets. Only
    # image nodes are serialized, so prose, code and ordinary reference links
    # keep their authored bytes. Reference images become self-contained inline
    # images, without changing a definition also used by an ordinary link.
    def project_images(body, urls)
      return body if urls.empty?

      bytes = body.b
      line_offsets = [0]
      # CommonMark recognizes LF, CRLF and bare CR. Track their original bytes.
      bytes.scan(/\r\n?|\n/) { line_offsets << Regexp.last_match.end(0) }
      edits = []
      # Splices use byte offsets, including when Unicode precedes an image.
      Commonmarker.parse(body, options: MarkdownOptions::SOURCE_BYTES).walk do |node|
        next unless node.type == :image && (url = urls[node.url])
        parent = node.parent
        parent = parent.parent while parent && parent.type != :image
        next if parent # Nested image syntax contributes only to the outer alt.

        cell = node.parent
        cell = cell.parent while cell && cell.type != :table_cell
        position = node.source_position
        start = source_offset(bytes, line_offsets, position[:start_line], position[:start_column] - 1, cell)
        finish = source_offset(bytes, line_offsets, position[:end_line], position[:end_column], cell)
        node.url = url
        text = node.to_commonmark(options: { render: { width: 0 } }).strip
        text = text.gsub("|") { "\\|" } if cell
        edits << [start, finish, text]
      end
      output = body.b.dup
      edits.sort_by(&:first).reverse_each { |start, finish, text| output[start...finish] = text.b }
      output.force_encoding(body.encoding)
    end
    private_class_method :project_images

    def source_offset(bytes, line_offsets, line, column, cell)
      offset = line_offsets.fetch(line - 1) + column
      return offset unless cell

      # Comrak removes the backslash in table-cell \| before assigning inline
      # positions. Restore those bytes, including escapes before the image.
      position = cell.source_position
      start = line_offsets.fetch(position.fetch(:start_line) - 1) + position.fetch(:start_column) - 1
      length = position.fetch(:end_column) - position.fetch(:start_column) + 1
      relative = offset - start
      bytes.byteslice(start, length).scan(/\\\|/) do
        break if Regexp.last_match.begin(0) >= relative
        relative += 1
      end
      start + relative
    end
    private_class_method :source_offset

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
