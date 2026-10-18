# frozen_string_literal: true

module JekyllObsidian
  module TemplateFilters
    # Liquid 4's replace interprets backslash patterns in replacement text.
    def replace_literal(input, pattern, replacement)
      input.to_s.gsub(pattern.to_s) { replacement.to_s }
    end
  end
end
