# frozen_string_literal: true

module JekyllObsidian
  module Diagnostics
    def self.normalize(items)
      items.uniq.sort_by do |item|
        span = item.span
        [item.path.to_s.b,
          [span&.start_line.to_i, span&.start_column.to_i, span&.end_line.to_i, span&.end_column.to_i],
          item.severity.to_s, item.code.to_s, item.property.to_s, item.message.to_s]
      end.freeze
    end
  end
end
