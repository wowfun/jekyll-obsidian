# frozen_string_literal: true

require "psych"

module JekyllObsidian
  # The same taxonomy metadata applies to single-language and localized sites.
  module TagPolicy
    KEYS = %w[name hreflang dir messages tag_labels tag_aliases hidden_tags].freeze
    Resolution = Data.define(:policy, :errors)
    module_function

    def parse(bytes)
      raw = Psych.safe_load(bytes.to_s, permitted_classes: [], aliases: false)
      unless raw.is_a?(Hash) && raw.keys.all? { |key| key.is_a?(String) }
        raise ArgumentError, "locale manifest must be a YAML mapping with string keys"
      end
      raw
    end

    def resolve(raw)
      errors = (raw.keys - KEYS).map { |key| "unknown locale setting #{key.inspect}" }
      maps = %w[tag_labels tag_aliases].to_h do |key|
        value = raw.fetch(key, {})
        unless value.is_a?(Hash) && value.all? { |tag, label| valid_tag?(tag) && valid_tag?(label) }
          errors << "#{key} must map non-empty tags to non-empty strings"
          value = {}
        end
        [key, value]
      end
      aliases = maps.fetch("tag_aliases")
      aliases.each do |tag, replacement|
        if tag == replacement || aliases.key?(replacement) || tag.split("/").first != replacement.split("/").first
          errors << "tag_aliases must be flattened replacements within one namespace"
        end
      end
      hidden = raw.fetch("hidden_tags", [])
      unless hidden.is_a?(Array) && hidden.all? { |tag| valid_tag?(tag) } && hidden.uniq.length == hidden.length
        errors << "hidden_tags must contain unique non-empty tags"
        hidden = []
      end
      Resolution.new(policy: maps.merge("hidden_tags" => hidden.map { |tag| aliases.fetch(tag, tag) }.uniq.sort), errors: errors)
    end

    def valid_tag?(value)
      OutputText.valid?(value) && !value.empty?
    end
    private_class_method :valid_tag?
  end
end
