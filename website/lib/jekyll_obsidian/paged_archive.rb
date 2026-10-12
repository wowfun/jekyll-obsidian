# frozen_string_literal: true

require "json"
require "digest"
require "base64"
require "date"

module JekyllObsidian
  # A static archive query interface: the browser fetches selected postings and
  # card chunks for a page, or the selected date range during Markdown export.
  module PagedArchive
    module_function

    def facet_values(tags, config)
      aliases = config.site.tag_aliases || {}
      resolved = Array(tags).map { |tag| aliases.fetch(tag, tag) }.uniq
      config.blog.fetch("facets").to_h do |name, prefix|
        [name, resolved.filter_map { |tag| tag.delete_prefix(prefix) if tag.start_with?(prefix) }]
      end
    end

    def facet_links(tags, config)
      labels = config.site.tag_labels || {}
      facet_values(tags, config).flat_map do |name, ids|
        prefix = config.blog.fetch("facets").fetch(name)
        ids.map { |id| { "facet" => name, "id" => id, "name" => labels.fetch("#{prefix}#{id}", id) } }
      end
    end

    def build(cards, config)
      size = config.blog.fetch("page_size") || 50
      labels = config.site.tag_labels || {}
      aliases = config.site.tag_aliases || {}
      facets = config.blog.fetch("facets")
      offset = config.blog["utc_offset"]
      records = cards.map do |card|
        stamp = card["published_at"]
        date = stamp && (offset ? DateTime.iso8601(stamp).new_offset(offset).iso8601 : stamp)
        values = facet_values(card["tags"], config)
        card.slice("id", "title", "url", "markdown_url", "summary", "source_url", "date_basis").merge(
          "published_at" => date, "display_date" => date&.slice(0, 10),
          "year" => date&.slice(0, 4) || "Undated", "month" => date&.slice(0, 7),
          "facets" => values
        )
      end
      generation = Digest::SHA256.hexdigest(JSON.generate([records, labels, aliases, config.blog]))
      root = "/assets/website/archive/#{generation}"
      files = []
      emit = lambda do |name, data|
        files << GeneratedFile.new(route: "#{root}/#{name}", content: "#{JSON.generate(data)}\n", media_type: "application/json")
      end
      groups = facets.to_h do |name, prefix|
        members = Hash.new { |hash, key| hash[key] = [] }
        records.each_with_index { |record, ordinal| record.fetch("facets").fetch(name).each { |id| members[id] << ordinal } }
        options = members.map do |id, ordinals|
          filename = "facet-#{Digest::SHA256.hexdigest(JSON.generate([name, id]))}.json"
          bytes = Array.new((records.length + 7) / 8, 0)
          ordinals.each { |ordinal| bytes[ordinal / 8] |= 1 << (ordinal % 8) }
          emit.call(filename, { "generation" => generation, "total" => records.length, "bitmap" => Base64.strict_encode64(bytes.pack("C*")) })
          { "id" => id, "name" => labels.fetch("#{prefix}#{id}", id), "count" => ordinals.length, "posting" => filename }
        end.sort_by { |option| [-option.fetch("count"), option.fetch("id")] }
        [name, options]
      end
      months = {}
      years = {}
      days = {}
      records.each_with_index do |record, ordinal|
        [ [months, record["month"]], [years, record["year"]], [days, record["display_date"]] ].each do |mapping, key|
          next unless key
          mapping[key] ||= [ordinal, ordinal]
          mapping[key][1] = ordinal + 1
        end
      end
      chunks = []
      records.each_slice(size).with_index do |slice, index|
        filename = "cards-#{index}.json"
        chunks << filename
        emit.call(filename, { "generation" => generation, "start" => index * size, "cards" => slice })
      end
      manifest = {
        "version" => 1, "generation" => generation, "total" => records.length,
        "page_size" => size, "facets" => groups, "prefixes" => facets,
        "export_max_days" => config.blog.fetch("export_max_days", 7),
        "labels" => labels, "aliases" => aliases, "years" => years, "months" => months, "days" => days,
        "chunks" => chunks
      }
      emit.call("manifest.json", manifest)
      url = config.url_builder.href("#{root}/manifest.json")
      first = records.first(size).map { |record| card_labels(record, manifest) }
      daily = config.blog["timeline_granularity"] == "day"
      timeline = years.reject { |year, _| year == "Undated" }.map do |year, range|
        { "year" => year, "count" => range[1] - range[0], (daily ? "days" : "months") => (daily ? days : months).filter_map do |key, bounds|
          { "key" => key, "label" => key[5..], "count" => bounds[1] - bounds[0] } if key.start_with?(year)
        end }
      end
      {
        "archive" => manifest.merge("url" => url),
        "archive_groups" => first.group_by { |card| card.fetch("year") }.map { |year, posts| { "label" => year, "posts" => posts } },
        "timeline" => timeline, "files" => files
      }
    end

    def card_labels(card, manifest)
      card.merge("archive_facets" => card.fetch("facets").flat_map do |name, ids|
        prefix = manifest.fetch("prefixes").fetch(name)
        ids.map { |id| { "facet" => name, "id" => id, "name" => manifest.fetch("labels").fetch("#{prefix}#{id}", id) } }
      end)
    end
  end
end
