# frozen_string_literal: true

require "date"
require "psych"

module JekyllObsidian
  class FrontMatter
    XML_INVALID_CHARACTER = /[^\u{9}\u{A}\u{D}\u{20}-\u{D7FF}\u{E000}-\u{FFFD}\u{10000}-\u{10FFFF}]/u
    SUPPORTED = %w[
      publish title subtitle aliases tags author categories description permalink image cssclasses created updated
      content_type date nav_order nav_exclude navigation comments
    ].freeze
    ARRAY_PROPERTIES = %w[aliases tags author categories cssclasses].freeze
    LINK_ARRAY_PROPERTIES = %w[author categories].freeze
    STRING_PROPERTIES = %w[title subtitle description permalink image].freeze
    CONTENT_TYPES = %w[post doc page].freeze
    NAVIGATION_KEYS = %w[label order visible].freeze

    Result = Struct.new(:properties, :body, :diagnostics, keyword_init: true)

    def self.parse(path, bytes)
      new(path, bytes).parse
    end

    def self.valid_output_text?(value)
      value.is_a?(String) && value.valid_encoding? && !value.match?(XML_INVALID_CHARACTER)
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
        return result({}, "")
      end

      raw, body = split
      return result({}, body) unless raw

      parsed = Psych.safe_load(raw, permitted_classes: [Date, Time], aliases: false) || {}
      unless parsed.is_a?(Hash) && parsed.keys.all? { |key| key.is_a?(String) }
        error("invalid_frontmatter", "frontmatter must be a YAML mapping with string keys")
        return result({}, body)
      end

      properties = validate(parsed, raw)
      result(properties, body)
    rescue Psych::Exception => exception
      error("invalid_frontmatter", "invalid YAML frontmatter: #{exception.problem || exception.message}")
      result({}, body || "")
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
      properties = {}
      parsed.each do |key, value|
        next unless SUPPORTED.include?(key)

        case key
        when "publish", "comments"
          if value == true || value == false
            properties[key] = value
          else
            code = key == "publish" ? "invalid_publish" : "invalid_comments"
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
        end
      end
      properties
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

    def error(code, message)
      @diagnostics << Diagnostic.new(severity: :error, code: code, message: message, path: @path, span: nil)
    end

    def result(properties, body)
      Result.new(properties: properties, body: body, diagnostics: @diagnostics)
    end
  end
end
