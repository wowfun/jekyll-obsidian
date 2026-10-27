# frozen_string_literal: true

require "cgi/escape"
require "date"
require_relative "archive_chronology"

module JekyllObsidian
  # The only internal theme seam. Each built-in adapter consumes the same
  # immutable PublishedSiteModel and returns a complete ThemeOutput through a
  # single render interface.
  module BuiltInThemes
    IDS = %w[minimal docs].freeze
    ALWAYS_RESERVED_NAMESPACES = %w[
      /404.html /sitemap.xml /assets/website /assets/vault
    ].freeze
    module_function

    def resolve(id)
      case id
      when "minimal" then Minimal.new
      when "docs" then Docs.new
      else
        raise ArgumentError, "unknown built-in theme #{id.inspect}"
      end
    end

    class Presenter
      private

      def project(model:, config:, landing_note:, note_theme_data:, theme_pages:, system_theme_data:, taxonomy:, feed_notes:, shared_files: [], suppressed_note_routes: [], home_route: nil, &note_page_transform)
        topic_anchors = taxonomy.fetch("anchors")
        tag_groups = taxonomy.fetch("groups")
        topic_summaries = taxonomy.fetch("summaries")
        local_graphs = config.features.fetch("graph") ? local_graphs(model, config) : {}
        home_route ||= landing_note ? landing_note.route : "/"
        home_url = config.url_builder.href(home_route)
        pages = model.notes.reject { |note| suppressed_note_routes.include?(note.route) }.map do |note|
          output = note_page(
            note,
            config,
            note_theme_data.fetch(note.id),
            topic_anchors,
            topic_summaries,
            local_graphs[note.id],
            home_route,
            home_url
          )
          note_page_transform ? note_page_transform.call(note, output) : output
        end
        pages.concat(theme_pages)
        if config.theme == "docs" && config.features.fetch("tags")
          pages << tags_page(tag_groups, config, system_theme_data, home_route, home_url)
        end
        pages << not_found_page(config, system_theme_data, home_route, home_url)
        pages << redirect_page(landing_note, config, home_route, home_url) if landing_note && pages.none? { |page| page.route == "/" }

        artifacts = []
        artifacts << "catalog" if config.features.fetch("previews")
        artifacts << "graph" if config.features.fetch("graph")
        artifacts << "search" if config.features.fetch("search")
        artifacts << "sitemap"
        artifacts << "feed" if config.features.fetch("feed")

        namespaces = ALWAYS_RESERVED_NAMESPACES.dup
        namespaces << "/feed.xml" if config.features.fetch("feed")
        pages = pages.map { |page| attach_navigation(page, config) }

        ThemeOutput.new(
          pages: pages,
          artifacts: artifacts,
          shared_files: shared_files,
          site_data: {},
          feed_note_ids: feed_notes.sort_by(&:id).map(&:id),
          reserved_namespaces: namespaces
        )
      end

      def favorite_card(note, config)
        # Shared by the article, ledger and other post cards during one render.
        @favorite_cards[note.id] ||= begin
          record = PagedArchive.record(content_card(note, config).merge(
            "published_at" => ArchiveChronology.local_time(note.published_at, config.blog["utc_offset"]),
            "markdown_url" => config.url_builder.href(PublishedMarkdown.route(note.route))), config)
          record.merge("favorite_labels" => PagedArchive.favorite_labels(record.fetch("facets"), config.blog.fetch("facets"), config.site.tag_labels || {}))
        end
      end

      def note_page(note, config, theme_data, topic_anchors, topic_summaries, local_graph, home_route, home_url)
        properties = note.properties
        comments = page_comments(note, config)
        website = {
          "kind" => "note",
          "id" => note.id,
          "content_type" => note.content_type,
          "published_at" => ArchiveChronology.local_time(note.published_at, config.blog["utc_offset"]),
          "route" => note.route,
          "href" => config.url_builder.href(note.route),
          "absolute_url" => config.url_builder.absolute_url(note.route),
          "markdown_url" => config.url_builder.href(PublishedMarkdown.route(note.route)),
          "aliases" => Array(properties["aliases"]),
          "subtitle" => properties["subtitle"],
          "tags" => Array(properties["tags"]),
          "authors" => note.topics.select { |topic| topic.fetch("kind") == "author" },
          "categories" => Array(properties["categories"]),
          "topic_links" => blog_topic_links(note, topic_anchors, config),
          "cssclasses" => Array(properties["cssclasses"]),
          "created" => note.created,
          "updated" => ArchiveChronology.local_time(note.updated, config.blog["utc_offset"]),
          "directory_index" => note.directory_index,
          "has_h1" => note.has_h1,
          "source_links" => note.source_links,
          "source_url" => note.source_url,
          "source_title" => properties["source_title"],
          "display_properties" => note.display_properties,
          "date_basis" => properties["date_basis"],
          "archive_item" => note.content_type == "post" && config.home["layout"] == "archive",
          "archive_facets" => note.content_type == "post" && config.home["layout"] == "archive" ? PagedArchive.facet_links(properties["tags"], config) : [],
          "home_route" => home_route,
          "home_url" => home_url,
          "routes" => { "home" => home_route },
          "theme" => config.theme,
          "features" => config.features.merge(note.feature_flags),
          "favorites_scope" => config.url_builder.baseurl,
          "favorite_card" => config.features.fetch("favorites") && note.content_type == "post" ? favorite_card(note, config) : nil,
          "content_security" => content_security_data(note.content_security, config),
          "theme_data" => theme_data,
          "tag_links" => Array(note.properties["tags"]).filter_map do |tag|
            anchor = topic_anchors[topic_identity("name" => tag)]
            { "name" => topic_label({ "kind" => "tag", "name" => tag }, config), "anchor" => anchor } if anchor
          end,
          "outline" => note.outline,
          "related_articles" => theme_data.fetch("related_articles", note.related || []),
          "links" => config.features.fetch("relations") ? note.links : [],
          "backlinks" => config.features.fetch("relations") ? note.backlinks : [],
          "embedded_by" => config.features.fetch("relations") ? note.embedded_by : []
        }
        website["compact_collection"] = note.presentation&.fetch("empty_intro", false) &&
          properties.dig("tab", "layout") != "archive" &&
          !website["subtitle"] && !website["updated"] && !website["source_url"] &&
          website.fetch("display_properties").empty? &&
          (!config.features.fetch("tags") || website.fetch("tag_links").empty?) &&
          (properties["description"] || note.preview).to_s == note.title
        website["local_graph"] = local_graph if local_graph
        website["has_context"] = context_present?(website)
        website["comments"] = comments if comments
        website["analytics"] = analytics_data(config.analytics) unless config.analytics.provider.empty?
        data = {
          "title" => note.title,
          "description" => properties["description"] || note.preview,
          "image" => note.image_url,
          "layout" => "website-#{config.theme}",
          "website" => website
        }.compact
        PageOutput.new(route: note.route, content: note.content, data: data)
      end

      def system_page(
        config,
        route,
        title,
        kind,
        system_theme_data,
        theme_data = {},
        home_route: "/",
        home_url: config.url_builder.href(home_route),
        content: "",
        description: config.site.description.to_s,
        website_data: {}
      )
        PageOutput.new(
          route: route,
          content: content,
          data: {
            "layout" => "website-#{config.theme}",
            "title" => title,
            "description" => description,
            "website" => {
              "kind" => kind,
              "theme" => config.theme,
              "features" => config.features,
              "favorites_scope" => config.url_builder.baseurl,
              "content_security" => content_security_data(nil, config),
              "theme_data" => system_theme_data.merge(theme_data),
              "route" => route,
              "href" => config.url_builder.href(route),
              "absolute_url" => config.url_builder.absolute_url(route),
              "home_route" => home_route,
              "home_url" => home_url,
              "routes" => { "home" => home_route }
            }.merge(website_data).tap do |website|
              website["analytics"] = analytics_data(config.analytics) unless config.analytics.provider.empty?
            end
          }
        )
      end

      def tags_page(tag_groups, config, system_theme_data, home_route, home_url)
        system_page(
          config,
          "/tags/",
          "Tags",
          "tags",
          system_theme_data,
          { "tag_groups" => tag_groups },
          home_route: home_route,
          home_url: home_url
        )
      end

      def analytics_data(analytics)
        {
          "provider" => analytics.provider,
          "identifier" => analytics.identifier,
          "load" => analytics.load
        }
      end

      def content_security_data(content_security, config)
        media_sources = Array(content_security&.media_sources).dup
        frame_sources = Array(content_security&.frame_sources).dup
        script_sources = Array(content_security&.script_sources).dup
        connect_sources = Array(content_security&.connect_sources).dup
        if config.analytics.load
          case config.analytics.provider
          when "cloudflare"
            script_sources << "https://static.cloudflareinsights.com"
            connect_sources << "https://cloudflareinsights.com"
          when "google"
            script_sources << "https://www.googletagmanager.com"
            connect_sources.concat(%w[
              https://*.analytics.google.com
              https://*.google-analytics.com
              https://www.googletagmanager.com
            ])
          end
        end
        {
          "media_sources" => media_sources.uniq.sort,
          "frame_sources" => frame_sources.uniq.sort,
          "script_sources" => script_sources.uniq.sort,
          "connect_sources" => connect_sources.uniq.sort
        }
      end

      def build_tag_groups(notes, anchors, config)
        groups = Hash.new { |hash, key| hash[key] = [] }
        notes.each { |note| Array(note.properties["tags"]).each { |tag| groups[tag] << note } }
        groups.keys.sort.map do |tag|
          {
            "name" => topic_label({ "kind" => "tag", "name" => tag }, config),
            "anchor" => anchors.fetch(topic_identity("name" => tag)),
            "notes" => groups.fetch(tag).sort_by(&:id).map { |note| system_note_card(note, config) }
          }
        end
      end

      def build_topic_groups(notes, anchors, config)
        groups = {}
        notes.each do |note|
          topics_for(note, config).uniq { |topic| topic_identity(topic) }.each do |topic|
            identity = topic_identity(topic)
            groups[identity] ||= { "topic" => topic, "notes" => [] }
            groups.fetch(identity).fetch("notes") << note
          end
        end

        groups.map do |identity, group|
          topic = group.fetch("topic")
          {
            "name" => topic_label(topic, config),
            "anchor" => anchors.fetch(identity),
            "url" => topic["url"],
            "notes" => group.fetch("notes").sort_by(&:id).map { |note| system_note_card(note, config) }
          }
        end
      end

      def summarize_topics(topic_groups)
        topic_groups.map do |group|
          group.slice("name", "anchor", "url").merge("count" => group.fetch("notes").length).compact
        end.sort_by { |topic| [-topic.fetch("count"), topic.fetch("name").downcase, topic.fetch("name")] }
      end

      def taxonomy_for(notes, config)
        return { "anchors" => {}, "groups" => [], "summaries" => [] } unless config.features.fetch("tags")

        anchors = topic_anchor_map(notes, config)
        groups = build_topic_groups(notes, anchors, config)
        {
          "anchors" => anchors,
          "groups" => build_tag_groups(notes, anchors, config),
          "summaries" => summarize_topics(groups)
        }
      end

      def timeline_for(notes, config)
        daily = config.blog["timeline_granularity"] == "day"
        counts = Hash.new(0)
        notes.each do |note|
          date = ArchiveChronology.local_time(yield(note), config.blog["utc_offset"])
          key = daily ? date&.slice(0, 10) : month_key(date)
          counts[key] += 1 if key
        end

        ArchiveChronology.timeline(counts, daily: daily)
      end

      def month_key(value)
        match = value.to_s.match(/\A(\d{4})-(0[1-9]|1[0-2])/)
        match && "#{match[1]}-#{match[2]}"
      end

      def redirect_page(landing_note, config, home_route, home_url)
        PageOutput.new(
          route: "/",
          content: "",
          data: {
            "layout" => "website-redirect",
            "title" => landing_note.title,
            "description" => landing_note.preview,
            "website" => {
              "kind" => "redirect",
              "theme" => config.theme,
              "features" => config.features,
              "route" => "/",
              "href" => config.url_builder.href("/"),
              "absolute_url" => config.url_builder.absolute_url("/"),
              "canonical_url" => config.url_builder.absolute_url(landing_note.route),
              "redirect_url" => home_url,
              "home_route" => home_route,
              "home_url" => home_url,
              "routes" => { "home" => home_route },
              "robots" => "noindex"
            }
          }
        )
      end

      def local_graphs(model, config)
        edges_by_note = Hash.new { |hash, id| hash[id] = [] }
        neighbours_by_note = Hash.new { |hash, id| hash[id] = {} }
        model.graph_edges.each do |edge|
          source = edge.fetch("source")
          target = edge.fetch("target")
          edges_by_note[source] << edge
          edges_by_note[target] << edge unless source == target
          neighbours_by_note[source][target] = true
          neighbours_by_note[target][source] = true
        end

        model.notes.each_with_object({}) do |note, graphs|
          neighbour_ids = neighbours_by_note[note.id].keys.reject { |id| id == note.id }
          next if neighbour_ids.empty?

          node_ids = [note.id, *neighbour_ids].sort
          nodes = node_ids.map do |id|
            target = model.notes_by_id.fetch(id)
            {
              "id" => id,
              "title" => target.title,
              "url" => config.url_builder.href(target.route),
              "degree" => model.graph_degrees.fetch(id)
            }
          end
          edges = edges_by_note[note.id].sort_by do |edge|
            [edge.fetch("source"), edge.fetch("target"), edge.fetch("kind")]
          end
          graphs[note.id] = { "current_id" => note.id, "nodes" => nodes, "edges" => edges }
        end
      end

      def context_present?(website)
        return true if website["local_graph"]
        return true if website.fetch("features").fetch("outline") && !website.fetch("outline").empty?
        return true unless Array(website["tag_summaries"]).empty?

        website.fetch("features").fetch("relations") &&
          %w[links backlinks embedded_by].any? { |key| !website.fetch(key).empty? }
      end

      def page_comments(note, config)
        comments = config.comments
        return unless comments.enabled && note.content_type == "post"
        return if note.properties["comments"] == false

        {
          "configured" => comments.configured,
          "repository" => comments.repository,
          "repository_id" => comments.repository_id,
          "category" => comments.category,
          "category_id" => comments.category_id,
          "term" => "website:post:#{note.id.delete_suffix('.md')}",
          "language" => comments.language,
          "load" => comments.load,
          "repository_url" => "https://github.com/#{comments.repository}",
          "discussion_url" => "https://github.com/#{comments.repository}/discussions"
        }
      end

      def not_found_page(config, system_theme_data, home_route, home_url)
        system_page(
          config,
          "/404.html",
          "Page not found",
          "404",
          system_theme_data,
          { "home_url" => home_url },
          home_route: home_route,
          home_url: home_url
        )
      end

      def system_note_card(note, config)
        { "id" => note.id, "title" => note.title, "url" => config.url_builder.href(note.route) }
      end

      def topic_anchors_for(note, taxonomy, config)
        anchors = taxonomy.fetch("anchors")
        topics_for(note, config).filter_map { |topic| anchors[topic_identity(topic)] }.uniq
      end

      def topic_anchor_map(notes, config)
        used = Hash.new(0)
        topics = notes.flat_map { |note| topics_for(note, config) }.uniq { |topic| topic_identity(topic) }
        topics.sort_by { |topic| [topic.fetch("name").downcase, topic.fetch("name"), topic["url"].to_s] }.to_h do |topic|
          base = config.url_builder.slug(topic.fetch("name"))
          used[base] += 1
          [topic_identity(topic), used[base] == 1 ? base : "#{base}-#{used[base]}"]
        end
      end

      def topics_for(note, config)
        topics = note.topics
        if config.theme == "minimal"
          seen_names = {}
          return topics.select do |topic|
            next true unless %w[tag category].include?(topic.fetch("kind"))

            name = topic_name_identity(topic)
            next false if seen_names[name]

            seen_names[name] = true
          end
        end

        topics.select { |topic| topic.fetch("kind") == "tag" }
      end

      def topic_label(topic, config)
        name = topic.fetch("name")
        return name unless topic.fetch("kind") == "tag"

        canonical = (config.site.tag_aliases || {}).fetch(name, name)
        (config.site.tag_labels || {}).fetch(canonical, name)
      end

      def blog_topic_links(note, topic_anchors, config)
        note.topics
          .select { |topic| %w[tag category].include?(topic.fetch("kind")) }
          .uniq { |topic| topic_name_identity(topic) }
          .filter_map do |topic|
            anchor = topic_anchors[topic_identity(topic)]
            { "name" => topic_label(topic, config), "anchor" => anchor } if anchor
          end
      end

      def topic_name_identity(topic)
        topic.fetch("name").unicode_normalize(:nfc).downcase(:fold)
      end

      def content_card(note, config)
        {
          "id" => note.id,
          "title" => note.title,
          "url" => config.url_builder.href(note.route),
          "published_at" => note.published_at,
          "summary" => note.properties["description"] || note.preview,
          "subtitle" => note.properties["subtitle"],
          "image" => note.image_url,
          "authors" => note.topics.select { |topic| topic.fetch("kind") == "author" },
          "tags" => Array(note.properties["tags"]),
          "source_url" => note.source_url,
          "source_title" => note.properties["source_title"],
          "date_basis" => note.properties["date_basis"]
        }
      end

      def tab_member_card(note, config)
        topics = note.topics
          .select { |topic| %w[tag category].include?(topic.fetch("kind")) }
          .uniq { |topic| topic_name_identity(topic) }
          .map do |topic|
            card = topic.slice("name", "url")
            card["name"] = topic_label(topic, config)
            card
          end
        content_card(note, config).merge(
          "content_type" => note.content_type,
          "topics" => topics
        )
      end

      def attach_custom_tab_theme_data(theme_data, model, config)
        config.navigation.custom_tabs.each do |tab|
          cards = tab.member_note_ids.filter_map do |id|
            note = model.notes_by_id[id]
            tab_member_card(note, config) if note
          end
          theme_data[tab.index_note_id] = theme_data.fetch(tab.index_note_id).merge(
            "tab_id" => tab.id,
            "tab_member_ids" => tab.member_note_ids,
            "tab_members" => cards
          )
        end
      end

      def related_article_cards(note, model, config)
        if Array(note.related).empty?
          return [] unless note.content_type == "post"
          return Array((model.recommendations || {})[note.id]).filter_map do |recommendation|
            next if Time.iso8601(recommendation.fetch("expires_at")) <= @recommendation_time
            target = model.notes_by_id[recommendation.fetch("path")]
            next unless target && target.id != note.id && target.content_type == "post"
            content_card(target, config).merge("recommendation_expires_at" => recommendation.fetch("expires_at"))
          end
        end
        Array(note.related).map do |related|
          target = model.notes_by_id.fetch(related.fetch("id"))
          content_card(target, config).merge(
            "title" => related.fetch("title"),
            "url" => related.fetch("url")
          )
        end
      end

      def topic_identity(topic)
        [topic.fetch("name"), topic["url"].to_s]
      end

      def h(value)
        text = value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
        CGI.escapeHTML(text.gsub(FrontMatter::XML_INVALID_CHARACTER, "\uFFFD"))
      end

      def attach_navigation(page, config)
        navigation = config.navigation
        website = page.data.fetch("website").dup
        repository = config.site.repository.to_s
        website["repository_url"] = "https://github.com/#{repository}" if repository.match?(/\A[\w.-]+\/[\w.-]+\z/)
        active_id = if website["kind"] == "note" || website.dig("theme_data", "tab_id")
          navigation.active_by_note_id[website["id"]]
        else
          navigation.items.find do |item|
            item.fetch("active_scope").fetch("routes").include?(page.route)
          end&.fetch("id")
        end
        website["navigation"] = navigation.items.map do |item|
          item.slice("id", "label", "url", "order")
        end
        website["active_navigation_id"] = active_id
        routes = navigation.items.to_h { |item| [item.fetch("id"), item.fetch("url")] }
        routes["home"] ||= website.fetch("home_url")
        routes["blog"] = config.url_builder.href("/") if config.home["layout"] == "archive"
        routes["portfolio"] = config.url_builder.href(navigation.portfolio.route) if navigation.portfolio
        routes["tags"] = config.url_builder.href("/tags/") if config.theme == "docs" && config.features.fetch("tags")
        routes["feed"] = config.url_builder.href("/feed.xml") if config.features.fetch("feed")
        website["routes"] = routes
        data = page.data.merge("website" => website)
        PageOutput.new(route: page.route, content: page.content, data: data)
      end
    end

    class Minimal < Presenter
      def render(model:, config:)
        # Locale projections share the build's clock snapshot for cards and dates.
        @recommendation_time = config.reference_time
        @favorite_cards = {}
        ledger_current_year = @recommendation_time.getlocal(config.blog["utc_offset"] || "+00:00").year
        posts = ordered_posts(model)
        paged = config.home["layout"] == "archive" || config.blog["page_size"]
        chronological = chronological_notes(posts)
        displayed = paged ? chronological : displayed_posts(posts)
        taxonomy = taxonomy_for(posts, config)
        documentation = config.navigation
        portfolio = documentation.portfolio
        portfolio_notes = portfolio ? portfolio.project_note_ids.map { |id| model.notes_by_id.fetch(id) } : []
        portfolio_taxonomy = taxonomy_for(portfolio_notes, config)
        portfolio_projects = portfolio_project_cards(portfolio_notes, config, portfolio_taxonomy)
        portfolio_theme_data = {
          "portfolio_projects" => portfolio_projects,
          "portfolio_topic_summaries" => portfolio_taxonomy.fetch("summaries"),
          "portfolio_topic_filter_count" => portfolio_projects.length
        }
        portfolio_projects_by_id = portfolio_projects.to_h { |project| [project.fetch("id"), project] }
        linked_docs = documentation.docs_note_ids.filter_map { |id| model.notes_by_id[id] }
        linked_doc_positions = linked_docs.each_with_index.to_h { |note, index| [note.id, index] }
        post_positions = posts.each_with_index.to_h { |post, index| [post.id, index] }
        theme_data = model.notes.to_h do |note|
          post_index = post_positions[note.id]
          doc_index = linked_doc_positions[note.id]
          project = portfolio_projects_by_id[note.id]
          data = {
            "archive_groups" => [],
            "docs_tree" => note.content_type == "doc" ? documentation.docs_tree : [],
            "docs_home_url" => documentation.docs_home_url,
            "related_articles" => related_article_cards(note, model, config),
            "previous" => sequence_card(
              note,
              post_index,
              doc_index,
              posts,
              linked_docs,
              -1,
              config,
              taxonomy
            ),
            "next" => sequence_card(
              note,
              post_index,
              doc_index,
              posts,
              linked_docs,
              1,
              config,
              taxonomy
            )
          }
          data["portfolio_topics"] = project.fetch("topics") if project
          [
            note.id,
            data
          ]
        end
        system_theme_data = {
          "archive_groups" => [],
          "docs_tree" => documentation.docs_tree,
          "docs_home_url" => documentation.docs_home_url,
          "previous" => nil,
          "next" => nil
        }
        root_path = model.directory_index_paths&.fetch(".", nil)
        root = root_path && model.notes_by_id[root_path]
        home_modules = home_theme_data(displayed, config, taxonomy)
        theme_data[root.id] = theme_data.fetch(root.id).merge(home_modules) if root
        if portfolio&.index_note_id
          theme_data[portfolio.index_note_id] = theme_data.fetch(portfolio.index_note_id).merge(
            portfolio_theme_data
          )
        end
        attach_custom_tab_theme_data(theme_data, model, config)
        tab_archive_files = attach_tab_archives(theme_data, model, config, taxonomy, ledger_current_year: ledger_current_year)
        authored_root_route = model.notes.any? { |note| note.route == "/" }
        home = home_page(displayed, config, system_theme_data, taxonomy) if !root && !authored_root_route && displayed.any? && config.home["layout"] != "archive"
        archive_data = (paged || config.features.fetch("favorites")) && PagedArchive.build(chronological.map { |post| note_card(post, config, taxonomy) }, config, postings: !!paged, tab_sources: home_tab_sources(model, config))
        if archive_data && paged
          groups = archive_data.fetch("archive_groups")
          timeline = archive_data.fetch("timeline")
        else
          groups = archive_groups(displayed, config, taxonomy)
          timeline = timeline_for(displayed, config, &:published_at)
        end
        blog = if (displayed.any? || config.home["layout"] == "archive") && !(root && config.home["layout"] == "archive")
          system_page(
            config,
            config.home["layout"] == "archive" ? "/" : "/blog/",
            config.home["layout"] == "archive" ? config.site.title : navigation_label(config, "blog", "Blog"),
            "blog-index",
            system_theme_data,
            {
              "archive_groups" => groups,
              "ledger_current_year" => ledger_current_year,
              "topic_summaries" => taxonomy.fetch("summaries"),
              "topic_filter_count" => displayed.length,
              "timeline" => timeline,
              "archive" => paged && archive_data && archive_data.fetch("archive"),
              "ledger_group_by" => config.blog.fetch("ledger_group_by")
            },
            home_route: "/",
            home_url: config.url_builder.href("/")
          )
        end
        portfolio_page = if portfolio && !portfolio.index_note_id
          system_page(
            config,
            portfolio.route,
            navigation_label(config, "portfolio", "Portfolio"),
            "portfolio-index",
            system_theme_data,
            portfolio_theme_data,
            home_route: "/",
            home_url: config.url_builder.href("/")
          )
        end
        theme_pages = [home, blog, portfolio_page].compact
        root_route_claimed = authored_root_route || theme_pages.any? { |page| page.route == "/" }
        landing_note = nil
        home_route = "/"
        unless root || home || root_route_claimed
          destination = config.navigation.items.find { |item| item.fetch("id") != "favorites" }
          if !destination && portfolio
            destination = {
              "id" => "portfolio",
              "label" => navigation_label(config, "portfolio", "Portfolio"),
              "url" => config.url_builder.href(portfolio.route)
            }
          end
          if destination
            home_route = destination.fetch("url").delete_prefix(config.url_builder.baseurl)
            theme_pages << redirect_to(destination, config)
          else
            landing_note = fallback_landing_note(model.notes)
            home_route = landing_note.route if landing_note
          end
        end
        if config.features.fetch("favorites")
          theme_pages << system_page(config, "/favorites/", navigation_label(config, "favorites", "Favorites"), "blog-index", system_theme_data,
            { "archive" => archive_data.fetch("archive"), "archive_groups" => [], "timeline" => archive_data.fetch("timeline"),
              "favorites" => true, "ledger_group_by" => "day", "ledger_current_year" => ledger_current_year },
            home_route: home_route, website_data: { "robots" => "noindex", "canonical_url" => config.url_builder.absolute_url(home_route) })
        end
        project(
          model: model,
          config: config,
          landing_note: landing_note,
          home_route: home_route,
          note_theme_data: theme_data,
          theme_pages: theme_pages,
          system_theme_data: system_theme_data,
          taxonomy: taxonomy,
          feed_notes: posts,
          shared_files: (archive_data ? archive_data.fetch("files") : []) + tab_archive_files
        ) do |note, output|
          if theme_data.fetch(note.id)["archive"]
            website = output.data.fetch("website").merge("kind" => "blog-index")
            PageOutput.new(route: output.route, content: output.content, data: output.data.merge("website" => website))
          elsif note.id == root&.id && config.home["layout"] == "archive"
            website = output.data.fetch("website").merge("kind" => "blog-index", "has_h1" => false,
              "theme_data" => system_theme_data.merge(archive_data.reject { |key, _| key == "files" }).merge("ledger_group_by" => config.blog.fetch("ledger_group_by"), "ledger_current_year" => ledger_current_year))
            PageOutput.new(route: output.route, content: "", data: output.data.merge("website" => website))
          else
            note.id == root&.id ? authored_home_page(output) : output
          end
        end
      end

      private

      def fallback_landing_note(notes)
        visible = notes.reject(&:nav_exclude)
        candidates = visible.empty? ? notes : visible
        # Source paths keep the same landing note when titles are translated.
        candidates.min_by { |note| [note.nav_order.nil? ? 1 : 0, note.nav_order || 0, note.id] }
      end

      def home_tab_sources(model, config)
        return [] unless config.home["layout"] == "archive" && config.home["hide_tab_sources"]
        # Theme rendering precedes BuildFailure, so invalid configuration must
        # still reach the compiler's missing-source-facet diagnostic.
        return [] unless config.blog.fetch("facets")["source"]
        archive_tabs(model, config).flat_map do |_tab, root|
          PagedArchive.facet_values(root.properties.dig("tab", "topics"), config).fetch("source")
        end.uniq.sort
      end

      def archive_tabs(model, config)
        config.navigation.custom_tabs.filter_map do |tab|
          root = model.notes_by_id.fetch(tab.index_note_id)
          [tab, root] if root.properties.dig("tab", "layout") == "archive"
        end
      end

      def attach_tab_archives(theme_data, model, config, taxonomy, ledger_current_year:)
        archive_tabs(model, config).flat_map do |tab, _root|
          members = tab.member_note_ids.map { |id| model.notes_by_id.fetch(id) }
          chronological = chronological_notes(members)
          archive = PagedArchive.build(chronological.map { |note| note_card(note, config, taxonomy) }, config, scope: tab.id)
          theme_data[tab.index_note_id] = theme_data.fetch(tab.index_note_id)
            .reject { |key, _| key == "tab_members" }
            .merge(archive.reject { |key, _| key == "files" })
            .merge("ledger_group_by" => config.blog.fetch("ledger_group_by"),
              "ledger_current_year" => ledger_current_year,
              "previous" => nil, "next" => nil)
          archive.fetch("files")
        end
      end

      def ordered_posts(model)
        chronological_notes(model.notes.select { |note| note.content_type == "post" }, newest_first: false)
      end

      def displayed_posts(posts)
        displayed = chronological_notes(posts)
        pinned, remaining = displayed.partition { |note| note.properties["pinned"] == true }
        pinned + remaining
      end

      def archive_groups(posts, config, taxonomy)
        cards = posts.map do |note|
          card = note_card(note, config, taxonomy)
          card.merge(PagedArchive.calendar_fields(card["published_at"]))
        end
        PagedArchive.groups(cards, config)
      end

      def home_theme_data(posts, config, taxonomy)
        {
          "recent_posts" => posts.first(config.home.fetch("recent_posts_limit")).map { |post| note_card(post, config, taxonomy) },
          "view_all_url" => config.url_builder.href("/blog/"),
          "contacts" => config.contacts,
          "topic_summaries" => taxonomy.fetch("summaries")
        }
      end

      def home_page(posts, config, system_theme_data, taxonomy)
        system_page(
          config,
          "/",
          navigation_label(config, "home", "Home"),
          "home",
          system_theme_data,
          home_theme_data(posts, config, taxonomy),
          home_route: "/",
          home_url: config.url_builder.href("/")
        )
      end

      def authored_home_page(page)
        website = page.data.fetch("website").merge("kind" => "home")
        PageOutput.new(route: "/", content: page.content, data: page.data.merge("website" => website))
      end

      def redirect_to(item, config)
        url = item.fetch("url")
        PageOutput.new(
          route: "/",
          content: "",
          data: {
            "layout" => "website-redirect",
            "title" => item.fetch("label"),
            "description" => config.site.description.to_s,
            "website" => {
              "kind" => "redirect",
              "redirect_navigation_id" => item.fetch("id"),
              "theme" => config.theme,
              "features" => config.features,
              "route" => "/",
              "href" => config.url_builder.href("/"),
              "absolute_url" => config.url_builder.absolute_url("/"),
              "canonical_url" => config.url_builder.origin.empty? ? nil : "#{config.url_builder.origin}#{url}",
              "redirect_url" => url,
              "home_route" => "/",
              "home_url" => config.url_builder.href("/"),
              "routes" => { "home" => "/" },
              "robots" => "noindex"
            }
          }
        )
      end

      def sequence_card(note, post_index, doc_index, posts, docs, offset, config, taxonomy)
        collection, index = note.content_type == "post" ? [posts, post_index] : [docs, doc_index]
        return unless index

        target_index = index + offset
        return if target_index.negative? || target_index >= collection.length

        target = collection.fetch(target_index)
        note.content_type == "post" ? note_card(target, config, taxonomy) : docs_card(target, config)
      end

      def docs_card(note, config)
        {
          "id" => note.id,
          "title" => note.title,
          "url" => !note.nav_exclude ? config.url_builder.href(note.route) : nil,
          "content_type" => note.content_type
        }
      end

      def navigation_label(config, id, fallback)
        config.navigation.items.find { |item| item.fetch("id") == id }&.fetch("label") ||
          config.site.navigation&.dig(id, "label") || fallback
      end

      def portfolio_project_cards(notes, config, taxonomy)
        notes.map do |note|
          topics = portfolio_topics_for(note, config, taxonomy)
          card = {
            "id" => note.id,
            "title" => note.title,
            "url" => config.url_builder.href(note.route),
            "image" => note.image_url,
            "summary" => note.properties["description"] || note.preview,
            "topics" => topics,
            "topic_anchors" => topics.map { |topic| topic.fetch("anchor") }
          }
          card["repository_url"] = note.source_links.fetch("repository") if note.source_links["repository"]
          card
        end
      end

      def portfolio_topics_for(note, config, taxonomy)
        anchors = taxonomy.fetch("anchors")
        topics_for(note, config).uniq { |topic| topic_identity(topic) }.filter_map do |topic|
          anchor = anchors[topic_identity(topic)]
          next unless anchor

          topic.slice("name", "url").merge("name" => topic_label(topic, config), "anchor" => anchor).compact
        end
      end

      def chronology_key(value)
        [0, DateTime.iso8601(value.to_s).new_offset(0).ajd]
      rescue Date::Error
        [1, value.to_s]
      end

      def chronological_notes(notes, newest_first: true)
        dated, undated = notes.partition(&:published_at)
        dated = dated.sort_by { |note| [chronology_key(note.published_at), note.id] }
        (newest_first ? dated.reverse : dated) + undated.sort_by(&:id)
      end

      def note_card(note, config, taxonomy)
        date = ArchiveChronology.local_time(note.published_at, config.blog["utc_offset"])
        content_card(note, config).merge(
          "markdown_url" => config.url_builder.href(PublishedMarkdown.route(note.route)),
          "published_at" => date,
          "topics" => blog_topic_links(note, taxonomy.fetch("anchors"), config),
          "topic_anchors" => topic_anchors_for(note, taxonomy, config),
          "filter_month" => month_key(date),
          "filter_day" => date&.slice(0, 10),
          "favorite_card" => config.features.fetch("favorites") ? favorite_card(note, config) : nil
        )
      end
    end

    class Docs < Presenter
      def render(model:, config:)
        # Locale projections share the build's clock snapshot for cards and dates.
        @recommendation_time = config.reference_time
        @favorite_cards = {}
        taxonomy = taxonomy_for(model.notes, config)
        navigation = config.navigation
        docs_home_url = navigation.docs_home_url
        linked = navigation.docs_note_ids.filter_map { |id| model.notes_by_id[id] }
        root_path = model.directory_index_paths&.fetch(".", nil)
        landing = (root_path && model.notes_by_id[root_path]) || linked.first || model.notes.first
        linked_positions = linked.each_with_index.to_h { |linked_note, index| [linked_note.id, index] }
        theme_data = model.notes.to_h do |note|
          index = linked_positions[note.id]
          [
            note.id,
            {
              "docs_tree" => navigation.docs_tree,
              "docs_home_url" => docs_home_url,
              "related_articles" => related_article_cards(note, model, config),
              "previous" => index && index.positive? ? docs_card(linked[index - 1], config) : nil,
              "next" => index && index < linked.length - 1 ? docs_card(linked[index + 1], config) : nil
            }
          ]
        end
        attach_custom_tab_theme_data(theme_data, model, config)
        system_theme_data = {
          "docs_tree" => navigation.docs_tree,
          "docs_home_url" => docs_home_url,
          "previous" => nil,
          "next" => nil
        }
        project(
          model: model,
          config: config,
          landing_note: landing,
          note_theme_data: theme_data,
          theme_pages: [],
          system_theme_data: system_theme_data,
          taxonomy: taxonomy,
          feed_notes: model.notes
        )
      end

      private

      def docs_card(note, config, linked: true)
        {
          "id" => note.id,
          "title" => note.title,
          "url" => linked && !note.nav_exclude ? config.url_builder.href(note.route) : nil,
          "content_type" => note.content_type
        }
      end
    end
  end
end
