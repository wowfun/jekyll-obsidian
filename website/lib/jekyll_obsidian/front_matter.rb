# frozen_string_literal: true

require "date"
require "psych"

module JekyllObsidian
  class FrontMatter
    XML_INVALID_CHARACTER = /[^\u{9}\u{A}\u{D}\u{20}-\u{D7FF}\u{E000}-\u{FFFD}\u{10000}-\u{10FFFF}]/u
    SUPPORTED = %w[
      publish title aliases tags description permalink image cssclasses created updated
      content_type date nav_order nav_exclude comments
    ].freeze
    ARRAY_PROPERTIES = %w[aliases tags cssclasses].freeze
    STRING_PROPERTIES = %w[title description permalink image].freeze
    CONTENT_TYPES = %w[post doc page].freeze

    Result = Struct.new(:properties, :body, :diagnostics, keyword_init: true)

    def self.parse(path, bytes)
      new(path, bytes).parse
    end

    def self.valid_output_text?(value)
      value.is_a?(String) && value.valid_encoding? && !value.match?(XML_INVALID_CHARACTER)
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

      properties = validate(parsed)
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

    def validate(parsed)
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
            if key == "cssclasses" && !value.all? { |item| item.match?(/\A[-_a-zA-Z][-_a-zA-Z0-9]*\z/) }
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
        end
      end
      properties
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
