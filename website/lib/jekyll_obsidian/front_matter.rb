# frozen_string_literal: true

require "date"
require "psych"

module JekyllObsidian
  class FrontMatter
    XML_INVALID_CHARACTER = OutputText::INVALID_CHARACTER
    SUPPORTED = %w[
      publish title subtitle aliases tags author categories description permalink image cssclasses created updated
      content_type date pinned nav_order nav_exclude navigation comments github_markdown related
    ].freeze
    ARRAY_PROPERTIES = %w[aliases tags author categories cssclasses].freeze
    LINK_ARRAY_PROPERTIES = %w[author categories].freeze
    STRING_PROPERTIES = %w[title subtitle description permalink image].freeze
    CONTENT_TYPES = %w[post doc page].freeze
    NAVIGATION_KEYS = %w[label order visible].freeze

    Result = Struct.new(:properties, :property_links, :body, :diagnostics, keyword_init: true)

    def self.parse(path, bytes)
      new(path, bytes).parse
    end

    def self.valid_output_text?(value)
      OutputText.valid?(value)
    end

    def self.parse_wiki_link(value)
      return unless value.is_a?(String)

      match = value.match(/\A\[\[([^\[\]\r\n]+)\]\]\z/u)
      return unless match

      target, display = match[1].split("|", 2).map { |part| part&.strip }
      return if target.to_s.empty? || display == ""

      [target, display]
    end

    def initialize(path, bytes)
      @path = path
      @bytes = bytes.dup.force_encoding(Encoding::UTF_8)
      @diagnostics = []
    end

    def parse
      unless @bytes.valid_encoding?
        error("invalid_utf8", "note must be valid UTF-8")
        return result({}, [], "")
      end

      raw, body = split
      return result({}, [], body) unless raw

      parsed = Psych.safe_load(raw, permitted_classes: [Date, Time], aliases: false) || {}
      unless parsed.is_a?(Hash) && parsed.keys.all? { |key| key.is_a?(String) }
        error("invalid_frontmatter", "frontmatter must be a YAML mapping with string keys")
        return result({}, [], body)
      end

      properties, property_links = validate(parsed, raw)
      result(properties, property_links, body)
    rescue Psych::Exception => exception
      error("invalid_frontmatter", "invalid YAML frontmatter: #{exception.problem || exception.message}")
      result({}, [], body || "")
    end

    private

    def split
      return [nil, @bytes] unless @bytes.start_with?("---\n", "---\r\n")

      lines = @bytes.lines
      closing = lines.each_index.drop(1).find { |index| %W[---\n ---\r\n ...\n ...\r\n].include?(lines[index]) }
      unless closing
        error("invalid_frontmatter", "frontmatter is missing a closing delimiter")
        return ["", ""]
      end

      [lines[1...closing].join, lines[(closing + 1)..].to_a.join]
    end

    def validate(parsed, raw)
      unquoted_wiki_links = unquoted_wiki_link_properties(raw)
      property_nodes, property_key_nodes = frontmatter_nodes(raw)
      properties = {}
      property_links = []
      parsed.each do |key, value|
        unless SUPPORTED.include?(key)
          unless valid_custom_property_name?(key)
            error(
              "invalid_property",
              "custom property names must be non-empty NFC text without leading, trailing, or control characters",
              span: frontmatter_source_span(property_key_nodes[key])
            )
            next
          end

          valid, normalized = normalize_custom_property(key, value, property_nodes[key])
          next unless valid

          properties[key] = normalized
          unless key == "alias"
            property_links.concat(custom_property_links(key, normalized, property_nodes[key]))
          end
          next
        end

        case key
        when "publish", "comments", "pinned"
          if value == true || value == false
            properties[key] = value
          else
            code = case key
            when "publish" then "invalid_publish"
            when "comments" then "invalid_comments"
            else "invalid_property"
            end
            error(code, "#{key} must be a YAML boolean")
          end
        when *ARRAY_PROPERTIES
          if value.is_a?(Array) && value.all? { |item| self.class.valid_output_text?(item) }
            if LINK_ARRAY_PROPERTIES.include?(key) && value.any? { |item| wiki_link_candidate?(item) && !self.class.parse_wiki_link(item) }
              error("invalid_property", "#{key} wiki links must use [[target]] or [[target|label]] syntax")
            elsif unquoted_wiki_links.include?(key)
              error("invalid_property", "#{key} wiki link entries must use double-quoted YAML strings")
            elsif key == "cssclasses" && !value.all? { |item| item.match?(/\A[-_a-zA-Z][-_a-zA-Z0-9]*\z/) }
              error("invalid_property", "cssclasses entries must be valid CSS class tokens")
            else
              properties[key] = value.dup
            end
          else
            error("invalid_property", "#{key} must be an array of strings")
          end
        when "related"
          normalized, links = validate_related(value, property_nodes[key])
          if normalized
            properties[key] = normalized
            property_links.concat(links)
          end
        when *STRING_PROPERTIES
          if self.class.valid_output_text?(value)
            properties[key] = value
          else
            error("invalid_property", "#{key} must be a string containing only output-safe Unicode characters")
          end
        when "content_type"
          if CONTENT_TYPES.include?(value)
            properties[key] = value
          else
            error("invalid_property", "content_type must be one of: #{CONTENT_TYPES.join(', ')}")
          end
        when "created", "updated", "date"
          normalized = normalize_time(value)
          normalized ? properties[key] = normalized : error("invalid_property", "#{key} must be an ISO-8601 date or date-time")
        when "nav_order"
          if value.is_a?(Integer)
            properties[key] = value
          else
            error("invalid_property", "nav_order must be an integer")
          end
        when "nav_exclude"
          if value == true || value == false
            properties[key] = value
          else
            error("invalid_property", "nav_exclude must be a YAML boolean")
          end
        when "navigation"
          normalized = validate_navigation(value)
          properties[key] = normalized if normalized
        when "github_markdown"
          begin
            reference = GitHubMarkdown.normalize(value)
            properties[key] = {
              "repository" => reference.repository,
              "ref" => reference.ref,
              "path" => reference.path
            }
          rescue GitHubMarkdown::Invalid => exception
            error("invalid_property", exception.message)
          end
        end
      end
      [properties, property_links]
    end

    def valid_custom_property_name?(value)
      self.class.valid_output_text?(value) &&
        !value.empty? &&
        !value.match?(/\A\p{Space}|\p{Space}\z/u) &&
        value == value.unicode_normalize(:nfc) &&
        !value.match?(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u)
    rescue EncodingError
      false
    end

    def normalize_custom_property(key, value, property_node)
      if value.is_a?(Array)
        if value.all? { |item| custom_scalar?(item) }
          return [true, value.map { |item| normalize_custom_scalar(item) }]
        end
      elsif custom_scalar?(value)
        return [true, normalize_custom_scalar(value)]
      end

      if unquoted_wiki_link_node?(property_node)
        error("invalid_property", "#{key} wiki links must use double-quoted YAML strings")
      else
        error("invalid_property", "#{key} must be a scalar or a flat array of scalars")
      end
      [false, nil]
    end

    def validate_related(value, property_node)
      unless value.is_a?(Array)
        error("invalid_property", "related must be an array of double-quoted wiki links")
        return [nil, []]
      end

      nodes = property_node.is_a?(Psych::Nodes::Sequence) ? property_node.children : []
      links = []
      invalid = false
      value.each_with_index do |item, index|
        if item.is_a?(String) && !self.class.valid_output_text?(item)
          error("invalid_property", "related entries must contain only output-safe Unicode characters")
          invalid = true
          next
        end

        parsed = self.class.parse_wiki_link(item)
        node = nodes[index]
        unless parsed
          message = if unquoted_wiki_link_node?(node)
            "related wiki links must use double-quoted YAML strings"
          else
            "related entries must use [[target]] or [[target|label]] syntax"
          end
          error("invalid_property", message)
          invalid = true
          next
        end
        unless node.is_a?(Psych::Nodes::Scalar) && node.style == Psych::Nodes::Scalar::DOUBLE_QUOTED
          error("invalid_property", "related wiki links must use double-quoted YAML strings")
          invalid = true
          next
        end

        target, display = parsed
        links << FrontMatterLink.new(
          property: "related",
          index: index,
          target: target,
          display: display,
          source_span: frontmatter_source_span(node)
        )
      end
      invalid ? [nil, []] : [value.dup, links]
    end

    def unquoted_wiki_link_node?(node)
      return false unless node.is_a?(Psych::Nodes::Sequence)

      node.children.any? do |child|
        child.is_a?(Psych::Nodes::Sequence) &&
          (child.children.all? { |nested| nested.is_a?(Psych::Nodes::Scalar) } || unquoted_wiki_link_node?(child))
      end
    end

    def custom_scalar?(value)
      return true if value.nil? || value == true || value == false || value.is_a?(Integer)
      return value.finite? if value.is_a?(Float)
      return true if value.is_a?(Date) || value.is_a?(DateTime) || value.is_a?(Time)

      self.class.valid_output_text?(value)
    end

    def normalize_custom_scalar(value)
      return normalize_time(value) if value.is_a?(Date) || value.is_a?(DateTime) || value.is_a?(Time)

      value
    end

    def custom_property_links(property, value, property_node)
      values = value.is_a?(Array) ? value : [value]
      nodes = if property_node.is_a?(Psych::Nodes::Sequence)
        property_node.children
      else
        [property_node]
      end

      values.each_with_index.filter_map do |item, index|
        next unless item.is_a?(String)

        parsed = self.class.parse_wiki_link(item)
        if parsed
          node = nodes[index]
          unless node.is_a?(Psych::Nodes::Scalar) && node.style == Psych::Nodes::Scalar::DOUBLE_QUOTED
            error("invalid_property", "#{property} wiki links must use double-quoted YAML strings")
            next
          end

          target, display = parsed
          FrontMatterLink.new(
            property: property,
            index: index,
            target: target,
            display: display,
            source_span: frontmatter_source_span(node)
          )
        elsif item.start_with?("[[")
          error("invalid_property", "#{property} wiki links must use [[target]] or [[target|label]] syntax")
          nil
        end
      end
    end

    def frontmatter_nodes(raw)
      mapping = Psych.parse(raw)&.root
      return [{}, {}] unless mapping.is_a?(Psych::Nodes::Mapping)

      property_nodes = {}
      property_key_nodes = {}
      mapping.children.each_slice(2) do |key_node, value_node|
        next unless key_node.is_a?(Psych::Nodes::Scalar)

        property_nodes[key_node.value] = value_node
        property_key_nodes[key_node.value] = key_node
      end
      [property_nodes, property_key_nodes]
    end

    def frontmatter_source_span(node)
      SourceSpan.new(
        start_line: node.start_line + 2,
        start_column: node.start_column + 1,
        end_line: node.end_line + 2,
        end_column: node.end_column + 1
      )
    end

    def validate_navigation(value)
      unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
        error("invalid_property", "navigation must be a YAML mapping with string keys")
        return nil
      end

      unknown = value.keys - NAVIGATION_KEYS
      unknown.sort.each { |key| error("invalid_property", "unknown navigation setting #{key.inspect}") }
      normalized = {}
      if value.key?("label")
        label = value["label"]
        if self.class.valid_output_text?(label) && !label.strip.empty?
          normalized["label"] = label
        else
          error("invalid_property", "navigation.label must be a non-empty string containing only output-safe Unicode characters")
        end
      end
      if value.key?("order")
        order = value["order"]
        if order.is_a?(Integer)
          normalized["order"] = order
        else
          error("invalid_property", "navigation.order must be an integer")
        end
      end
      if value.key?("visible")
        visible = value["visible"]
        if visible == true || visible == false
          normalized["visible"] = visible
        else
          error("invalid_property", "navigation.visible must be a YAML boolean")
        end
      end
      normalized
    end

    def wiki_link_candidate?(value)
      value.start_with?("[[") || value.end_with?("]]")
    end

    def unquoted_wiki_link_properties(raw)
      mapping = Psych.parse(raw)&.root
      return [] unless mapping.is_a?(Psych::Nodes::Mapping)

      mapping.children.each_slice(2).filter_map do |key_node, value_node|
        next unless key_node.is_a?(Psych::Nodes::Scalar) && LINK_ARRAY_PROPERTIES.include?(key_node.value)
        next unless value_node.is_a?(Psych::Nodes::Sequence)

        invalid = value_node.children.any? do |item|
          item.is_a?(Psych::Nodes::Scalar) &&
            self.class.parse_wiki_link(item.value) &&
            item.style != Psych::Nodes::Scalar::DOUBLE_QUOTED
        end
        key_node.value if invalid
      end
    end

    def normalize_time(value)
      case value
      when DateTime, Time
        value.iso8601
      when Date
        "#{value.iso8601}T00:00:00Z"
      when String
        return "#{Date.iso8601(value).iso8601}T00:00:00Z" if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

        DateTime.iso8601(value).iso8601
      end
    rescue Date::Error
      nil
    end

    def error(code, message, span: nil)
      @diagnostics << Diagnostic.new(severity: :error, code: code, message: message, path: @path, span: span)
    end

    def result(properties, property_links, body)
      Result.new(properties: properties, property_links: property_links, body: body, diagnostics: @diagnostics)
    end
  end
end
