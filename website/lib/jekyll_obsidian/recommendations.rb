# frozen_string_literal: true

require "json"
require "time"

module JekyllObsidian
  # External recommendations are presentation metadata, never graph edges.
  module Recommendations
    PATH = "_recommendations.json"
    module_function

    def note_path?(value)
      value.is_a?(String) && value.end_with?(".md") &&
        !value.match?(/[\\\x00-\x1f:?#]/) &&
        value.split("/", -1).none? { |part| ["", ".", ".."].include?(part) } &&
        !value.start_with?("_translations/")
    end

    def parse(bytes)
      document = JSON.parse(bytes)
      unless document.is_a?(Hash) && document.keys.sort == %w[items version] && document["version"] == 1 && document["items"].is_a?(Hash)
        raise ArgumentError, "recommendations require version 1 and an items mapping"
      end
      document.fetch("items").to_h do |path, targets|
        raise ArgumentError, "invalid recommendation source path" unless note_path?(path)
        raise ArgumentError, "recommendation targets must be an array" unless targets.is_a?(Array)
        normalized = targets.map do |target|
          unless target.is_a?(Hash) && target.keys.sort == %w[expires_at path] && note_path?(target["path"]) &&
              target["expires_at"].is_a?(String) && target["expires_at"].match?(/(?:Z|[+-]\d\d:\d\d)\z/)
            raise ArgumentError, "recommendation targets require a note path and absolute expires_at"
          end
          { "path" => target.fetch("path"), "expires_at" => Time.iso8601(target.fetch("expires_at")).utc.iso8601 }
        end
        [path, normalized.uniq { |target| target.fetch("path") }]
      end
    end
  end
end
