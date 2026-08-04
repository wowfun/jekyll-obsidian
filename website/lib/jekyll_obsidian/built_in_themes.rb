# frozen_string_literal: true

require "cgi/escape"
require "date"

module JekyllObsidian
  # The only internal theme seam. Each built-in adapter consumes the same
  # immutable PublishedSiteModel and returns a complete ThemeOutput through a
  # single render interface.
  module BuiltInThemes
    IDS = %w[blog docs digital-garden].freeze
    ALWAYS_RESERVED_NAMESPACES = %w[
      /404.html /sitemap.xml /assets/website /assets/vault
    ].freeze
    module_function

    def resolve(id)
      case id
      when "blog" then Blog.new
      when "docs" then Docs.new
      when "digital-garden" then DigitalGarden.new
      else
        raise ArgumentError, "unknown built-in theme #{id.inspect}"
      end
    end

    class Presenter
      private

      def project(model:, config:, note_theme_data:, theme_pages:, system_theme_data:, tag_notes:, feed_notes:, shared_files: [])
        tag_anchors = config.features.fetch("tags") ? tag_anchor_map(tag_notes, config.url_builder) : {}
        local_graphs = config.features.fetch("graph") ? local_graphs(model, config) : {}
        pages = model.notes.map do |note|
          note_page(
            note,
            config,
            note_theme_data.fetch(note.id),
            tag_anchors,
            local_graphs[note.id]
          )
        end
        pages.concat(theme_pages)
        pages << tags_page(tag_notes, tag_anchors, config, system_theme_data) if config.features.fetch("tags")
        pages << not_found_page(config, system_theme_data)

        artifacts = []
        artifacts << "catalog" if config.features.fetch("previews")
        artifacts << "graph" if config.features.fetch("graph")
        artifacts << "search" if config.features.fetch("search")
        artifacts << "sitemap"
        artifacts << "feed" if config.features.fetch("feed")

        namespaces = ALWAYS_RESERVED_NAMESPACES.dup
        namespaces << "/feed.xml" if config.features.fetch("feed")

        ThemeOutput.new(
          pages: pages,
          artifacts: artifacts,
          shared_files: shared_files,
          site_data: {
            "website_repository_url" => repository_url(config)
          }.compact,
          feed_note_ids: feed_notes.sort_by(&:id).map(&:id),
          reserved_namespaces: namespaces
        )
      end

      def note_page(note, config, theme_data, tag_anchors, local_graph)
        properties = note.properties
        comments = page_comments(note, config)
        website = {
          "kind" => "note",
          "id" => note.id,
          "content_type" => note.content_type,
          "published_at" => note.published_at,
          "route" => note.route,
          "href" => config.url_builder.href(note.route),
          "absolute_url" => config.url_builder.absolute_url(note.route),
          "aliases" => Array(properties["aliases"]),
          "tags" => Array(properties["tags"]),
          "cssclasses" => Array(properties["cssclasses"]),
          "created" => note.created,
          "updated" => note.updated,
          "has_h1" => note.has_h1,
          "source_links" => note.source_links,
          "theme" => config.theme,
          "features" => config.features.merge(note.feature_flags),
          "theme_data" => theme_data,
          "tag_links" => Array(note.properties["tags"]).filter_map do |tag|
            anchor = tag_anchors[tag]
            { "name" => tag, "anchor" => anchor } if anchor
          end,
          "outline" => note.outline,
          "links" => config.features.fetch("relations") ? note.links : [],
          "backlinks" => config.features.fetch("relations") ? note.backlinks : [],
          "embedded_by" => config.features.fetch("relations") ? note.embedded_by : []
        }
        website["local_graph"] = local_graph if local_graph
        website["has_context"] = context_present?(website)
        website["comments"] = comments if comments
        data = {
          "title" => note.title,
          "description" => properties["description"] || note.preview,
          "image" => note.image_url,
          "layout" => "website-#{config.theme}",
          "website" => website
        }.compact
        PageOutput.new(route: note.route, content: note.content, data: data)
      end

      def system_page(config, route, title, kind, system_theme_data, theme_data = {})
        PageOutput.new(
          route: route,
          content: "",
          data: {
            "layout" => "website-#{config.theme}",
            "title" => title,
            "description" => config.site.description.to_s,
            "website" => {
              "kind" => kind,
              "theme" => config.theme,
              "features" => config.features,
              "theme_data" => system_theme_data.merge(theme_data),
              "route" => route,
              "href" => config.url_builder.href(route),
              "absolute_url" => config.url_builder.absolute_url(route)
            }
          }
        )
      end

      def tags_page(notes, anchors, config, system_theme_data)
        groups = Hash.new { |hash, key| hash[key] = [] }
        notes.each { |note| Array(note.properties["tags"]).each { |tag| groups[tag] << note } }
        tag_groups = groups.keys.sort.map do |tag|
          {
            "name" => tag,
            "anchor" => anchors.fetch(tag),
            "notes" => groups.fetch(tag).sort_by(&:id).map { |note| system_note_card(note, config) }
          }
        end
        system_page(config, "/tags/", "Tags", "tags", system_theme_data, "tag_groups" => tag_groups)
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

        model.notes.to_h do |note|
          node_ids = [note.id, *neighbours_by_note[note.id].keys].uniq.sort
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
          [note.id, { "current_id" => note.id, "nodes" => nodes, "edges" => edges }]
        end
      end

      def context_present?(website)
        return true if website["local_graph"]
        return true if website.fetch("features").fetch("outline") && !website.fetch("outline").empty?

        website.fetch("features").fetch("relations") &&
          %w[links backlinks embedded_by].any? { |key| !website.fetch(key).empty? }
      end

      def repository_url(config)
        repository = config.site.repository.to_s
        return unless repository.match?(/\A[\w.-]+\/[\w.-]+\z/)

        "https://github.com/#{repository}"
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

      def not_found_page(config, system_theme_data)
        system_page(
          config,
          "/404.html",
          "Page not found",
          "404",
          system_theme_data,
          "home_url" => config.url_builder.href("/")
        )
      end

      def system_note_card(note, config)
        { "id" => note.id, "title" => note.title, "url" => config.url_builder.href(note.route) }
      end

      def tag_anchor_map(notes, url_builder)
        used = Hash.new(0)
        notes.flat_map { |note| Array(note.properties["tags"]) }.uniq.sort.to_h do |tag|
          base = url_builder.slug(tag)
          used[base] += 1
          [tag, used[base] == 1 ? base : "#{base}-#{used[base]}"]
        end
      end

      def h(value)
        text = value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
        CGI.escapeHTML(text.gsub(FrontMatter::XML_INVALID_CHARACTER, "\uFFFD"))
      end
    end

    class Blog < Presenter
      def render(model:, config:)
        posts = ordered_posts(model)
        displayed = displayed_posts(posts)
        post_positions = posts.each_with_index.to_h { |post, index| [post.id, index] }
        theme_data = model.notes.to_h do |note|
          index = post_positions[note.id]
          [
            note.id,
            {
              "recent_posts" => note.id == "index.md" ? displayed.first(10).map { |post| note_card(post, config) } : [],
              "archive_groups" => [],
              "previous" => index && index.positive? ? note_card(posts[index - 1], config) : nil,
              "next" => index && index < posts.length - 1 ? note_card(posts[index + 1], config) : nil
            }
          ]
        end
        system_theme_data = {
          "recent_posts" => [],
          "archive_groups" => [],
          "previous" => nil,
          "next" => nil
        }
        groups = archive_groups(displayed, config)
        archive = system_page(
          config,
          "/archive/",
          "Archive",
          "archive",
          system_theme_data,
          "archive_groups" => groups
        )
        project(
          model: model,
          config: config,
          note_theme_data: theme_data,
          theme_pages: [archive],
          system_theme_data: system_theme_data,
          tag_notes: posts,
          feed_notes: posts
        )
      end

      private

      def ordered_posts(model)
        dated, undated = model.notes.select { |note| note.content_type == "post" }.partition(&:published_at)
        dated.sort_by! { |note| [chronology_key(note.published_at), note.id] }
        undated.sort_by!(&:id)
        dated + undated
      end

      def displayed_posts(posts)
        dated, undated = posts.partition(&:published_at)
        dated.reverse + undated
      end

      def archive_groups(posts, config)
        posts.group_by { |note| note.published_at ? note.published_at[0, 4] : "Undated" }.map do |label, grouped|
          { "label" => label, "posts" => grouped.map { |note| note_card(note, config) } }
        end
      end

      def chronology_key(value)
        [0, DateTime.iso8601(value.to_s).new_offset(0).ajd]
      rescue Date::Error
        [1, value.to_s]
      end

      def note_card(note, config)
        {
          "id" => note.id,
          "title" => note.title,
          "url" => config.url_builder.href(note.route),
          "published_at" => note.published_at,
          "tags" => Array(note.properties["tags"])
        }
      end
    end

    class Docs < Presenter
      def render(model:, config:)
        navigation = docs_navigation(model, config)
        docs_home_url = docs_home_url(model, navigation, config)
        linked = navigation.fetch("linked_notes")
        linked_positions = linked.each_with_index.to_h { |linked_note, index| [linked_note.id, index] }
        theme_data = model.notes.to_h do |note|
          index = linked_positions[note.id]
          [
            note.id,
            {
              "docs_tree" => note.id == "index.md" ? navigation.fetch("tree") : docs_branch(navigation.fetch("tree"), note.id),
              "docs_tree_url" => config.url_builder.href("/assets/website/docs-navigation.html"),
              "docs_index_url" => config.url_builder.href("/"),
              "docs_home_url" => docs_home_url,
              "breadcrumbs" => note.content_type == "doc" ? docs_breadcrumbs(note, model, config) : [],
              "previous" => index && index.positive? ? docs_card(linked[index - 1], config) : nil,
              "next" => index && index < linked.length - 1 ? docs_card(linked[index + 1], config) : nil
            }
          ]
        end
        system_theme_data = {
          "docs_tree" => [],
          "docs_tree_url" => config.url_builder.href("/assets/website/docs-navigation.html"),
          "docs_index_url" => config.url_builder.href("/"),
          "docs_home_url" => docs_home_url,
          "breadcrumbs" => [],
          "previous" => nil,
          "next" => nil
        }
        project(
          model: model,
          config: config,
          note_theme_data: theme_data,
          theme_pages: [],
          system_theme_data: system_theme_data,
          tag_notes: model.notes,
          feed_notes: model.notes,
          shared_files: [GeneratedFile.new(
            route: "/assets/website/docs-navigation.html",
            content: docs_tree_html(navigation.fetch("tree")),
            media_type: "text/html"
          )]
        )
      end

      private

      def docs_navigation(model, config)
        root = { path: "", name: "", index: nil, notes: [], children: {} }
        model.notes.select { |note| note.content_type == "doc" }.sort_by(&:id).each do |note|
          directory = File.dirname(note.id)
          folder = root
          unless directory == "."
            current_path = []
            directory.split("/").each do |segment|
              current_path << segment
              folder[:children][segment] ||= {
                path: current_path.join("/"), name: segment, index: nil, notes: [], children: {}
              }
              folder = folder[:children].fetch(segment)
            end
          end
          if File.basename(note.id) == "index.md"
            folder[:index] = note
          else
            folder[:notes] << note
          end
        end

        tree = render_folder_contents(root, config)
        linked = []
        walk = lambda do |nodes|
          nodes.each do |node|
            linked << model.notes_by_id.fetch(node.fetch("id")) if node["url"] && model.notes_by_id.key?(node.fetch("id"))
            walk.call(node.fetch("children"))
          end
        end
        walk.call(tree)
        { "tree" => tree, "linked_notes" => linked }
      end

      def docs_home_url(model, navigation, config)
        configured_root = config.content.fetch("directories").fetch("doc").filter_map do |directory|
          candidate = model.notes_by_id["#{directory}/index.md"]
          candidate if candidate&.content_type == "doc" && !candidate.nav_exclude
        end.first
        landing = configured_root || navigation.fetch("linked_notes").first
        landing ? config.url_builder.href(landing.route) : nil
      end

      def render_folder_contents(folder, config)
        nodes = folder.fetch(:notes).reject(&:nav_exclude).map { |note| docs_node(note, [], config) }
        folder.fetch(:children).values.each do |child|
          children = render_folder_contents(child, config)
          index_note = child.fetch(:index)
          next if children.empty? && (!index_note || index_note.nav_exclude)

          node = if index_note
            docs_node(index_note, children, config, linked: !index_note.nav_exclude)
          else
            {
              "id" => "folder:#{child.fetch(:path)}",
              "title" => humanize_path_segment(child.fetch(:name)),
              "url" => nil,
              "content_type" => "doc",
              "children" => children,
              "nav_order" => nil
            }
          end
          nodes << node
        end
        nodes.sort_by { |node| docs_sort_key(node) }
      end

      def docs_node(note, children, config, linked: true)
        {
          "id" => note.id,
          "title" => note.title,
          "url" => linked ? config.url_builder.href(note.route) : nil,
          "content_type" => note.content_type,
          "children" => children,
          "nav_order" => note.nav_order
        }
      end

      def docs_sort_key(node)
        order = node["nav_order"]
        [order.nil? ? 1 : 0, order || 0, node.fetch("title").downcase, node.fetch("id")]
      end

      def docs_branch(nodes, note_id)
        nodes.filter_map do |node|
          children = docs_branch(node.fetch("children"), note_id)
          next unless node.fetch("id") == note_id || !children.empty?

          node.merge("children" => children)
        end
      end

      def docs_tree_html(nodes)
        items = nodes.map do |node|
          label = if node["url"]
            %(<a href="#{h(node.fetch('url'))}">#{h(node.fetch('title'))}</a>)
          else
            %(<span>#{h(node.fetch('title'))}</span>)
          end
          children = node.fetch("children").empty? ? "" : docs_tree_html(node.fetch("children"))
          %(<li class="docs-tree__item">#{label}#{children}</li>)
        end.join
        %(<ul class="docs-tree__list">#{items}</ul>)
      end

      def docs_card(note, config, linked: true)
        {
          "id" => note.id,
          "title" => note.title,
          "url" => linked && !note.nav_exclude ? config.url_builder.href(note.route) : nil,
          "content_type" => note.content_type
        }
      end

      def docs_breadcrumbs(note, model, config)
        parts = File.dirname(note.id) == "." ? [] : File.dirname(note.id).split("/")
        crumbs = []
        parts.each_index do |index|
          directory = parts[0..index].join("/")
          ancestor = model.notes_by_id["#{directory}/index.md"]
          if ancestor&.content_type == "doc"
            crumbs << docs_card(ancestor, config)
          else
            crumbs << {
              "id" => "folder:#{directory}",
              "title" => humanize_path_segment(parts[index]),
              "url" => nil,
              "content_type" => "doc"
            }
          end
        end
        crumbs << docs_card(note, config) unless crumbs.any? { |crumb| crumb.fetch("id") == note.id }
        crumbs
      end

      def humanize_path_segment(segment)
        segment.tr("-_", " ").split.map(&:capitalize).join(" ")
      end
    end

    class DigitalGarden < Presenter
      def render(model:, config:)
        theme_data = model.notes.to_h { |note| [note.id, {}] }
        items = model.notes.sort_by { |note| [note.title.downcase, note.id] }
          .map { |note| system_note_card(note, config) }
        notes_page = system_page(
          config,
          "/notes/",
          "All notes",
          "notes",
          {},
          "notes" => items
        )
        project(
          model: model,
          config: config,
          note_theme_data: theme_data,
          theme_pages: [notes_page],
          system_theme_data: {},
          tag_notes: model.notes,
          feed_notes: model.notes
        )
      end
    end
  end
end
