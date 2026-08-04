# frozen_string_literal: true

require "json"
require "nokogiri"
require "psych"
require "set"
require "uri"

module JekyllObsidian
  # Compiles every configured theme locale behind the existing VaultCompiler
  # interface. The default tree remains authoritative; translated snapshots
  # are overlays with the same logical paths.
  class LocalizedCompiler
    TRANSLATIONS_ROOT = "_translations"
    LOCALE_MANIFEST = "_locale.yml"
    TRANSLATABLE_PROPERTIES = %w[title description tags image cssclasses].freeze
    STRUCTURAL_PROPERTIES = (FrontMatter::SUPPORTED - TRANSLATABLE_PROPERTIES - %w[publish]).freeze
    URL_PROPERTIES = %w[
      absolute_url canonical_url discussion_url docs_home_url docs_index_url docs_tree_url
      home_url href image route url
    ].freeze
    SOURCE_LINK_PROPERTIES = %w[edit history issue source].freeze
    LOCALE_PATTERN = /\A[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*\z/
    RESERVED_LOCALE_PREFIXES = %w[assets].freeze
    MESSAGE_DEFAULTS = {
      "language" => "Language",
      "translation_missing" => "This page is not translated yet. The default-language version is shown.",
      "skip_to_content" => "Skip to content",
      "overview" => "Overview",
      "documentation" => "Documentation",
      "tags" => "Tags",
      "graph" => "Graph",
      "feed" => "Feed",
      "search" => "Search",
      "scheme" => "Scheme",
      "toggle_scheme" => "Toggle color scheme",
      "use_light_scheme" => "Use light color scheme",
      "use_dark_scheme" => "Use dark color scheme",
      "light_scheme" => "Light",
      "dark_scheme" => "Dark",
      "contents" => "Contents",
      "view_full_index" => "View full documentation index",
      "breadcrumb" => "Breadcrumb",
      "page_context" => "Page context",
      "mobile_actions" => "Mobile actions",
      "browse" => "Browse",
      "on_this_page" => "On this page",
      "context" => "Context",
      "previous" => "Previous",
      "next" => "Next",
      "manual" => "Manual",
      "dispatch" => "Dispatch",
      "note" => "Note",
      "published" => "Published",
      "updated" => "Updated",
      "edit" => "Edit",
      "history" => "History",
      "view_source" => "View source",
      "report_issue" => "Report issue",
      "contribute" => "Contribute to this page",
      "documentation_sequence" => "Documentation sequence",
      "manual_index" => "Manual index",
      "browse_handbook" => "Browse the handbook",
      "search_title" => "Search this site",
      "close_search" => "Close search",
      "search_pages" => "Search pages",
      "search_placeholder" => "Title, tag, or phrase",
      "search_initial" => "The index loads when search opens.",
      "search_loading" => "Loading notebook index…",
      "search_prompt" => "Type a title, tag, or phrase.",
      "search_unavailable" => "Search could not be loaded. Reload the page and try again.",
      "search_no_results" => "No notes found for “{query}”.",
      "search_result_one" => "{count} note found.",
      "search_result_many" => "{count} notes found.",
      "close_browse" => "Close browse menu",
      "more_browse_options" => "More ways to browse",
      "close_context" => "Close page context",
      "outgoing_links" => "Outgoing links",
      "direct_links" => "Direct links",
      "backlinks" => "Backlinks",
      "embedded_by" => "Embedded by",
      "no_outgoing_links" => "No outgoing note links.",
      "no_backlinks" => "No notes link here yet.",
      "not_embedded" => "Not embedded elsewhere.",
      "outline" => "On this page",
      "no_headings" => "No headings on this page.",
      "all_notes" => "All notes",
      "page_not_found" => "Page not found",
      "page_not_found_description" => "The requested page is not in this published site.",
      "return_home" => "Return home",
      "primary_navigation" => "Primary navigation",
      "home" => "Home",
      "archive" => "Archive",
      "interactive_graph" => "Interactive graph",
      "open_full_graph" => "Open full graph",
      "open_local_graph" => "Expand local graph",
      "full_graph" => "Full graph",
      "local_graph" => "Local graph",
      "close_full_graph" => "Close full graph",
      "close_local_graph" => "Close local graph",
      "isolated_graph" => "This note has no linked neighbours yet.",
      "graph_loading" => "Loading graph…",
      "graph_unavailable" => "The interactive graph could not be loaded. Use the linked notes below.",
      "graph_too_large" => "This complete graph is too large to render interactively. Use local graphs or search instead.",
      "graph_summary" => "{notes} notes and {relations} relations.",
      "graph_node_label" => "{title}, {count} relations",
      "graph_title" => "Note relation graph",
      "graph_description" => "Linked notes are connected by solid lines; embedded notes use dashed lines.",
      "diagram" => "Diagram",
      "embed_cycle" => "Embed cycle",
      "embedded_from" => "From {title}",
      "missing_fragment" => "Missing fragment: {label}",
      "download_pdf" => "Download PDF",
      "download" => "Download",
      "built_by" => "Built by",
      "project_on_github" => "Jekyll Obsidian on GitHub",
      "latest" => "Latest",
      "topics" => "Topics",
      "notes" => "Notes",
      "note_context" => "Note context",
      "post_sequence" => "Post sequence",
      "older" => "Older",
      "newer" => "Newer",
      "dated_posts" => "Dated posts",
      "chronology" => "Chronology",
      "field_dispatches" => "Field dispatches",
      "browse_archive" => "Browse the archive",
      "notebook_index" => "Notebook index",
      "explore_garden" => "Explore the garden",
      "garden_overview" => "Garden overview",
      "browse_every_page" => "Browse every published page",
      "follow_subjects" => "Follow recurring subjects",
      "see_vault_links" => "See links across the vault",
      "discussion" => "Discussion",
      "comments" => "Comments",
      "comments_loading" => "Loading comments…",
      "comments_development" => "Comments load only on the published site.",
      "comments_setup_pending" => "Comments are not available yet. You can finish the GitHub Discussions setup later.",
      "comments_unavailable" => "Comments could not be loaded. You can continue the conversation on GitHub.",
      "comments_stored" => "Comments are stored in GitHub Discussions.",
      "open_discussions" => "Open discussions on GitHub",
      "open_comments_repository" => "Open the comments repository on GitHub"
    }.freeze

    def self.compile(request)
      new(request).compile
    end

    def initialize(request)
      @request = request
      @config = request.config
      @diagnostics = []
      @entries = Array(request.snapshot.entries)
      @entries_by_path = @entries.to_h { |entry| [entry.path.to_s, entry] }
      @url_builder = UrlBuilder.new(origin: @config.url, baseurl: @config.baseurl)
      @locales = []
      @enabled = false
      @locale_data = {}
      @actual_by_locale = {}
      @physical_sources = {}
      @default_locale = @config.lang.to_s
    rescue ArgumentError => exception
      @diagnostics ||= []
      error("invalid_url_config", exception.message)
    end

    def compile
      validate_configuration
      return failure if @diagnostics.any? { |item| item.severity == :error }
      return compile_disabled unless @enabled

      load_manifests if @diagnostics.none? { |item| item.severity == :error }
      snapshots = build_locale_snapshots if @diagnostics.none? { |item| item.severity == :error }
      return failure if @diagnostics.any? { |item| item.severity == :error }

      results = @locales.to_h do |locale|
        config = BuildConfig.new(**@config.to_h.merge(i18n: nil))
        result = VaultCompiler.compile_single(BuildRequest.new(snapshot: snapshots.fetch(locale), config: config))
        @diagnostics.concat(result.diagnostics)
        [locale, result]
      end
      return failure if results.values.any? { |result| !result.success? }

      combine(results)
    rescue StandardError => exception
      error("i18n_internal_error", exception.message)
      failure
    end

    private

    def compile_disabled
      config = BuildConfig.new(**@config.to_h.merge(i18n: nil))
      VaultCompiler.compile_single(BuildRequest.new(snapshot: @request.snapshot, config: config))
    end

    def validate_configuration
      raw = @config.i18n
      unless raw.is_a?(Hash)
        error("invalid_i18n_config", "website.i18n must be a mapping")
        return
      end
      unknown = raw.keys.map(&:to_s) - %w[enabled locales]
      unknown.each { |key| error("invalid_i18n_config", "unknown i18n setting #{key.inspect}") }
      enabled = fetch(raw, "enabled") if raw.key?("enabled") || raw.key?(:enabled)
      unless enabled.nil? || enabled == true || enabled == false
        error("invalid_i18n_config", "website.i18n.enabled must be a YAML boolean")
        return
      end
      configured_theme = @config.theme.to_s
      configured_theme = "docs" if configured_theme.empty?
      @enabled = enabled.nil? ? configured_theme == "docs" : enabled
      locales = fetch(raw, "locales")
      return unless @enabled || !locales.nil?

      unless locales.is_a?(Array) && !locales.empty? && locales.all? { |locale| locale.is_a?(String) }
        error("invalid_i18n_locales", "website.i18n.locales must be a non-empty array of locale strings")
        return
      end
      folded = Set.new
      locales.each do |locale|
        unless locale.match?(LOCALE_PATTERN) && locale == locale.unicode_normalize(:nfc)
          error("invalid_locale", "locale must be a normalized BCP 47-style tag", locale)
          next
        end
        if RESERVED_LOCALE_PREFIXES.include?(locale.downcase(:fold))
          error("reserved_locale", "locale conflicts with a reserved public route prefix", locale)
          next
        end
        key = locale.downcase(:fold)
        if folded.include?(key)
          error("duplicate_locale", "locales must be unique under case-folding", locale)
        else
          folded << key
          @locales << locale
        end
      rescue EncodingError
        error("invalid_locale", "locale must contain valid Unicode", locale)
      end
      if @enabled && !@locales.include?(@default_locale)
        error("missing_default_locale", "lang must name one of website.i18n.locales")
      end
    end

    def load_manifests
      @locales.each do |locale|
        path = locale == @default_locale ? LOCALE_MANIFEST : "#{TRANSLATIONS_ROOT}/#{locale}/#{LOCALE_MANIFEST}"
        entry = @entries_by_path[path]
        unless entry
          error("missing_locale_manifest", "configured locale requires #{path}", path)
          next
        end
        begin
          raw = Psych.safe_load(entry.bytes.to_s, permitted_classes: [], aliases: false)
        rescue Psych::Exception => exception
          error("invalid_locale_manifest", exception.message, path)
          next
        end
        unless raw.is_a?(Hash) && raw.keys.all? { |key| key.is_a?(String) }
          error("invalid_locale_manifest", "locale manifest must be a YAML mapping with string keys", path)
          next
        end
        unknown = raw.keys - %w[name hreflang dir messages]
        unknown.each { |key| error("invalid_locale_manifest", "unknown locale setting #{key.inspect}", path) }
        name = raw["name"]
        unless valid_text?(name) && !name.empty?
          error("invalid_locale_manifest", "name must be a non-empty string", path)
          name = locale
        end
        hreflang = raw.fetch("hreflang", locale)
        error("invalid_locale_manifest", "hreflang must be a non-empty string", path) unless valid_text?(hreflang) && !hreflang.empty?
        direction = raw.fetch("dir", "ltr")
        error("invalid_locale_manifest", "dir must be ltr or rtl", path) unless %w[ltr rtl].include?(direction)
        messages = raw.fetch("messages", {})
        unless messages.is_a?(Hash) && messages.keys.all? { |key| key.is_a?(String) }
          error("invalid_locale_manifest", "messages must be a mapping with string keys", path)
          messages = {}
        end
        messages.each do |key, value|
          error("invalid_locale_message", "unknown message key #{key.inspect}", path) unless MESSAGE_DEFAULTS.key?(key)
          error("invalid_locale_message", "message #{key.inspect} must be a string", path) unless valid_text?(value)
        end
        @locale_data[locale] = {
          "code" => locale,
          "name" => name,
          "hreflang" => hreflang,
          "dir" => direction,
          "messages" => MESSAGE_DEFAULTS.merge(messages.select { |key, value| MESSAGE_DEFAULTS.key?(key) && valid_text?(value) })
        }
      end
    end

    def build_locale_snapshots
      default_entries = @entries.reject do |entry|
        entry.path == LOCALE_MANIFEST || entry.path.to_s.start_with?("#{TRANSLATIONS_ROOT}/")
      end
      default_public = default_entries.filter_map do |entry|
        next unless entry.kind.to_sym == :note
        parsed = FrontMatter.parse(entry.path, entry.bytes.to_s)
        @diagnostics.concat(parsed.diagnostics)
        [entry.path, [entry, parsed]] if parsed.properties["publish"] == true
      end.to_h

      configured_roots = @locales.reject { |locale| locale == @default_locale }.map { |locale| "#{TRANSLATIONS_ROOT}/#{locale}/" }
      @entries.each do |entry|
        next unless entry.path.to_s.start_with?("#{TRANSLATIONS_ROOT}/")
        next if configured_roots.any? { |root| entry.path.to_s.start_with?(root) }

        error("unknown_translation_locale", "translation content belongs to an unconfigured locale", entry.path)
      end

      snapshots = { @default_locale => Snapshot.new(entries: default_entries) }
      @actual_by_locale[@default_locale] = Set.new(default_public.keys)
      @physical_sources[@default_locale] = default_public.keys.to_h { |path| [path, path] }

      @locales.each do |locale|
        next if locale == @default_locale

        prefix = "#{TRANSLATIONS_ROOT}/#{locale}/"
        translated = {}
        @entries.select { |entry| entry.path.to_s.start_with?(prefix) }.each do |entry|
          logical_path = entry.path.to_s.delete_prefix(prefix)
          next if logical_path == LOCALE_MANIFEST
          unless valid_logical_path?(logical_path)
            error("invalid_translation_path", "translation paths must be normalized vault-relative POSIX paths", entry.path)
            next
          end
          unless entry.kind.to_sym == :note
            error("localized_asset_unsupported", "localized binary assets are not supported; reference a shared default asset", entry.path)
            next
          end
          default_pair = default_public[logical_path]
          unless default_pair
            error("orphan_translation", "translation has no published default-language counterpart", entry.path)
            next
          end
          translated_parse = FrontMatter.parse(entry.path, entry.bytes.to_s)
          @diagnostics.concat(translated_parse.diagnostics)
          unless translated_parse.properties["publish"] == true
            error("unpublished_translation", "translation notes must use publish: true", entry.path)
            next
          end
          default_entry, default_parse = default_pair
          STRUCTURAL_PROPERTIES.each do |property|
            next unless translated_parse.properties.key?(property)
            next if translated_parse.properties[property] == default_parse.properties[property]

            error("localized_structure_override", "translation must not change #{property}", entry.path)
          end
          merged = default_parse.properties.merge(translated_parse.properties)
          bytes = "#{Psych.dump(merged)}---\n#{translated_parse.body}"
          translated[logical_path] = SnapshotEntry.new(**entry.to_h.merge(
            path: logical_path,
            bytes: bytes,
            size: bytes.bytesize,
            first_committed_at: default_entry.first_committed_at,
            last_committed_at: default_entry.last_committed_at
          ))
          (@physical_sources[locale] ||= {})[logical_path] = entry.path
        end
        @actual_by_locale[locale] = Set.new(translated.keys)
        @physical_sources[locale] ||= {}
        overlaid = default_entries.map do |entry|
          entry.kind.to_sym == :note && translated.key?(entry.path) ? translated.fetch(entry.path) : entry
        end
        snapshots[locale] = Snapshot.new(entries: overlaid)
      end
      snapshots
    end

    def combine(results)
      pages = []
      generated_files = []
      copied_assets = {}
      notes = []
      relations = []
      default_routes = note_routes(results.fetch(@default_locale))

      @locales.each do |locale|
        result = results.fetch(locale)
        result.pages.each { |page| pages << localize_page(page, locale, default_routes) }
        result.generated_files.each do |file|
          localized = localize_generated_file(file, locale)
          generated_files << localized if localized
        end
        result.copied_assets.each { |asset| copied_assets[asset.route] ||= asset }
        result.notes.each do |note|
          notes << NoteOutput.new(
            id: locale == @default_locale ? note.id : "#{locale}:#{note.id}",
            title: note.title,
            route: prefixed_route(note.route, locale),
            properties: note.properties
          )
        end
        result.relations.each do |relation|
          prefix = locale == @default_locale ? "" : "#{locale}:"
          relations << Relation.new(**relation.to_h.merge(
            source_id: "#{prefix}#{relation.source_id}",
            target_id: "#{prefix}#{relation.target_id}"
          ))
        end
      end

      generated_files.reject! { |file| file.route == "/sitemap.xml" }
      generated_files << GeneratedFile.new(route: "/sitemap.xml", content: sitemap_xml(pages), media_type: "application/xml")
      preflight_routes(pages, generated_files, copied_assets.values)
      return failure if @diagnostics.any? { |item| item.severity == :error }

      default_result = results.fetch(@default_locale)
      BuildSuccess.new(
        pages: pages.sort_by(&:route),
        generated_files: generated_files.sort_by(&:route),
        copied_assets: copied_assets.values.sort_by(&:route),
        diagnostics: sorted_diagnostics,
        relations: relations.freeze,
        notes: notes.freeze,
        theme: default_result.theme,
        features: default_result.features,
        site_data: default_result.site_data.merge(
          "website_i18n" => {
            "default_locale" => @default_locale,
            "locales" => @locales.map { |locale| @locale_data.fetch(locale).reject { |key, _| key == "messages" } }
          }
        )
      )
    end

    def localize_page(page, locale, default_routes)
      route = prefixed_route(page.route, locale)
      data = localize_data(page.data, locale)
      website = data.fetch("website")
      kind = website.fetch("kind")
      note_id = website["id"]
      actual = kind != "note" || locale == @default_locale || @actual_by_locale.fetch(locale).include?(note_id)
      default_route = kind == "note" ? default_routes.fetch(note_id) : page.route
      localizations = @locales.map do |candidate|
        candidate_actual = kind != "note" || candidate == @default_locale || @actual_by_locale.fetch(candidate).include?(note_id)
        locale_data = @locale_data.fetch(candidate)
        {
          "locale" => candidate,
          "name" => locale_data.fetch("name"),
          "hreflang" => locale_data.fetch("hreflang"),
          "dir" => locale_data.fetch("dir"),
          "href" => @url_builder.href(prefixed_route(default_route, candidate)),
          "fallback" => !candidate_actual
        }
      end
      alternates = if actual
        localizations.reject { |item| item.fetch("fallback") }.map do |item|
          item.merge("href" => absolute_for(item.fetch("href")))
        end.then do |items|
          default = items.find { |item| item.fetch("locale") == @default_locale }
          default ? items + [{ "hreflang" => "x-default", "href" => default.fetch("href") }] : items
        end
      else
        []
      end
      locale_data = @locale_data.fetch(locale)
      content_locale_data = actual ? locale_data : @locale_data.fetch(@default_locale)
      website["route"] = route
      website["href"] = @url_builder.href(route)
      website["canonical_url"] = actual ? @url_builder.absolute_url(route) : @url_builder.absolute_url(default_route)
      website["alternates"] = alternates
      website["robots"] = "noindex" unless actual
      website["resources"] = resource_urls(locale)
      website["routes"] = %w[home tags notes archive].to_h do |name|
        base = name == "home" ? "/" : "/#{name}/"
        [name, prefixed_route(base, locale)]
      end.merge("feed" => prefixed_route("/feed.xml", locale))
      website["i18n"] = {
        "locale" => locale,
        "name" => locale_data.fetch("name"),
        "hreflang" => locale_data.fetch("hreflang"),
        "dir" => locale_data.fetch("dir"),
        "messages" => locale_data.fetch("messages"),
        "content_lang" => actual ? locale : @default_locale,
        "content_dir" => content_locale_data.fetch("dir"),
        "fallback" => !actual,
        "localizations" => localizations
      }
      if website["comments"]
        website["comments"]["language"] = VaultCompiler.giscus_language(locale)
      end
      localize_page_copy!(data, kind, locale_data.fetch("messages"))
      if kind == "note" && actual && locale != @default_locale
        website["source_links"] = repository_links(@physical_sources.fetch(locale).fetch(note_id), note_id)
      end
      content = localize_html(page.content, locale)
      PageOutput.new(route: route, content: content, data: data)
    end

    def localize_generated_file(file, locale)
      return nil if locale != @default_locale && file.route == "/sitemap.xml"

      route = generated_route(file.route, locale)
      content = case file.media_type
      when "application/json"
        "#{JSON.generate(localize_data(JSON.parse(file.content), locale))}\n"
      when "text/html"
        localize_html(file.content, locale)
      when "application/atom+xml", "application/xml"
        localize_xml(file.content, locale)
      else
        file.content
      end
      GeneratedFile.new(route: route, content: content, media_type: file.media_type)
    end

    def generated_route(route, locale)
      return route if locale == @default_locale
      if route.start_with?("/assets/website/")
        basename = route.delete_prefix("/assets/website/")
        return "/assets/website/i18n/#{locale}/#{basename}"
      end
      prefixed_route(route, locale)
    end

    def resource_urls(locale)
      prefix = locale == @default_locale ? "/assets/website" : "/assets/website/i18n/#{locale}"
      {
        "search" => @url_builder.href("#{prefix}/search.v1.json"),
        "catalog" => @url_builder.href("#{prefix}/catalog.v1.json"),
        "preview" => @url_builder.href("#{prefix}/catalog.v1.json"),
        "graph" => @url_builder.href("#{prefix}/graph.v1.json"),
        "docs_navigation" => @url_builder.href("#{prefix}/docs-navigation.html"),
        "feed" => @url_builder.href(prefixed_route("/feed.xml", locale))
      }
    end

    def localize_data(value, locale, property = nil, parent_property = nil)
      case value
      when Hash
        value.to_h do |key, item|
          [key, localize_data(item, locale, key.to_s, property)]
        end
      when Array
        value.map { |item| localize_data(item, locale, property, parent_property) }
      when String
        localizable_url_property?(property, parent_property) ? localize_url(value, locale) : value
      else
        value
      end
    end

    def localizable_url_property?(property, parent_property)
      URL_PROPERTIES.include?(property) ||
        (parent_property == "source_links" && SOURCE_LINK_PROPERTIES.include?(property))
    end

    def localize_html(html, locale)
      fragment = Nokogiri::HTML5.fragment(html)
      fragment.css("[href], [src], [poster]").each do |node|
        %w[href src poster].each { |attribute| node[attribute] = localize_url(node[attribute], locale) if node[attribute] }
      end
      localize_generated_copy(fragment, locale)
      fragment.to_html
    end

    def localize_generated_copy(fragment, locale)
      messages = @locale_data.fetch(locale).fetch("messages")
      fragment.css("[data-website-mermaid]").each { |node| node["data-diagram-label"] = messages.fetch("diagram") }
      fragment.css(".website-embed--cycle").each do |node|
        replace_generated_text(node, messages.fetch("embed_cycle"), locale) if node.text == MESSAGE_DEFAULTS.fetch("embed_cycle")
      end
      fragment.css(".website-transclusion__source").each do |node|
        next unless node.text.start_with?("From ")

        title = node.text.delete_prefix("From ")
        replace_generated_text(node, messages.fetch("embedded_from").sub("{title}", title), locale)
      end
      fragment.css(".website-embed--unresolved").each do |node|
        match = node.text.match(/\AMissing fragment: (?<label>.*)\z/m)
        replace_generated_text(node, messages.fetch("missing_fragment").sub("{label}", match[:label]), locale) if match
      end
      fragment.css("object[type='application/pdf'] > a").each do |node|
        replace_generated_text(node, messages.fetch("download_pdf"), locale) if node.text == MESSAGE_DEFAULTS.fetch("download_pdf")
      end
      fragment.css(".website-download-card__meta").each do |node|
        replace_generated_text(node, messages.fetch("download"), locale) if node.text == MESSAGE_DEFAULTS.fetch("download")
      end
    end

    def replace_generated_text(node, text, locale)
      node.content = text
      node["lang"] = locale if locale != @default_locale
    end

    def localize_xml(xml, locale)
      document = Nokogiri::XML(xml) { |config| config.strict.nonet }
      document.xpath("//*[@href]").each { |node| node["href"] = localize_url(node["href"], locale) }
      document.xpath("//*[local-name()='id']").each { |node| node.content = localize_url(node.text, locale) }
      document.to_xml
    rescue Nokogiri::XML::SyntaxError
      xml
    end

    def localize_url(value, locale)
      return value if locale == @default_locale || value.empty? || value.start_with?("#")

      absolute = !@url_builder.origin.empty? && value.start_with?(@url_builder.origin)
      raw = absolute ? value.delete_prefix(@url_builder.origin) : value
      return value unless raw.start_with?("/")

      path, suffix = raw.split(/(?=[?#])/, 2)
      relative = if @url_builder.baseurl.empty?
        path
      elsif path == @url_builder.baseurl || path.start_with?("#{@url_builder.baseurl}/")
        path.delete_prefix(@url_builder.baseurl)
      else
        return value
      end
      relative = "/" if relative.empty?
      localized = if relative == "/assets/website/docs-navigation.html"
        "/assets/website/i18n/#{locale}/docs-navigation.html"
      elsif relative.start_with?("/assets/vault/", "/assets/website/")
        relative
      else
        prefixed_route(relative, locale)
      end
      result = @url_builder.href(localized)
      result = "#{@url_builder.origin}#{result}" if absolute
      "#{result}#{suffix}"
    end

    def prefixed_route(route, locale)
      return route if locale == @default_locale
      return "/#{locale}/" if route == "/"

      "/#{locale}#{route}"
    end

    def note_routes(result)
      result.pages.filter_map do |page|
        website = page.data["website"]
        [website["id"], page.route] if website&.fetch("kind", nil) == "note"
      end.to_h
    end

    def repository_links(path, logical_path)
      repository = @config.repository.to_s
      return {} unless repository.match?(/\A[\w.-]+\/[\w.-]+\z/)

      branch = URI.encode_uri_component(@config.edit_branch.to_s.empty? ? "main" : @config.edit_branch.to_s)
      source = [@config.source.to_s, path].reject(&:empty?).map do |part|
        part.split("/").map { |segment| URI.encode_uri_component(segment) }.join("/")
      end.join("/")
      base = "https://github.com/#{repository}"
      {
        "edit" => "#{base}/edit/#{branch}/#{source}",
        "history" => "#{base}/commits/#{branch}/#{source}",
        "source" => "#{base}/blob/#{branch}/#{source}",
        "issue" => "#{base}/issues/new?title=#{URI.encode_uri_component("Issue with #{logical_path}")}"
      }
    end

    def absolute_for(href)
      return href if @url_builder.origin.empty?

      "#{@url_builder.origin}#{href}"
    end

    def sitemap_xml(pages)
      body = pages.reject do |page|
        page.route.end_with?("/404.html") || page.data.dig("website", "i18n", "fallback")
      end.sort_by(&:route).map do |page|
        website = page.data.fetch("website")
        alternates = Array(website["alternates"]).map do |alternate|
          %(    <xhtml:link rel="alternate" hreflang="#{escape(alternate.fetch('hreflang'))}" href="#{escape(alternate.fetch('href'))}" />)
        end
        lines = ["  <url>", "    <loc>#{escape(@url_builder.absolute_url(page.route))}</loc>", *alternates, "  </url>"]
        lines.join("\n")
      end.join("\n")
      %(<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n#{body}\n</urlset>\n)
    end

    def preflight_routes(pages, files, assets)
      seen = {}
      (pages + files + assets).each do |output|
        destination = destination_key(output)
        conflict = seen.find do |candidate, _route|
          candidate == destination || candidate.start_with?("#{destination}/") || destination.start_with?("#{candidate}/")
        end
        if conflict
          error("route_collision", "localized output collides with #{conflict.last}", output.route)
        else
          seen[destination] = output.route
        end
      end
    end

    def destination_key(output)
      key = @url_builder.collision_key(output.route)
      if output.is_a?(PageOutput)
        key.end_with?("/") ? "#{key}index.html" : key
      else
        output.route.end_with?("/") ? key : key.delete_suffix("/")
      end
    end

    def fetch(hash, key)
      hash.key?(key) ? hash[key] : hash[key.to_sym]
    end

    def valid_text?(value)
      FrontMatter.valid_output_text?(value)
    end

    def valid_logical_path?(path)
      return false unless valid_text?(path) && path == path.unicode_normalize(:nfc)
      return false if path.empty? || path.start_with?("/", "\\") || path.include?("\\")

      path.split("/", -1).none? { |segment| segment.empty? || segment == "." || segment == ".." }
    rescue EncodingError
      false
    end

    def localize_page_copy!(data, kind, messages)
      title_key = {
        "archive" => "archive",
        "tags" => "tags",
        "graph" => "graph",
        "notes" => "all_notes",
        "404" => "page_not_found"
      }[kind]
      data["title"] = messages.fetch(title_key) if title_key
      data["description"] = messages.fetch("page_not_found_description") if kind == "404"
    end

    def escape(value)
      CGI.escapeHTML(value.to_s)
    end

    def error(code, message, path = nil)
      @diagnostics << Diagnostic.new(severity: :error, code: code, message: message, path: path, span: nil)
    end

    def sorted_diagnostics
      @diagnostics.sort_by { |item| [item.path.to_s.b, item.span&.start_line.to_i, item.code.to_s, item.message.to_s] }.freeze
    end

    def failure
      BuildFailure.new(diagnostics: sorted_diagnostics)
    end
  end
end
