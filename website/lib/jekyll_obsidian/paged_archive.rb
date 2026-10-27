# frozen_string_literal: true

require "json"
require "digest"
require "base64"
require "set"
require_relative "archive_chronology"

module JekyllObsidian
  # A static archive query interface: the browser fetches selected postings and
  # card chunks for a page, or the selected date range during Markdown export.
  module PagedArchive
    CALENDAR_FIELDS = { "years" => "year", "months" => "month", "days" => "display_date" }.freeze
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
    def build(cards, config, postings: true, scope: nil, tab_sources: [])
      size = config.blog.fetch("page_size") || 50
      labels = config.site.tag_labels || {}
      aliases = config.site.tag_aliases || {}
      facets = config.blog.fetch("facets")
      hidden = Array(config.site.hidden_tags).uniq.sort
      records = cards.map { |card| record(card, config) }
      # Each tab owns its artifact namespace as well as its current descriptor.
      # Identical member sets must not emit duplicate routes during preflight.
      # Resource-format changes also need fresh immutable URLs when input is unchanged.
      generation = Digest::SHA256.hexdigest(JSON.generate(["archive-v2", records, labels, aliases, config.blog, config.features.fetch("favorites"), postings, scope, hidden, tab_sources]))
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
      ranges = { "years" => years, "months" => months, "days" => days }
      excluded_sources = tab_sources.to_set
      view = unless excluded_sources.empty?
        { "total" => 0, "facets" => facets.to_h { |name, _| [name, Hash.new(0)] },
          "years" => Hash.new(0), "months" => Hash.new(0), "days" => Hash.new(0) }
      end
      excluded_bytes = Array.new((records.length + 7) / 8, 0) if view
      # Retain ordinals in the aligned records/cards arrays, even when the
      # default view excludes entries between the first page's visible cards.
      first_ordinals = []
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
        CALENDAR_FIELDS.each do |name, field|
          key = record[field]
          next unless key
          mapping = ranges.fetch(name)
          mapping[key] ||= [ordinal, ordinal]
          mapping[key][1] = ordinal + 1
        end
        if view && record.fetch("facets").fetch("source", []).any? { |id| excluded_sources.include?(id) }
          excluded_bytes[ordinal / 8] |= 1 << (ordinal % 8)
          next
        end
        first_ordinals << ordinal if first_ordinals.length < size
        next unless view

        view["total"] += 1
        record.fetch("facets").each { |name, ids| ids.each { |id| view["facets"][name][id] += 1 } }
        CALENDAR_FIELDS.each { |name, field| view[name][record[field]] += 1 if record[field] }
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
        "hidden_tags" => hidden, "tab_sources" => tab_sources,
        "export_max_days" => config.blog.fetch("export_max_days"),
        "labels" => labels, "aliases" => aliases, "years" => years, "months" => months, "days" => days,
        "chunks" => chunks, "ledger_group_by" => config.blog.fetch("ledger_group_by")
      }
      if view
        manifest["default_view"] = view
        manifest["excluded_posting"] = "excluded.json"
        emit.call("excluded.json", { "generation" => generation, "total" => records.length, "bitmap" => Base64.strict_encode64(excluded_bytes.pack("C*")) })
      end
      if config.features.fetch("favorites")
        manifest["identities"] = "identities.json"
        emit.call("identities.json", { "generation" => generation, "ids" => records.map { |card| card.fetch("id") } })
      end
      emit.call("manifest.json", manifest)
      url = config.url_builder.href("#{root}/manifest.json")
      current_route = scope ? "/assets/website/archive/tabs/#{scope}/current.json" : "/assets/website/archive/current.json"
      current_url = config.url_builder.href(current_route)
      files << GeneratedFile.new(route: current_route, content: "#{JSON.generate("version" => 1, "url" => url)}\n", media_type: "application/json", localize_content: true)
      first = first_ordinals.map do |ordinal|
        record = records[ordinal]
        labeled = card_labels(record, manifest)
        if config.features.fetch("favorites")
          labeled["favorite_card"] = cards[ordinal]["favorite_card"] || record.merge("favorite_labels" => favorite_labels(record.fetch("facets"), facets, labels))
        end
        labeled
      end
      daily = config.blog["timeline_granularity"] == "day"
      counts = (daily ? days : months).transform_values { |bounds| bounds[1] - bounds[0] }
      timeline = ArchiveChronology.timeline(counts, daily: daily)
      timeline.each do |year|
        year["count"] = view["years"].fetch(year["year"], 0)
        Array(year[daily ? "days" : "months"]).each { |entry| entry["count"] = view[daily ? "days" : "months"].fetch(entry["key"], 0) }
      end if view
      {
        "archive" => manifest.merge("url" => url, "current_url" => current_url),
        "archive_groups" => groups(first, config),
        "timeline" => timeline, "files" => files
      }
    end

    def record(card, config)
      date = card["published_at"]
      card.slice("id", "title", "url", "markdown_url", "summary", "source_url", "source_title", "date_basis").merge(
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
      grouped = cards.group_by { |card| card[key] || "Undated" }
      if key == "display_date"
        grouped = grouped.sort_by { |label, _| label == "Undated" ? "" : label }.reverse.to_h
        latest = grouped.keys.find { |label| label != "Undated" }
      end
      grouped.map do |label, posts|
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
