# frozen_string_literal: true

module JekyllObsidian
  # Compiler-owned navigation projection. It turns content types, authored
  # navigation declarations, and folder configuration into one immutable model
  # consumed by every presentation surface.
  module SiteNavigation
    PortfolioProjection = ImmutableRecord.define(
      :path,
      :route,
      :index_note_id,
      :project_note_ids
    )

    Result = ImmutableRecord.define(
      :items,
      :active_by_note_id,
      :docs_tree,
      :docs_note_ids,
      :docs_home_url,
      :portfolio,
      :diagnostics
    )

    module_function

    def build(model:, settings:, content:, url_builder:, theme:)
      Builder.new(
        model: model,
        settings: settings,
        content: content,
        url_builder: url_builder,
        theme: theme
      ).build
    end

    class Builder
      def initialize(model:, settings:, content:, url_builder:, theme:)
        @model = model
        @settings = settings
        @content = content
        @url_builder = url_builder
        @theme = theme
        @diagnostics = []
      end

      def build
        documentation = documentation_navigation
        portfolio = @theme == "minimal" ? portfolio_projection : nil
        @portfolio_projection = portfolio
        items = @theme == "minimal" ? minimal_items(documentation, portfolio) : docs_items(documentation)
        items = validate_items(items)
        active = active_notes(items)

        Result.new(
          items: items,
          active_by_note_id: active,
          docs_tree: documentation.fetch("tree"),
          docs_note_ids: documentation.fetch("linked_notes").map(&:id),
          docs_home_url: documentation.fetch("home_url"),
          portfolio: portfolio,
          diagnostics: @diagnostics
        )
      end

      private

      def minimal_items(documentation, portfolio)
        items = []
        posts = @model.notes.select { |note| note.content_type == "post" }
        docs = @model.notes.select { |note| note.content_type == "doc" }
        root = @model.notes_by_id["index.md"]
        portfolio_owns_root_navigation = portfolio&.route == "/" && @settings.fetch("portfolio").fetch("visible")

        add_builtin(
          items,
          "home",
          "Home",
          @url_builder.href("/"),
          !portfolio_owns_root_navigation && (root || posts.any?),
          note_ids: root ? [root.id] : [],
          routes: ["/"]
        )
        add_builtin(
          items,
          "blog",
          "Blog",
          @url_builder.href("/blog/"),
          posts.any?,
          note_ids: posts.map(&:id),
          routes: ["/blog/"]
        )
        add_builtin(
          items,
          "docs",
          "Docs",
          documentation.fetch("home_url"),
          !documentation.fetch("linked_notes").empty?,
          note_ids: docs.map(&:id),
          routes: []
        )
        if portfolio
          add_builtin(
            items,
            "portfolio",
            "Portfolio",
            @url_builder.href(portfolio.route),
            true,
            note_ids: @portfolio_note_ids,
            routes: [portfolio.route]
          )
        end
        add_folder_items(items)
        add_page_items(items)
        items
      end

      def docs_items(documentation)
        items = []
        root = @model.notes_by_id["index.md"]
        docs = @model.notes.select { |note| note.content_type == "doc" }
        add_builtin(
          items,
          "home",
          "Overview",
          @url_builder.href("/"),
          !root.nil?,
          note_ids: root ? [root.id] : [],
          routes: ["/"]
        )
        add_builtin(
          items,
          "docs",
          "Documentation",
          documentation.fetch("home_url"),
          !documentation.fetch("linked_notes").empty?,
          note_ids: docs.map(&:id),
          routes: []
        )
        items
      end

      def add_builtin(items, id, default_label, route, has_content, note_ids:, routes:)
        setting = @settings.fetch(id)
        return unless setting.fetch("visible") && has_content && route

        items << {
          "id" => id,
          "label" => setting["label"] || default_label,
          "url" => route,
          "order" => setting.fetch("order"),
          "active_scope" => active_scope(note_ids, routes)
        }
      end

      def add_folder_items(items)
        seen = {}
        @settings.fetch("folders").each do |setting|
          path = setting.fetch("path")
          folded = path.downcase(:fold)
          portfolio_setting = @settings.fetch("portfolio")
          portfolio_path = @portfolio_projection && portfolio_setting.fetch("visible") && portfolio_setting.fetch("path")
          if portfolio_path && folded == portfolio_path.downcase(:fold)
            navigation_error(
              "duplicate_navigation_folder",
              "navigation folder conflicts with the built-in portfolio path",
              path
            )
            next
          end
          if seen.key?(folded)
            navigation_error("duplicate_navigation_folder", "navigation folder is configured more than once", path)
            next
          end
          seen[folded] = true

          notes = @model.notes.select do |note|
            note.content_type == "page" && (note.id == "#{path}/index.md" || note.id.start_with?("#{path}/"))
          end
          landing = notes.find { |note| note.id == "#{path}/index.md" && !note.nav_exclude }
          landing ||= notes.reject(&:nav_exclude).reject { |note| File.basename(note.id) == "index.md" }.min_by do |note|
            note_sort_key(note)
          end
          unless landing
            navigation_error(
              "empty_navigation_folder",
              "navigation folder must contain at least one visible published page",
              path
            )
            next
          end
          next unless setting.fetch("visible")

          id = "folder:#{path}"
          items << {
            "id" => id,
            "label" => setting["label"] || folder_label(path, notes),
            "url" => @url_builder.href(landing.route),
            "order" => setting.fetch("order"),
            "active_scope" => active_scope(notes.map(&:id), [])
          }
        rescue EncodingError
          navigation_error("invalid_navigation_folder", "navigation folder must contain valid Unicode", path)
        end
      end

      def add_page_items(items)
        @model.notes.sort_by(&:id).each do |note|
          authored = note.properties["navigation"]
          next unless authored

          unless note.content_type == "page"
            navigation_error(
              "invalid_page_navigation",
              "navigation frontmatter is only supported on content_type: page",
              note.id
            )
            next
          end

          if note.id == "index.md"
            navigation_error("reserved_navigation_page", "the root index already belongs to Home", note.id)
            next
          end
          next unless authored.fetch("visible", true)

          id = "page:#{note.id}"
          note_ids = if File.basename(note.id) == "index.md"
            prefix = "#{File.dirname(note.id)}/"
            @model.notes.select do |candidate|
              candidate.content_type == "page" && candidate.id.start_with?(prefix)
            end.map(&:id)
          else
            [note.id]
          end
          items << {
            "id" => id,
            "label" => authored["label"] || note.title,
            "url" => @url_builder.href(note.route),
            "order" => authored.fetch("order", 100),
            "active_scope" => active_scope(note_ids, [])
          }
        end
      end

      def validate_items(items)
        candidates = items.filter_map do |item|
          label = item["label"]
          unless FrontMatter.valid_output_text?(label) && !label.strip.empty?
            navigation_error(
              "invalid_navigation_label",
              "navigation label must be a non-empty string containing only output-safe Unicode characters",
              navigation_source(item)
            )
            next
          end

          item.merge("label" => label.strip)
        end
        valid = []
        labels = {}
        destinations = {}
        candidates.sort_by { |item| [item.fetch("order"), item.fetch("label").downcase, item.fetch("label"), item.fetch("id")] }.each do |item|
          label_key = item.fetch("label").unicode_normalize(:nfc).downcase(:fold)
          destination_key = item.fetch("url").unicode_normalize(:nfc).downcase(:fold)
          if labels.key?(label_key)
            navigation_error(
              "duplicate_navigation_label",
              "navigation labels must be unique; conflicts with #{labels.fetch(label_key).inspect}",
              navigation_source(item)
            )
            next
          end
          if destinations.key?(destination_key)
            navigation_error(
              "duplicate_navigation_target",
              "navigation targets must be unique; conflicts with #{destinations.fetch(destination_key).inspect}",
              navigation_source(item)
            )
            next
          end

          labels[label_key] = item.fetch("id")
          destinations[destination_key] = item.fetch("id")
          valid << item
        rescue EncodingError
          navigation_error("invalid_navigation_label", "navigation label must contain valid Unicode", navigation_source(item))
        end
        valid
      end

      def active_notes(items)
        active = {}
        builtins = items.select { |item| %w[home blog docs portfolio].include?(item.fetch("id")) }
        folders = items.select { |item| item.fetch("id").start_with?("folder:") }.sort_by do |item|
          item.fetch("id").count("/")
        end
        pages = items.select { |item| item.fetch("id").start_with?("page:") }.sort_by do |item|
          note_id = item.fetch("id").delete_prefix("page:")
          index = File.basename(note_id) == "index.md"
          [index ? 0 : 1, index ? note_id.count("/") : 0, note_id]
        end
        (builtins + folders + pages).each do |item|
          item.fetch("active_scope").fetch("note_ids").each do |note_id|
            active[note_id] = item.fetch("id")
          end
        end
        active
      end

      def active_scope(note_ids, routes)
        {
          "note_ids" => note_ids.uniq.sort,
          "routes" => routes.uniq.sort
        }
      end

      def portfolio_projection
        path = @settings.fetch("portfolio").fetch("path")
        notes = @model.notes.select { |note| note.id.start_with?("#{path}/") }
        index = notes.find { |note| note.id == "#{path}/index.md" }
        projects = notes.reject { |note| note.id == index&.id || note.nav_exclude }.sort_by do |note|
          portfolio_sort_key(note)
        end
        return if projects.empty?

        @portfolio_note_ids = notes.map(&:id)
        PortfolioProjection.new(
          path: path,
          route: index ? index.route : @url_builder.route_for_note("#{path}/index.md"),
          index_note_id: index&.id,
          project_note_ids: projects.map(&:id)
        )
      end

      def portfolio_sort_key(note)
        order = note.nav_order
        pinned = note.properties["pinned"] == true
        [pinned ? 0 : 1, order.nil? ? 1 : 0, order || 0, note.title.downcase, note.title, note.id]
      end

      def navigation_source(item)
        id = item.fetch("id")
        return id.delete_prefix("page:") if id.start_with?("page:")
        return id.delete_prefix("folder:") if id.start_with?("folder:")

        "website.navigation.#{id}"
      end

      def documentation_navigation
        root = { path: "", name: "", index: nil, notes: [], children: {} }
        docs_directories = @content.fetch("directories").fetch("doc")
        single_root = docs_directories.first if docs_directories.one?
        @model.notes.select { |note| note.content_type == "doc" }.sort_by(&:id).each do |note|
          navigation_id = if single_root && note.id.start_with?("#{single_root}/")
            note.id.delete_prefix("#{single_root}/")
          else
            note.id
          end
          directory = File.dirname(navigation_id)
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
          if File.basename(navigation_id) == "index.md"
            folder[:index] = note
          else
            folder[:notes] << note
          end
        end

        tree = render_folder_contents(root)
        linked = []
        root_index = root.fetch(:index)
        linked << root_index if root_index && !root_index.nav_exclude
        walk = lambda do |nodes|
          nodes.each do |node|
            linked << @model.notes_by_id.fetch(node.fetch("id")) if node["url"] && @model.notes_by_id.key?(node.fetch("id"))
            walk.call(node.fetch("children"))
          end
        end
        walk.call(tree)

        configured_root = docs_directories.filter_map do |directory|
          candidate = @model.notes_by_id["#{directory}/index.md"]
          candidate if candidate&.content_type == "doc" && !candidate.nav_exclude
        end.first
        landing = configured_root || linked.first
        {
          "tree" => tree,
          "linked_notes" => linked,
          "home_url" => landing && @url_builder.href(landing.route)
        }
      end

      def render_folder_contents(folder)
        nodes = folder.fetch(:notes).reject(&:nav_exclude).map { |note| docs_node(note, []) }
        folder.fetch(:children).values.each do |child|
          children = render_folder_contents(child)
          index_note = child.fetch(:index)
          next if children.empty? && (!index_note || index_note.nav_exclude)

          node = if index_note
            docs_node(index_note, children, linked: !index_note.nav_exclude)
          else
            {
              "id" => "folder:#{child.fetch(:path)}",
              "title" => humanize_path_segment(child.fetch(:name)),
              "url" => first_link_url(children),
              "content_type" => "doc",
              "children" => children,
              "nav_order" => nil
            }
          end
          nodes << node
        end
        nodes.sort_by { |node| docs_sort_key(node) }
      end

      def first_link_url(nodes)
        nodes.each do |node|
          return node["url"] if node["url"]

          nested = first_link_url(node.fetch("children"))
          return nested if nested
        end
        nil
      end

      def docs_node(note, children, linked: true)
        {
          "id" => note.id,
          "title" => note.title,
          "url" => linked ? @url_builder.href(note.route) : nil,
          "content_type" => note.content_type,
          "children" => children,
          "nav_order" => note.nav_order
        }
      end

      def docs_sort_key(node)
        order = node["nav_order"]
        [order.nil? ? 1 : 0, order || 0, node.fetch("title").downcase, node.fetch("id")]
      end

      def note_sort_key(note)
        [note.nav_order.nil? ? 1 : 0, note.nav_order || 0, note.title.downcase, note.id]
      end

      def folder_label(path, notes)
        index = notes.find { |note| note.id == "#{path}/index.md" }
        index&.title || humanize_path_segment(File.basename(path))
      end

      def humanize_path_segment(segment)
        segment.tr("-_", " ").split.map(&:capitalize).join(" ")
      end

      def navigation_error(code, message, path)
        @diagnostics << Diagnostic.new(severity: :error, code: code, message: message, path: path, span: nil)
      end
    end
  end
end
