# frozen_string_literal: true

require "json"
require "digest"
require "base64"
require_relative "archive_chronology"

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
      label_facets(facet_values(tags, config), config.blog.fetch("facets"), config.site.tag_labels || {})
    end

    def label_facets(values, prefixes, labels)
      values.flat_map do |name, ids|
        prefix = prefixes.fetch(name)
        ids.map { |id| { "facet" => name, "id" => id, "name" => labels.fetch("#{prefix}#{id}", id) } }
      end
    end

    # Cards must be in descending display-date order with undated cards last.
    # Within each day, preserve the presenter's stable ordering. Date ranges in
    # the emitted index refer to contiguous ordinal blocks in this sequence.
    def build(cards, config, postings: true, scope: nil)
      size = config.blog.fetch("page_size") || 50
      labels = config.site.tag_labels || {}
      aliases = config.site.tag_aliases || {}
      facets = config.blog.fetch("facets")
      records = cards.map { |card| record(card, config) }
      # Each tab owns its artifact namespace as well as its current descriptor.
      # Identical member sets must not emit duplicate routes during preflight.
      generation = Digest::SHA256.hexdigest(JSON.generate([records, labels, aliases, config.blog, config.features.fetch("favorites"), postings, scope]))
      root = "/assets/website/archive/#{generation}"
      files = []
      emit = lambda do |name, data, localize_content: false|
        files << GeneratedFile.new(route: "#{root}/#{name}", content: "#{JSON.generate(data)}\n", media_type: "application/json", localize_content: localize_content)
      end
      groups = facets.to_h do |name, prefix|
        members = Hash.new { |hash, key| hash[key] = [] }
        records.each_with_index { |record, ordinal| record.fetch("facets").fetch(name).each { |id| members[id] << ordinal } }
        options = members.map do |id, ordinals|
          filename = "facet-#{Digest::SHA256.hexdigest(JSON.generate([name, id]))}.json"
          option = { "id" => id, "name" => labels.fetch("#{prefix}#{id}", id), "count" => ordinals.length }
          if postings
            bytes = Array.new((records.length + 7) / 8, 0)
            ordinals.each { |ordinal| bytes[ordinal / 8] |= 1 << (ordinal % 8) }
            emit.call(filename, { "generation" => generation, "total" => records.length, "bitmap" => Base64.strict_encode64(bytes.pack("C*")) })
            option["posting"] = filename
          end
          option
        end.sort_by { |option| [-option.fetch("count"), option.fetch("id")] }
        [name, options]
      end
      months = {}
      years = {}
      days = {}
      previous_day = nil
      undated = false
      records.each_with_index do |record, ordinal|
        day = record["display_date"]
        if day
          # Export ranges rely on descending, contiguous calendar-day blocks.
          raise ArgumentError, "Paged archive dates must be descending with undated cards last" if undated || (previous_day && day > previous_day)
          previous_day = day
        else
          undated = true
        end
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
        emit.call(filename, { "generation" => generation, "start" => index * size, "cards" => slice }, localize_content: true)
      end
      manifest = {
        "version" => 1, "generation" => generation, "total" => records.length,
        "page_size" => size, "facets" => groups, "prefixes" => facets,
        "export_max_days" => config.blog.fetch("export_max_days"),
        "labels" => labels, "aliases" => aliases, "years" => years, "months" => months, "days" => days,
        "chunks" => chunks, "ledger_group_by" => config.blog.fetch("ledger_group_by")
      }
      if config.features.fetch("favorites")
        manifest["identities"] = "identities.json"
        emit.call("identities.json", { "generation" => generation, "ids" => records.map { |card| card.fetch("id") } })
      end
      emit.call("manifest.json", manifest)
      url = config.url_builder.href("#{root}/manifest.json")
      current_route = scope ? "/assets/website/archive/tabs/#{scope}/current.json" : "/assets/website/archive/current.json"
      current_url = config.url_builder.href(current_route)
      files << GeneratedFile.new(route: current_route, content: "#{JSON.generate("version" => 1, "url" => url)}\n", media_type: "application/json", localize_content: true)
      first = records.first(size).each_with_index.map do |record, index|
        labeled = card_labels(record, manifest)
        if config.features.fetch("favorites")
          labeled["favorite_card"] = cards[index]["favorite_card"] || record.merge("favorite_labels" => favorite_labels(record.fetch("facets"), facets, labels))
        end
        labeled
      end
      daily = config.blog["timeline_granularity"] == "day"
      counts = (daily ? days : months).transform_values { |bounds| bounds[1] - bounds[0] }
      timeline = ArchiveChronology.timeline(counts, daily: daily)
      {
        "archive" => manifest.merge("url" => url, "current_url" => current_url),
        "archive_groups" => groups(first, config),
        "timeline" => timeline, "files" => files
      }
    end

    def record(card, config)
      date = card["published_at"]
      card.slice("id", "title", "url", "markdown_url", "summary", "source_url", "date_basis").merge(
        "published_at" => date, "facets" => facet_values(card["tags"], config)
      ).merge(calendar_fields(date))
    end

    def calendar_fields(date)
      { "display_date" => date&.slice(0, 10), "year" => date&.slice(0, 4) || "Undated", "month" => date&.slice(0, 7) }
    end

    def favorite_labels(values, prefixes, labels)
      values.each_with_object({}) do |(name, ids), result|
        prefix = prefixes.fetch(name)
        ids.each { |id| result["#{name}/#{id}"] = labels.fetch("#{prefix}#{id}", id) }
      end
    end

    def groups(cards, config)
      key = config.blog.fetch("ledger_group_by") == "day" ? "display_date" : "year"
      latest = cards.filter_map { |card| card["display_date"] }.max if key == "display_date"
      cards.group_by { |card| card[key] || "Undated" }.map do |label, posts|
        group = { "label" => label, "posts" => posts }
        if key == "display_date"
          date = label == "Undated" ? nil : Date.iso8601(label)
          group["day"] = { "year" => date.year, "month" => date.month, "day" => date.day, "weekday" => date.wday } if date
          group["open"] = latest ? label == latest : true
        end
        group
      end
    end

    def card_labels(card, manifest)
      facets = label_facets(card.fetch("facets"), manifest.fetch("prefixes"), manifest.fetch("labels"))
      card.merge("archive_facets" => facets)
    end
  end
end
