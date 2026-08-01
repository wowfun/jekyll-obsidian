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
      /404.html /sitemap.xml /assets/obsidian /assets/vault
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

      def project(model:, config:, note_theme_data:, theme_pages:, system_theme_data:, tag_notes:, feed_notes:)
        tag_anchors = config.features.fetch("tags") ? tag_anchor_map(tag_notes, config.url_builder) : {}
        pages = model.notes.map do |note|
          note_page(
            note,
            config,
            note_theme_data.fetch(note.id),
            tag_anchors
          )
        end
        pages.concat(theme_pages)
        pages << tags_page(tag_notes, tag_anchors, config, system_theme_data) if config.features.fetch("tags")
        pages << graph_page(model, config, system_theme_data) if config.features.fetch("graph")
        pages << not_found_page(config, system_theme_data)

        artifacts = ["catalog"]
        artifacts << "graph" if config.features.fetch("graph")
        artifacts << "search" if config.features.fetch("search")
        artifacts << "sitemap"
        artifacts << "feed" if config.features.fetch("feed")

        namespaces = ALWAYS_RESERVED_NAMESPACES.dup
        namespaces << "/feed.xml" if config.features.fetch("feed")

        ThemeOutput.new(
          pages: pages,
          artifacts: artifacts,
          feed_note_ids: feed_notes.sort_by(&:id).map(&:id),
          reserved_namespaces: namespaces
        )
      end

      def note_page(note, config, theme_data, tag_anchors)
        obsidian = note.base_data.fetch("obsidian").merge(
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
        )
        data = note.base_data.merge(
          "layout" => "obsidian-#{config.theme}",
          "obsidian" => obsidian
        )
        PageOutput.new(route: note.route, content: note.content, data: data)
      end

      def system_page(config, route, title, content, kind, system_theme_data, theme_data = {})
        PageOutput.new(
          route: route,
          content: content,
          data: {
            "layout" => "obsidian-#{config.theme}",
            "title" => title,
            "description" => config.site.description.to_s,
            "obsidian" => {
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
        body = groups.keys.sort.map do |tag|
          links = groups.fetch(tag).sort_by(&:id).map do |note|
            %(<li><a href="#{h(config.url_builder.href(note.route))}">#{h(note.title)}</a></li>)
          end.join
          %(<section id="#{h(anchors.fetch(tag))}"><h2>#{h(tag)}</h2><ul>#{links}</ul></section>)
        end.join
        system_page(config, "/tags/", "Tags", %(<h1>Tags</h1>#{body}), "tags", system_theme_data)
      end

      def graph_page(model, config, system_theme_data)
        items = model.graph_edges.map do |edge|
          source = model.notes_by_id.fetch(edge.fetch("source"))
          target = model.notes_by_id.fetch(edge.fetch("target"))
          %(<li><a href="#{h(config.url_builder.href(source.route))}">#{h(source.title)}</a> #{h(edge.fetch("kind"))} <a href="#{h(config.url_builder.href(target.route))}">#{h(target.title)}</a> <span aria-label="count">&times;#{edge.fetch("count")}</span></li>)
        end.join
        content = %(<h1>Graph</h1><div data-graph><p class="graph-status" data-graph-status aria-live="polite">The interactive graph loads on this page.</p></div><details class="graph-fallback" open><summary>Accessible relation list</summary><ul>#{items}</ul></details>)
        system_page(config, "/graph/", "Graph", content, "graph", system_theme_data)
      end

      def not_found_page(config, system_theme_data)
        content = %(<h1>Page not found</h1><p>The requested page is not in this published site.</p><p><a href="#{h(config.url_builder.href("/"))}">Return home</a></p>)
        system_page(config, "/404.html", "Page not found", content, "404", system_theme_data)
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
          %(<h1>Archive</h1>),
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
              "docs_tree" => navigation.fetch("tree"),
              "docs_home_url" => docs_home_url,
              "breadcrumbs" => note.content_type == "doc" ? docs_breadcrumbs(note, model, config) : [],
              "previous" => index && index.positive? ? docs_card(linked[index - 1], config) : nil,
              "next" => index && index < linked.length - 1 ? docs_card(linked[index + 1], config) : nil
            }
          ]
        end
        system_theme_data = {
          "docs_tree" => navigation.fetch("tree"),
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
          feed_notes: model.notes
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
        items = model.notes.sort_by { |note| [note.title.downcase, note.id] }.map do |note|
          %(<li><a href="#{h(config.url_builder.href(note.route))}">#{h(note.title)}</a></li>)
        end.join
        notes_page = system_page(
          config,
          "/notes/",
          "All notes",
          %(<h1>All notes</h1><ul class="obsidian-index-list">#{items}</ul>),
          "notes",
          {}
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
