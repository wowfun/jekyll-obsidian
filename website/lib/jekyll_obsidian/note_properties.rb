# frozen_string_literal: true

require "date"
require "set"

module JekyllObsidian
  # A display projection, never a merge into Jekyll's page control data.
  # Link resolution stays in the compiler; both themes receive the same values.
  module NoteProperties
    EXCLUDED = Set.new(FrontMatter::SUPPORTED + FrontMatter::JEKYLL_CONTROL_KEYS).freeze
    module_function

    def visible?(name, hidden:)
      !EXCLUDED.include?(name) && !hidden.include?(name)
    end

    def project(properties, hidden:, links:)
      properties.filter_map do |name, value|
        next unless visible?(name, hidden: hidden)

        list = value.is_a?(Array)
        values = list ? value : [value]
        {
          "name" => name,
          "kind" => list ? "list" : "scalar",
          "values" => values.each_with_index.map { |item, index| links[[name, index]] || scalar(item) }
        }
      end
    end

    # Unsupported objects indicate a violation of FrontMatter's normalized contract.
    def scalar(value)
      case value
      when nil then { "kind" => "null", "text" => "null" }
      when true, false then { "kind" => "boolean", "text" => value.to_s }
      when Numeric then { "kind" => "number", "text" => value.to_s }
      when Time, DateTime
        text = value.is_a?(Time) ? value.iso8601(value.nsec.zero? ? 0 : 9) : value.iso8601
        { "kind" => "datetime", "text" => text, "datetime" => text }
      when Date
        { "kind" => "date", "text" => value.iso8601, "datetime" => value.iso8601 }
      when String
        return { "kind" => "empty_string", "text" => '""' } if value.empty?
        if (link = FrontMatter.parse_wiki_link(value))
          return { "kind" => "text", "text" => link[1] || link[0] }
        end
        return { "kind" => "url", "text" => value, "external_url" => value } if FrontMatter.public_url?(value)

        { "kind" => "text", "text" => value }
      else
        raise ArgumentError, "Unsupported property scalar type: #{value.class}"
      end
    end
  end
end
