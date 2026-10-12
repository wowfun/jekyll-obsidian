# frozen_string_literal: true

require "date"

module JekyllObsidian
  module ArchiveChronology
    module_function

    def local_time(value, offset)
      value && offset ? DateTime.iso8601(value).new_offset(offset).iso8601 : value
    end

    def timeline(counts, daily:)
      counts.keys.group_by { |key| key[0, 4] }.sort.reverse.map do |year, keys|
        {
          "year" => year,
          "count" => keys.sum { |key| counts.fetch(key) },
          (daily ? "days" : "months") => (daily ? keys.sort.reverse : keys.sort).map do |key|
            { "key" => key, "label" => key[5..], "count" => counts.fetch(key) }
          end
        }
      end
    end
  end
end
