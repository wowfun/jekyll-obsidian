# frozen_string_literal: true

require "cgi/escape"

module JekyllObsidian
  class OfmScanner
    Embed = Struct.new(:target, :source_span, :token, keyword_init: true)
    Iframe = Struct.new(:html, :source_span, :token, :closed, keyword_init: true)
    Wikilink = Struct.new(:target, :display, :source_span, :token, keyword_init: true)
    Result = Struct.new(:markdown, :block_ids, :embeds, :iframes, :wikilinks, :tags, keyword_init: true)

    VOID_HTML_TAGS = %w[
      area base basefont bgsound br col command embed frame hr img input keygen
      link menuitem meta param source track wbr
    ].freeze

    def self.prepare(markdown)
      new(markdown).prepare
    end

    def initialize(markdown)
      @markdown = markdown
      @ofm_comment = false
      @html_comment = false
      @fence = nil
      @inline_code_delimiter = nil
      @raw_html_stack = []
      @html_tag = nil
      @iframe_body = nil
      @list_quote_depth = nil
      @list_indents = []
      @block_ids = []
      @embeds = []
      @iframes = []
      @wikilinks = []
      @tags = []
    end

    def prepare
      output = @markdown.lines.map.with_index(1) { |line, line_number| process_line(line, line_number) }.join
      capture_unfinished_iframe
      Result.new(
        markdown: output,
        block_ids: @block_ids,
        embeds: @embeds,
        iframes: @iframes,
        wikilinks: @wikilinks,
        tags: @tags.uniq
      )
    end

    private

    def process_line(line, line_number)
      if @fence
        content = fenced_container_content(line, @fence)
        unless content
          @fence = nil
          return process_line(line, line_number)
        end

        @fence = nil if fence_closer?(content, @fence)
        return line
      end

      if plain_markdown_state?
        context = markdown_context(line)
        if (opener = fence_opener(context.fetch(:content)))
          @fence = opener.merge(
            quote_depth: context.fetch(:quote_depth),
            list_indent: context.fetch(:list_indent)
          )
          return line
        end

        # Indented code begins four columns beyond the surrounding blockquote
        # and list content baseline, not necessarily four columns from column
        # zero. This distinction keeps ordinary list paragraphs scannable.
        return line if indented_code_line?(context.fetch(:content))
      end

      scan_line(line, line_number)
    end

    def scan_line(line, line_number)
      output = +""
      cursor = 0

      while cursor < line.length
        if @iframe_body
          cursor = continue_iframe_body(line, cursor, output)
        elsif @html_tag
          cursor = continue_html_tag(line, cursor, output, line_number)
        elsif @html_comment
          cursor = continue_comment(line, cursor, output, "-->", :@html_comment)
        elsif @ofm_comment
          cursor = continue_comment(line, cursor, output, "%%", :@ofm_comment)
        elsif @inline_code_delimiter
          cursor = continue_inline_code(line, cursor, output)
        elsif line[cursor, 4] == "<!--"
          @html_comment = true
          cursor += 4
        elsif line[cursor, 2] == "%%"
          @ofm_comment = true
          cursor += 2
        elsif line[cursor] == "`" && @raw_html_stack.empty?
          run = backtick_run(line, cursor)
          @inline_code_delimiter = run
          output << run
          cursor += run.length
        elsif line[cursor] == "\\" && @raw_html_stack.empty? && cursor + 1 < line.length
          if line[cursor + 1] == "!" && line[cursor + 2, 2] == "[["
            # Commonmarker otherwise parses the wikilink after the escaped
            # exclamation mark. Escape its first bracket as well so the whole
            # authored sequence remains literal and cannot publish a target.
            output << "\\!\\["
            cursor += 3
          else
            output << line[cursor, 2]
            cursor += 2
          end
        elsif line[cursor] == "<" && (tag = html_tag_start(line, cursor))
          cursor = start_html_tag(line, cursor, output, tag, line_number)
        elsif !@raw_html_stack.empty?
          output << line[cursor]
          cursor += 1
        elsif line[cursor, 3] == "![["
          cursor = scan_embed(line, cursor, line_number, output)
        elsif line[cursor, 2] == "[["
          cursor = scan_wikilink(line, cursor, line_number, output)
        elsif line[cursor] == "#"
          cursor = scan_tag(line, cursor, output)
        elsif line[cursor] == "^" && block_id_boundary?(line, cursor) && (match = line[cursor..].match(/\A\^([\p{L}\p{N}_-]+)[ \t]*(\r?\n)?\z/u))
          block_id = match[1].unicode_normalize(:nfc)
          @block_ids << [block_id, line_number]
          output << %(<span data-website-block-id="#{block_id}"></span>)
          output << match[2].to_s
          cursor = line.length
        else
          output << line[cursor]
          cursor += 1
        end
      end

      # Removing a whole-line comment must not join the surrounding Markdown
      # lines into one paragraph token.
      output << line_ending(line) if output.empty? && !line_ending(line).empty?
      output
    end

    def continue_comment(line, cursor, output, delimiter, state)
      ending = line.index(delimiter, cursor)
      unless ending
        ending = line_ending(line)
        output << ending unless ending.empty? || output.end_with?(ending)
        return line.length
      end

      instance_variable_set(state, false)
      ending + delimiter.length
    end

    def continue_inline_code(line, cursor, output)
      if line[cursor] == "`"
        run = backtick_run(line, cursor)
        if run.length == @inline_code_delimiter.length
          output << run
          @inline_code_delimiter = nil
          return cursor + run.length
        end
      end

      output << line[cursor]
      cursor + 1
    end

    def scan_embed(line, cursor, line_number, output)
      ending = line.index("]]", cursor + 3)
      unless ending
        output << line[cursor]
        return cursor + 1
      end

      target = line[(cursor + 3)...ending]
      token = @embeds.length
      @embeds << Embed.new(
        target: target,
        source_span: SourceSpan.new(
          start_line: line_number,
          start_column: cursor + 1,
          end_line: line_number,
          end_column: ending + 2
        ),
        token: token
      )
      output << %(<website-ofm-embed data-token="#{token}"></website-ofm-embed>)
      ending + 2
    end

    def scan_wikilink(line, cursor, line_number, output)
      ending = line.index("]]", cursor + 2)
      unless ending
        output << line[cursor]
        return cursor + 1
      end

      inner = line[(cursor + 2)...ending]
      target, display = inner.split("|", 2)
      token = @wikilinks.length
      @wikilinks << Wikilink.new(
        target: target.to_s,
        display: display,
        source_span: SourceSpan.new(
          start_line: line_number,
          start_column: cursor + 1,
          end_line: line_number,
          end_column: ending + 2
        ),
        token: token
      )
      label = display || target
      output << %(<a data-website-wikilink-token="#{token}">#{CGI.escapeHTML(label.to_s)}</a>)
      ending + 2
    end

    def scan_tag(line, cursor, output)
      match = tag_boundary?(line, cursor) && line[cursor..].match(/\A#([\p{L}\p{N}_-]+(?:\/[\p{L}\p{N}_-]+)*)/u)
      if match && !match[1].match?(/\A\d+\z/)
        @tags << match[1].unicode_normalize(:nfc)
        output << match[0]
        cursor + match[0].length
      else
        output << line[cursor]
        cursor + 1
      end
    end

    def fence_opener(content)
      match = content.match(/^ {0,3}(`{3,}|~{3,})/)
      return nil unless match

      { character: match[1][0], length: match[1].length }
    end

    def fence_closer?(content, fence)
      match = content.match(/^ {0,3}([#{Regexp.escape(fence.fetch(:character))}]+)[ \t]*(?:\r?\n)?$/)
      match && match[1].length >= fence.fetch(:length)
    end

    def indented_code_line?(content)
      content.match?(/\A(?: {4}|\t)/) && !content.strip.empty?
    end

    def markdown_context(line)
      content, quote_depth = strip_blockquote_prefixes(line)
      if @list_quote_depth != quote_depth
        @list_quote_depth = quote_depth
        @list_indents = []
      end

      unless content.strip.empty?
        leading_columns = indentation_columns(content)
        @list_indents.pop while @list_indents.last && @list_indents.last > leading_columns
      end

      baseline = @list_indents.last || 0
      effective, = remove_indentation(content, baseline)
      if (item = list_item_context(effective))
        item_indent = baseline + item.fetch(:content_indent)
        @list_indents << item_indent
        effective = item.fetch(:content)
        baseline = item_indent
      end

      { content: effective, quote_depth: quote_depth, list_indent: baseline }
    end

    def fenced_container_content(line, fence)
      content, quote_depth = strip_blockquote_prefixes(line)
      return content if content.strip.empty?
      return nil unless quote_depth == fence.fetch(:quote_depth)

      normalized, satisfied = remove_indentation(content, fence.fetch(:list_indent))
      satisfied ? normalized : nil
    end

    def strip_blockquote_prefixes(line)
      cursor = 0
      depth = 0
      loop do
        start = cursor
        spaces = 0
        while spaces < 3 && line[cursor] == " "
          spaces += 1
          cursor += 1
        end
        unless line[cursor] == ">"
          cursor = start
          break
        end

        depth += 1
        cursor += 1
        cursor += 1 if line[cursor] == " " || line[cursor] == "\t"
      end
      [line[cursor..].to_s, depth]
    end

    def list_item_context(content)
      ending = line_ending(content)
      body = ending.empty? ? content : content.delete_suffix(ending)
      match = body.match(/\A( {0,3})([-+*]|\d{1,9}[.)])([ \t]{1,4})(.*)\z/m)
      return nil unless match

      content_indent = indentation_columns(match[1]) + match[2].length
      match[3].each_char do |character|
        content_indent += character == "\t" ? 4 - (content_indent % 4) : 1
      end
      {
        content: "#{match[4]}#{ending}",
        content_indent: content_indent
      }
    end

    def indentation_columns(content)
      columns = 0
      content.each_char do |character|
        case character
        when " "
          columns += 1
        when "\t"
          columns += 4 - (columns % 4)
        else
          break
        end
      end
      columns
    end

    def remove_indentation(content, columns)
      return [content, true] if columns.zero?

      consumed_columns = 0
      cursor = 0
      while cursor < content.length && consumed_columns < columns
        character = content[cursor]
        width = if character == " "
          1
        elsif character == "\t"
          4 - (consumed_columns % 4)
        else
          return [content, false]
        end
        consumed_columns += width
        cursor += 1
      end
      return [content, false] if consumed_columns < columns

      ["#{" " * (consumed_columns - columns)}#{content[cursor..]}", true]
    end

    def html_tag_start(line, cursor)
      match = line[cursor..].match(/\A<\s*(\/)?\s*([A-Za-z][A-Za-z0-9-]*)(?=[\s\/>])/)
      return nil unless match

      { name: match[2].downcase, closing: !match[1].nil? }
    end

    def start_html_tag(line, cursor, output, tag, line_number)
      capture_iframe = tag[:name] == "iframe" && !tag[:closing]
      @html_tag = tag.merge(
        quote: nil,
        last_nonspace: nil,
        capture_iframe: capture_iframe,
        raw: capture_iframe ? +"" : nil,
        start_line: line_number,
        start_column: cursor + 1,
        end_line: line_number,
        end_column: cursor + 1
      )
      continue_html_tag(line, cursor, output, line_number)
    end

    def continue_html_tag(line, cursor, output, line_number)
      while cursor < line.length
        character = line[cursor]
        if @html_tag[:capture_iframe]
          @html_tag[:raw] << character
          @html_tag[:end_line] = line_number
          @html_tag[:end_column] = cursor + 1
        else
          output << character
        end
        if @html_tag[:quote]
          @html_tag[:quote] = nil if character == @html_tag[:quote]
        elsif character == '"' || character == "'"
          @html_tag[:quote] = character
        elsif character == ">"
          captured = @html_tag[:capture_iframe]
          self_closing = @html_tag[:last_nonspace] == "/"
          tag = @html_tag
          finish_html_tag
          if captured
            iframe = Iframe.new(
              html: tag.fetch(:raw),
              source_span: SourceSpan.new(
                start_line: tag.fetch(:start_line),
                start_column: tag.fetch(:start_column),
                end_line: line_number,
                end_column: cursor + 1
              ),
              token: @iframes.length,
              closed: self_closing
            )
            @iframes << iframe
            output << %(<website-ofm-iframe data-token="#{iframe.token}"></website-ofm-iframe>)
            @iframe_body = iframe unless self_closing
          end
          return cursor + 1
        elsif !character.match?(/\s/)
          @html_tag[:last_nonspace] = character
        end
        cursor += 1
      end
      if @html_tag[:capture_iframe]
        ending = line_ending(line)
        output << ending unless ending.empty? || output.end_with?(ending)
      end
      cursor
    end

    def capture_unfinished_iframe
      tag = @html_tag
      return unless tag&.fetch(:capture_iframe, false)

      @iframes << Iframe.new(
        html: tag.fetch(:raw),
        source_span: SourceSpan.new(
          start_line: tag.fetch(:start_line),
          start_column: tag.fetch(:start_column),
          end_line: tag.fetch(:end_line),
          end_column: tag.fetch(:end_column)
        ),
        token: @iframes.length,
        closed: false
      )
    end

    def continue_iframe_body(line, cursor, output)
      match = line.match(%r{</\s*iframe\s*>}i, cursor)
      unless match
        ending = line_ending(line)
        output << ending unless ending.empty? || output.end_with?(ending)
        return line.length
      end

      @iframe_body.closed = true
      @iframe_body = nil
      match.end(0)
    end

    def finish_html_tag
      tag = @html_tag
      if tag[:closing]
        matching = @raw_html_stack.rindex(tag[:name])
        @raw_html_stack.slice!(matching..) if matching
      elsif !tag[:capture_iframe] && tag[:last_nonspace] != "/" && !VOID_HTML_TAGS.include?(tag[:name])
        @raw_html_stack << tag[:name]
      end
      @html_tag = nil
    end

    def plain_markdown_state?
      !@ofm_comment && !@html_comment && !@inline_code_delimiter && @raw_html_stack.empty? && !@html_tag
    end

    def backtick_run(line, cursor)
      line[cursor..].match(/\A`+/)[0]
    end

    def tag_boundary?(line, cursor)
      cursor.zero? || !line[cursor - 1].match?(/[\p{L}\p{N}_\/-]/u)
    end

    def block_id_boundary?(line, cursor)
      cursor.zero? || line[cursor - 1].match?(/\s/)
    end

    def line_ending(line)
      line[/\r?\n\z/].to_s
    end
  end
end
