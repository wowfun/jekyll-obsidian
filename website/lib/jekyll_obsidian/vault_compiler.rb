# frozen_string_literal: true

require "cgi/escape"
require "commonmarker"
require "json"
require "nokogiri"
require "pathname"
require "set"
require "uri"

module JekyllObsidian
  class VaultCompiler
    COMMONMARK_OPTIONS = {
      parse: {
        smart: false,
        relaxed_tasklist_matching: true,
        relaxed_autolinks: true,
        sourcepos_chars: true
      },
      render: {
        unsafe: true,
        hardbreaks: true,
        tasklist_classes: true,
        escaped_char_spans: true,
        sourcepos: true
      },
      extension: {
        strikethrough: true,
        table: true,
        autolink: true,
        tasklist: true,
        footnotes: true,
        math_dollars: true,
        math_code: true,
        math_latex: true,
        wikilinks_title_after_pipe: true,
        highlight: true,
        cjk_friendly_emphasis: true
      }
    }.freeze
    COMMONMARK_PLUGINS = { syntax_highlighter: { theme: "" } }.freeze
    REMOTE_COMMONMARK_OPTIONS = {
      parse: COMMONMARK_OPTIONS.fetch(:parse),
      render: COMMONMARK_OPTIONS.fetch(:render).merge(unsafe: false),
      extension: {
        strikethrough: true,
        table: true,
        autolink: true,
        tasklist: true,
        footnotes: true
      }
    }.freeze
    DANGEROUS_SCHEMES = %w[data file javascript vbscript].freeze
    EXTERNAL_SCHEMES = %w[http https mailto tel].freeze
    NOTE_EXTENSION = ".md"
    TRANSLATIONS_DIRECTORY = "_translations/"
    THEMES = BuiltInThemes::IDS
    FEATURE_KEYS = %w[search tags feed graph relations previews outline].freeze
    COMMENT_KEYS = %w[enabled repository repository_id category category_id].freeze
    ANALYTICS_PROVIDERS = %w[cloudflare google].freeze
    CONTACT_KEYS = %w[label url].freeze
    CONTACT_HOST_ICONS = {
      "github.com" => "github",
      "linkedin.com" => "linkedin",
      "x.com" => "x",
      "twitter.com" => "x",
      "mastodon.social" => "mastodon",
      "bsky.app" => "bluesky",
      "bsky.social" => "bluesky",
      "instagram.com" => "instagram",
      "youtube.com" => "youtube",
      "youtu.be" => "youtube",
      "t.me" => "telegram",
      "telegram.me" => "telegram",
      "telegram.org" => "telegram"
    }.freeze
    NAVIGATION_BUILTINS = {
      "home" => { "order" => 0, "visible" => true }.freeze,
      "blog" => { "order" => 10, "visible" => true }.freeze,
      "docs" => { "order" => 20, "visible" => true }.freeze
    }.freeze
    PORTFOLIO_NAVIGATION_DEFAULTS = {
      "path" => "portfolio", "order" => 30, "visible" => true
    }.freeze
    NAVIGATION_OVERRIDE_KEYS = %w[label order visible].freeze
    NAVIGATION_KEYS = (NAVIGATION_BUILTINS.keys + %w[portfolio folders]).freeze
    PORTFOLIO_NAVIGATION_KEYS = (NAVIGATION_OVERRIDE_KEYS + %w[path]).freeze
    NAVIGATION_FOLDER_KEYS = (NAVIGATION_OVERRIDE_KEYS + %w[path]).freeze
    CUSTOM_NAVIGATION_DEFAULTS = { "order" => 100, "visible" => true }.freeze
    MAX_CONTACTS = 12
    GISCUS_LANGUAGES = Set.new(%w[
      ar be bg ca cs da de en eo es eu fa fr gr hbs he hu id it ja kh ko nl pl
      pt ro ru th tr uk uz vi zh-CN zh-HK zh-TW
    ]).freeze
    THEME_FEATURE_DEFAULTS = {
      "minimal" => {
        "search" => true, "tags" => true, "feed" => true,
        "graph" => true, "relations" => true, "previews" => true, "outline" => true
      },
      "docs" => {
        "search" => true, "tags" => false, "feed" => false,
        "graph" => true, "relations" => true, "previews" => true, "outline" => true
      },
    }.transform_values(&:freeze).freeze
    MutableNote = Struct.new(
      :id,
      :entry,
      :properties,
      :body,
      :document,
      :scanner,
      :title,
      :has_h1,
      :route,
      :occurrences,
      :base_fragment,
      :authored_text,
      :preview,
      :outline,
      :anchors,
      :updated,
      :created,
      :content_type,
      :published_at,
      :nav_order,
      :nav_exclude,
      :feature_flags,
      :topics,
      :external_document,
      keyword_init: true
    )

    Occurrence = Struct.new(
      :index,
      :source_id,
      :raw_target,
      :display,
      :kind,
      :syntax,
      :source_span,
      :scanner_token,
      :resolved_type,
      :target_id,
      :target_path,
      :fragment,
      :options,
      :anchor_id,
      :unresolved,
      :property,
      :external_media,
      keyword_init: true
    )

    Topic = Struct.new(:kind, :name, :occurrence, keyword_init: true)
    Anchor = Struct.new(:kind, :id, :label, :level, :chain, keyword_init: true)
    TransclusionContext = Struct.new(:host_id, :sequence, :instances, :bytes, keyword_init: true)
    MAX_TRANSCLUSION_DEPTH = 16
    MAX_TRANSCLUSION_INSTANCES = 256
    MAX_TRANSCLUSION_BYTES = 2 * 1024 * 1024

    def self.compile(request)
      return LocalizedCompiler.compile(request) unless request.config.i18n.nil?

      compile_single(request)
    end

    def self.compile_single(request)
      new(request).compile
    end

    def self.giscus_language(locale)
      GISCUS_LANGUAGES.include?(locale.to_s) ? locale.to_s : "en"
    end

    def initialize(request)
      @request = request
      @config = request.config
      @diagnostics = []
      @notes = {}
      @all_note_paths = Set.new
      @attachments = {}
      @attachment_basename_index = Hash.new { |hash, key| hash[key] = [] }
      @image_paths = {}
      @relations = []
      @copied_asset_paths = Set.new
      @transclusion_selection_cache = {}
      @url_builder = nil
      @theme = "minimal"
      @features = THEME_FEATURE_DEFAULTS.fetch(@theme)
      @content_policy = ContentPolicy.resolve(nil).policy
      @content = @content_policy.settings
      @comments = disabled_comments_config
      @analytics = disabled_analytics_config
      @contacts = []
      @navigation_config = default_navigation_config
    end

    def compile
      validate_request
      index_snapshot
      parse_public_notes
      establish_identities
      parse_markdown_once
      resolve_all_occurrences
      detect_embed_cycles
      render_authored_documents
      merge_content_features

      published_site = build_published_site_model
      navigation = SiteNavigation.build(
        model: published_site,
        settings: @navigation_config,
        content: @content,
        url_builder: @url_builder,
        theme: @theme
      )
      @diagnostics.concat(navigation.diagnostics)
      theme_config = EffectiveThemeConfig.new(
        theme: @theme,
        features: @features,
        content: @content,
        comments: @comments,
        analytics: @analytics,
        contacts: @contacts,
        navigation: navigation,
        site: @config,
        url_builder: @url_builder
      )
      theme_output = BuiltInThemes.resolve(@theme).render(model: published_site, config: theme_config)
      pages = theme_output.pages
      generated_files = theme_output.shared_files + build_generated_files(pages, published_site, theme_output)
      copied_assets = build_copied_assets
      preflight_routes(pages, generated_files, copied_assets, theme_output.reserved_namespaces)

      note_outputs = published_site.notes.map do |note|
        NoteOutput.new(id: note.id, title: note.title, route: note.route, properties: note.properties)
      end
      diagnostics = sorted_diagnostics
      return BuildFailure.new(diagnostics: diagnostics) if diagnostics.any? { |item| item.severity == :error }

      BuildSuccess.new(
        pages: pages.sort_by(&:route),
        generated_files: generated_files.sort_by(&:route),
        copied_assets: copied_assets.sort_by(&:route),
        diagnostics: diagnostics,
        relations: published_site.relations,
        notes: note_outputs,
        theme: @theme,
        features: @features,
        site_data: theme_output.site_data
      )
    end

    private

    def validate_request
      unless @request.is_a?(BuildRequest) && @request.snapshot.is_a?(Snapshot) && @config.is_a?(BuildConfig)
        error("invalid_request", "compile expects a BuildRequest containing Snapshot and BuildConfig")
        return
      end

      @config.to_h.each do |name, value|
        next if FrontMatter.valid_output_text?(value.to_s)

        error("invalid_config_character", "#{name} contains a character forbidden by XML 1.0")
      end
      if @config.syntax_profile != "ofm@1"
        error("unsupported_syntax_profile", "syntax_profile must be ofm@1")
      end
      resolve_theme_config
      resolve_content_config
      resolve_comments_config
      resolve_analytics_config
      resolve_contacts_config
      resolve_navigation_config
      @url_builder = UrlBuilder.new(origin: @config.url, baseurl: @config.baseurl)
      error("missing_origin", "production builds require a non-empty url origin") if production? && @url_builder.origin.empty?
    rescue ArgumentError => exception
      error("invalid_url_config", exception.message)
      @url_builder = UrlBuilder.new(origin: "", baseurl: "")
    end

    def resolve_theme_config
      requested = @config.theme.to_s
      requested = "minimal" if requested.empty?
      if THEMES.include?(requested)
        @theme = requested
      else
        error("invalid_theme", "theme must be one of: #{THEMES.join(', ')}")
        @theme = "minimal"
      end

      overrides = @config.features
      unless overrides.nil? || overrides.is_a?(Hash)
        error("invalid_features", "features must be a mapping of supported feature names to YAML booleans")
        overrides = {}
      end
      overrides ||= {}
      normalized = {}
      overrides.each do |key, value|
        name = key.to_s
        unless FEATURE_KEYS.include?(name)
          error("invalid_feature", "unknown feature #{name.inspect}")
          next
        end
        unless value == true || value == false
          error("invalid_feature", "feature #{name.inspect} must be a YAML boolean")
          next
        end
        normalized[name] = value
      end
      @features = THEME_FEATURE_DEFAULTS.fetch(@theme).merge(normalized).sort.to_h.freeze
    end

    def resolve_comments_config
      raw = @config.comments
      if raw.nil?
        @comments = disabled_comments_config
        return
      end
      unless raw.is_a?(Hash) && raw.keys.all? { |key| key.is_a?(String) }
        error("invalid_comments", "website.comments must be a mapping with string keys")
        @comments = disabled_comments_config
        return
      end

      unknown = raw.keys - COMMENT_KEYS
      unknown.sort.each { |key| error("invalid_comments", "unknown comments setting #{key.inspect}") }
      enabled = raw.fetch("enabled", @theme == "minimal")
      unless enabled == true || enabled == false
        error("invalid_comments", "comments.enabled must be a YAML boolean")
        enabled = false
      end

      repository = raw.key?("repository") ? raw["repository"] : @config.repository
      repository = validate_comment_text("repository", repository)
      repository_id = validate_comment_text("repository_id", raw["repository_id"])
      category = validate_comment_text("category", raw["category"])
      category_id = validate_comment_text("category_id", raw["category_id"])

      repository_valid = repository&.match?(/\A[\w.-]+\/[\w.-]+\z/)
      error("invalid_comments", "comments.repository must be an owner/repository pair") if enabled && !repository_valid
      missing_provider_fields = {
        "repository_id" => repository_id,
        "category" => category,
        "category_id" => category_id
      }.filter_map { |key, value| "comments.#{key}" if value.to_s.empty? }
      configured = enabled && repository_valid && missing_provider_fields.empty?
      if enabled && repository_valid && missing_provider_fields.any?
        warning(
          "comments_unconfigured",
          "comments are enabled but Giscus setup is incomplete; missing #{missing_provider_fields.join(', ')}"
        )
      end

      @comments = CommentsConfig.new(
        enabled: enabled,
        configured: configured,
        repository: repository.to_s,
        repository_id: repository_id.to_s,
        category: category.to_s,
        category_id: category_id.to_s,
        language: self.class.giscus_language(@config.lang),
        load: configured && production?
      )
    end

    def validate_comment_text(key, value)
      return nil if value.nil?
      unless value.is_a?(String) && FrontMatter.valid_output_text?(value) && value.length <= 256
        error("invalid_comments", "comments.#{key} must be a string of at most 256 output-safe characters")
        return nil
      end

      value.strip
    end

    def disabled_comments_config
      CommentsConfig.new(
        enabled: false,
        configured: false,
        repository: "",
        repository_id: "",
        category: "",
        category_id: "",
        language: "en",
        load: false
      )
    end

    def resolve_analytics_config
      raw = @config.analytics
      return @analytics = disabled_analytics_config if raw.nil?
      unless raw.is_a?(Hash) && raw.keys.all? { |key| key.is_a?(String) }
        error("invalid_analytics", "website.analytics must be a mapping with string keys")
        return @analytics = disabled_analytics_config
      end

      provider = raw["provider"]
      unless ANALYTICS_PROVIDERS.include?(provider)
        error("invalid_analytics", "analytics.provider must be one of: #{ANALYTICS_PROVIDERS.join(', ')}")
        return @analytics = disabled_analytics_config
      end

      identifier_key = provider == "cloudflare" ? "token" : "measurement_id"
      (raw.keys - ["provider", identifier_key]).sort.each do |key|
        error("invalid_analytics", "unknown analytics setting #{key.inspect} for provider #{provider.inspect}")
      end
      value = raw[identifier_key]
      unless value.is_a?(String) && !value.empty? && value.length <= 256 &&
          value == value.strip && !value.match?(/[\s<>"']/) && FrontMatter.valid_output_text?(value)
        error("invalid_analytics", "analytics.#{identifier_key} must be a non-empty output-safe token of at most 256 characters")
        return @analytics = disabled_analytics_config
      end
      identifier = value
      if provider == "google" && !identifier.match?(/\AG-[A-Z0-9]+\z/)
        error("invalid_analytics", "analytics.measurement_id must begin with G- and contain only uppercase ASCII letters and digits")
        return @analytics = disabled_analytics_config
      end

      @analytics = AnalyticsConfig.new(provider: provider, identifier: identifier, load: production?)
    end

    def disabled_analytics_config
      AnalyticsConfig.new(provider: "", identifier: "", load: false)
    end

    def resolve_contacts_config
      raw = @config.contacts
      return @contacts = [] if raw.nil?
      unless raw.is_a?(Array)
        error("invalid_contacts", "website.contacts must be a list of label and url mappings")
        return @contacts = []
      end
      error("invalid_contacts", "website.contacts supports at most #{MAX_CONTACTS} entries") if raw.length > MAX_CONTACTS

      @contacts = raw.first(MAX_CONTACTS).each_with_index.filter_map do |entry, index|
        unless entry.is_a?(Hash) && entry.keys.all? { |key| key.is_a?(String) }
          error("invalid_contacts", "contacts[#{index}] must be a mapping with string keys")
          next
        end
        unknown = entry.keys - CONTACT_KEYS
        unless unknown.empty?
          error("invalid_contacts", "unknown contacts[#{index}] setting #{unknown.sort.first.inspect}")
          next
        end

        label = contact_text(entry["label"], "contacts[#{index}].label", 64)
        url = contact_text(entry["url"], "contacts[#{index}].url", 2048)
        next unless label && url
        unless contact_url?(url)
          error("invalid_contacts", "contacts[#{index}].url must use https, mailto, or tel")
          next
        end

        contact = { "label" => label, "url" => url }
        icon = contact_icon(label, url)
        contact["icon"] = icon if icon
        contact
      end
    end

    def resolve_navigation_config
      raw = @config.navigation
      return @navigation_config = default_navigation_config if raw.nil?
      unless raw.is_a?(Hash) && raw.keys.all? { |key| key.is_a?(String) }
        error("invalid_navigation_config", "website.navigation must be a mapping with string keys")
        return @navigation_config = default_navigation_config
      end

      (raw.keys - NAVIGATION_KEYS).sort.each do |key|
        error("invalid_navigation_config", "unknown website.navigation setting #{key.inspect}")
      end

      normalized = NAVIGATION_BUILTINS.to_h do |name, defaults|
        value = if raw.key?(name)
          normalize_navigation_override(raw[name], "website.navigation.#{name}", defaults)
        else
          defaults.dup
        end
        [name, value]
      end
      normalized["portfolio"] = if raw.key?("portfolio")
        normalize_portfolio_navigation(raw["portfolio"])
      else
        PORTFOLIO_NAVIGATION_DEFAULTS.dup
      end
      folders = raw.fetch("folders", [])
      unless folders.is_a?(Array)
        error("invalid_navigation_config", "website.navigation.folders must be an array")
        folders = []
      end
      normalized["folders"] = folders.each_with_index.filter_map do |entry, index|
        normalize_navigation_folder(entry, index)
      end
      @navigation_config = DeepFreeze.call(normalized)
    end

    def default_navigation_config
      DeepFreeze.call(
        NAVIGATION_BUILTINS.transform_values(&:dup).merge(
          "portfolio" => PORTFOLIO_NAVIGATION_DEFAULTS.dup,
          "folders" => []
        )
      )
    end

    def normalize_portfolio_navigation(value)
      path = "website.navigation.portfolio"
      unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
        error("invalid_navigation_config", "#{path} must be a mapping with string keys")
        return PORTFOLIO_NAVIGATION_DEFAULTS.dup
      end

      (value.keys - PORTFOLIO_NAVIGATION_KEYS).sort.each do |key|
        error("invalid_navigation_config", "unknown #{path} setting #{key.inspect}")
      end
      normalized = normalize_navigation_fields(value, path, PORTFOLIO_NAVIGATION_DEFAULTS)
      return normalized unless value.key?("path")

      folder_path = normalize_navigation_folder_path(value["path"], "#{path}.path")
      folder_path ? normalized.merge("path" => folder_path) : normalized
    end

    def normalize_navigation_override(value, path, defaults)
      unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
        error("invalid_navigation_config", "#{path} must be a mapping with string keys")
        return defaults.dup
      end

      (value.keys - NAVIGATION_OVERRIDE_KEYS).sort.each do |key|
        error("invalid_navigation_config", "unknown #{path} setting #{key.inspect}")
      end
      normalize_navigation_fields(value, path, defaults)
    end

    def normalize_navigation_folder(value, index)
      path = "website.navigation.folders[#{index}]"
      unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
        error("invalid_navigation_config", "#{path} must be a mapping with string keys")
        return nil
      end

      (value.keys - NAVIGATION_FOLDER_KEYS).sort.each do |key|
        error("invalid_navigation_config", "unknown #{path} setting #{key.inspect}")
      end
      folder_path = normalize_navigation_folder_path(value["path"], "#{path}.path")
      return nil unless folder_path

      normalize_navigation_fields(value, path, CUSTOM_NAVIGATION_DEFAULTS).merge("path" => folder_path)
    end

    def normalize_navigation_fields(value, path, defaults)
      normalized = defaults.dup
      if value.key?("label")
        label = value["label"]
        if FrontMatter.valid_output_text?(label) && !label.strip.empty?
          normalized["label"] = label
        else
          error("invalid_navigation_config", "#{path}.label must be a non-empty string containing only output-safe Unicode characters")
        end
      end
      if value.key?("order")
        order = value["order"]
        if order.is_a?(Integer)
          normalized["order"] = order
        else
          error("invalid_navigation_config", "#{path}.order must be an integer")
        end
      end
      if value.key?("visible")
        visible = value["visible"]
        if visible == true || visible == false
          normalized["visible"] = visible
        else
          error("invalid_navigation_config", "#{path}.visible must be a YAML boolean")
        end
      end
      normalized
    end

    def normalize_navigation_folder_path(value, path)
      unless FrontMatter.valid_output_text?(value)
        error("invalid_navigation_config", "#{path} must be a string")
        return nil
      end
      if value.empty? || value.start_with?("/", "\\") || value.include?("\\") || value != value.unicode_normalize(:nfc)
        error("invalid_navigation_config", "#{path} must be a normalized vault-relative POSIX directory")
        return nil
      end
      segments = value.split("/", -1)
      if segments.any? { |segment| segment.empty? || segment == "." || segment == ".." }
        error("invalid_navigation_config", "#{path} must not contain empty or traversal segments")
        return nil
      end
      value
    rescue EncodingError
      error("invalid_navigation_config", "#{path} must contain valid Unicode")
      nil
    end

    def contact_text(value, key, limit)
      unless value.is_a?(String) && !value.strip.empty? && value.length <= limit && FrontMatter.valid_output_text?(value)
        error("invalid_contacts", "#{key} must be a non-empty output-safe string of at most #{limit} characters")
        return nil
      end

      value.strip
    end

    def contact_url?(value)
      uri = URI.parse(value)
      case uri.scheme&.downcase
      when "https"
        !uri.host.to_s.empty?
      when "mailto", "tel"
        !uri.opaque.to_s.empty? && !uri.opaque.match?(/\s/)
      else
        false
      end
    rescue URI::InvalidURIError
      false
    end

    def contact_icon(label, value)
      uri = URI.parse(value)
      scheme = uri.scheme&.downcase
      return "email" if scheme == "mailto"
      return "phone" if scheme == "tel"

      host = uri.host.to_s.downcase.delete_suffix(".")
      CONTACT_HOST_ICONS.each do |domain, icon|
        return icon if host == domain || host.end_with?(".#{domain}")
      end

      normalized_label = label.downcase.strip
      return "mastodon" if normalized_label.match?(/\bmastodon\b/)
      return "rss" if normalized_label.match?(/\b(?:rss|feed|atom)\b/) || feed_url_path?(uri.path)
      return "website" if normalized_label.match?(/\A(?:website|web[ -]?site|site|homepage|home[ -]?page)\z/)

      nil
    rescue URI::InvalidURIError
      nil
    end

    def feed_url_path?(path)
      path.to_s.downcase.match?(%r{(?:\A|/)(?:feed|rss|atom)(?:\.(?:xml|rss|atom))?(?:/|\z)})
    end

    def resolve_content_config
      resolution = ContentPolicy.resolve(@config.content)
      @diagnostics.concat(resolution.diagnostics)
      @content_policy = resolution.policy
      @content = @content_policy.settings
    end

    def index_snapshot
      seen = {}
      Array(@request.snapshot&.entries).sort_by { |entry| entry.path.to_s.b }.each do |entry|
        path = validated_path(entry)
        next unless path
        next if path.start_with?(TRANSLATIONS_DIRECTORY)

        collision = path.unicode_normalize(:nfc).downcase(:fold)
        if seen.key?(collision)
          error("path_collision", "snapshot paths are equivalent under NFC/case-folding", path)
          error("route_collision", "note paths would map to equivalent public routes", path) if entry.kind.to_sym == :note
          next
        end
        seen[collision] = path

        case entry.kind.to_sym
        when :note
          unless path.end_with?(NOTE_EXTENSION)
            error("invalid_note_path", "note paths must end in .md", path)
            next
          end
          @all_note_paths << path
          parsed = FrontMatter.parse(path, entry.bytes.to_s)
          @diagnostics.concat(parsed.diagnostics)
          published = @content_policy.publish?(path, parsed.properties)
          if parsed.properties.key?("navigation") && !published
            error(
              "unpublished_page_navigation",
              "navigation frontmatter is only supported on published pages",
              path
            )
          end
          next unless published
          unless FrontMatter.valid_output_text?(parsed.body)
            error("invalid_character", "public note body contains a character forbidden by XML 1.0", path)
            next
          end

          external_document = entry.external_document
          if external_document && !parsed.body.strip.empty?
            error(
              "github_markdown_body_conflict",
              "a github_markdown project wrapper must have an empty local body",
              path
            )
          end
          @notes[path] = MutableNote.new(
            id: path,
            entry: entry,
            properties: parsed.properties,
            body: external_document ? external_document.markdown : parsed.body,
            occurrences: [],
            outline: [],
            feature_flags: {},
            external_document: external_document
          )
        when :attachment
          @attachments[path] = entry
          basename = File.basename(path).unicode_normalize(:nfc).downcase(:fold)
          @attachment_basename_index[basename] << path
        when :locale_manifest
          # Locale manifests are compiler metadata, never public vault assets.
        when :symlink
          error("symlink_rejected", "symlinks are not accepted in a vault snapshot", path)
        else
          error("invalid_entry_kind", "snapshot entry kind must be note, attachment, or locale_manifest", path)
        end
      end
    end

    def parse_public_notes
      error("missing_public_notes", "the content directory must contain at least one public note", nil) if @notes.empty?
    end

    def establish_identities
      @basename_index = Hash.new { |hash, key| hash[key] = [] }
      @notes.each_value do |note|
        route = note.properties["permalink"]
        if route
          route = @url_builder.validate_permalink(route)
          error("invalid_permalink", "permalink must be a concrete site path beginning and ending with /", note.id) unless route
        else
          route = @url_builder.route_for_note(note.id)
        end
        note.route = route || @url_builder.route_for_note(note.id)
        if note.id == "index.md" && note.route != "/"
          error("invalid_home_permalink", "the public root index must publish at /", note.id)
        end
        note.updated = note.properties["updated"]
        note.created = deterministic_created(note)
        if note.id == "index.md" && note.properties["content_type"] && note.properties["content_type"] != "page"
          error("invalid_root_content_type", "the public root index must have content_type: page", note.id)
        end
        note.content_type = effective_content_type(note)
        note.nav_order = note.properties["nav_order"]
        note.nav_exclude = note.properties["nav_exclude"] == true
        note.published_at = published_at(note)
        if note.content_type == "post" && note.published_at.nil?
          error_or_warning(
            "missing_post_date",
            "published posts require date, created, or Git first commit time",
            note.id,
            nil,
            fatal: production?
          )
        end
        basename = File.basename(note.id, NOTE_EXTENSION).unicode_normalize(:nfc).downcase(:fold)
        @basename_index[basename] << note.id
      end

      note_routes = {}
      @notes.each_value do |note|
        key = @url_builder.collision_key(note.route)
        if note_routes.key?(key)
          error("route_collision", "public notes map to equivalent routes", note.id)
        else
          note_routes[key] = note.id
        end
      end
    end

    def published_at(note)
      return nil unless note.content_type == "post"

      note.properties["date"] || note.properties["created"] || note.entry.first_committed_at
    end

    def effective_content_type(note)
      classified = @content_policy.classify(note.id, note.properties)
      return classified unless portfolio_note?(note.id)

      explicit = note.properties["content_type"]
      if explicit && explicit != "page"
        error(
          "portfolio_content_type_conflict",
          "published notes inside the portfolio path must use content_type: page",
          note.id
        )
      end
      "page"
    end

    def portfolio_note?(note_id)
      return false unless @theme == "minimal"

      path = @navigation_config.fetch("portfolio").fetch("path")
      note_id.start_with?("#{path}/")
    end

    def parse_markdown_once
      @notes.values.sort_by(&:id).each do |note|
        prepared = OfmScanner.prepare(note.external_document ? "" : note.body)
        note.scanner = prepared
        merged_tags = (Array(note.properties["tags"]) + prepared.tags).uniq.sort
        note.properties = note.properties.merge("tags" => merged_tags)
        markdown = (note.external_document ? note.body : prepared.markdown).dup.force_encoding(Encoding::UTF_8)
        options = note.external_document ? REMOTE_COMMONMARK_OPTIONS : COMMONMARK_OPTIONS
        note.document = Commonmarker.parse(markdown, options: options)
        if note.external_document
          rewrite_github_markdown_urls(note)
          note.body = note.document.to_commonmark(options: { render: { width: 0 } })
        end
        note.has_h1 = note.document.any? { |node| node.type == :heading && node.header_level == 1 }
        note.title = note.properties["title"] || first_h1(note.document) || filename_title(note.id)
        build_anchor_registry(note)
        annotate_occurrences(note) unless note.external_document
        annotate_frontmatter_topics(note)
        annotate_code_markers(note)
      end
    end

    def rewrite_github_markdown_urls(note)
      note.document.walk.each do |node|
        next unless %i[link image].include?(node.type)

        rewritten = github_markdown_url(note, node.url.to_s, image: node.type == :image)
        node.url = rewritten if rewritten
      end
    end

    def github_markdown_url(note, raw_url, image:)
      return raw_url if raw_url.empty? || raw_url.start_with?("#")

      uri = parse_github_markdown_uri(raw_url)
      if uri.scheme
        if image && uri.scheme.downcase != "https"
          error("invalid_github_markdown_image", "GitHub Markdown images must use HTTPS", note.id)
          return note.external_document.source_url
        end
        return raw_url
      end
      if uri.host || raw_url.start_with?("//")
        error("invalid_github_markdown_link", "protocol-relative GitHub Markdown links are not supported", note.id)
        return note.external_document.source_url
      end

      decoded = URI.decode_uri_component(uri.path.to_s)
      if decoded.include?("\\") || decoded.include?("\0")
        error("invalid_github_markdown_link", "GitHub Markdown links must use safe POSIX paths", note.id)
        return note.external_document.source_url
      end
      base = decoded.start_with?("/") ? "" : File.dirname(note.external_document.path)
      candidate = Pathname.new(File.join(base, decoded.delete_prefix("/"))).cleanpath.to_s.tr("\\", "/")
      if candidate == ".." || candidate.start_with?("../")
        error("invalid_github_markdown_link", "GitHub Markdown links must not escape the repository root", note.id)
        return note.external_document.source_url
      end

      encoded = candidate == "." ? "" : candidate.split("/").map { |part| URI.encode_uri_component(part) }.join("/")
      repository = note.external_document.repository
      commit = note.external_document.resolved_commit
      target = if image
        "https://raw.githubusercontent.com/#{repository}/#{commit}"
      else
        directory = uri.path.to_s.end_with?("/")
        "https://github.com/#{repository}/#{directory ? 'tree' : 'blob'}/#{commit}"
      end
      target = "#{target}/#{encoded}" unless encoded.empty?
      target = "#{target}?#{uri.query}" if uri.query
      target = "#{target}##{uri.fragment}" if uri.fragment
      target
    rescue URI::InvalidURIError, ArgumentError
      error("invalid_github_markdown_link", "GitHub Markdown contains an invalid relative URL", note.id)
      note.external_document.source_url
    end

    def parse_github_markdown_uri(raw_url)
      ascii_url = if raw_url.ascii_only?
        raw_url
      else
        raw_url.gsub(/[^\x00-\x7F]/) do |character|
          character.bytes.map { |byte| format("%%%02X", byte) }.join
        end
      end
      URI.parse(ascii_url)
    end

    def build_anchor_registry(note)
      used_heading_ids = Hash.new(0)
      identifiers = {}
      heading_stack = []
      anchors = []
      outline = []

      note.document.select { |node| node.type == :heading }.each do |heading|
        label = plain_node_text(heading).strip
        level = heading.header_level
        heading_stack.pop while heading_stack.last && heading_stack.last.fetch(:level) >= level
        chain = heading_stack.map { |item| item.fetch(:label) } + [label]
        base = @url_builder.slug(label)
        used_heading_ids[base] += 1
        duplicate_number = note.external_document ? used_heading_ids[base] - 1 : used_heading_ids[base]
        identifier = used_heading_ids[base] == 1 ? base : "#{base}-#{duplicate_number}"
        anchor = Anchor.new(kind: :heading, id: identifier, label: label, level: level, chain: chain)
        anchors << anchor
        identifiers[identifier] = anchor
        outline << { "id" => identifier, "label" => label, "level" => level }
        heading_stack << { level: level, label: label }
      end

      note.scanner.block_ids.each do |identifier, line_number|
        if identifiers.key?(identifier)
          error(
            "anchor_collision",
            "block ID collides with an existing heading or block anchor",
            note.id,
            SourceSpan.new(start_line: line_number, start_column: 1, end_line: line_number, end_column: 1)
          )
          next
        end

        anchor = Anchor.new(kind: :block, id: identifier, label: identifier, level: nil, chain: nil)
        anchors << anchor
        identifiers[identifier] = anchor
      end

      note.anchors = anchors
      note.outline = outline
    end

    def annotate_occurrences(note)
      note.scanner.embeds.each do |embed|
        note.occurrences << Occurrence.new(
          index: note.occurrences.length,
          source_id: note.id,
          raw_target: embed.target,
          display: nil,
          kind: :embed,
          syntax: :ofm_embed,
          source_span: embed.source_span,
          scanner_token: embed.token
        )
      end

      note.scanner.iframes.each do |iframe|
        descriptor = ExternalMedia.resolve_iframe(iframe.html, closed: iframe.closed)
        note.occurrences << Occurrence.new(
          index: note.occurrences.length,
          source_id: note.id,
          raw_target: descriptor.source_url,
          display: descriptor.title,
          kind: :embed,
          syntax: :html_iframe,
          source_span: iframe.source_span,
          scanner_token: iframe.token,
          resolved_type: :external_media,
          external_media: descriptor
        )
      rescue ExternalMedia::Invalid => exception
        error("invalid_external_media", exception.message, note.id, iframe.source_span)
      end

      note.scanner.wikilinks.each do |link|
        note.occurrences << Occurrence.new(
          index: note.occurrences.length,
          source_id: note.id,
          raw_target: link.target,
          display: link.display,
          kind: :link,
          syntax: :wikilink,
          source_span: link.source_span,
          scanner_token: link.token
        )
      end

      note.document.walk do |node|
        case node.type
        when :link, :image
          raw_url = node.url.to_s
          next if raw_url.empty?
          if external_url?(raw_url, note.id, source_span(node.source_position), media: node.type == :image)
            annotate_external_media(note, node, raw_url) if node.type == :image
            next
          end

          display = plain_node_text(node)
          occurrence_target = raw_url
          if node.type == :image && (dimension = display.match(/\A(.*)\|(\d+(?:x\d+)?)\z/m))
            display = dimension[1]
            occurrence_target = "#{raw_url}|#{dimension[2]}"
          end

          occurrence = Occurrence.new(
            index: note.occurrences.length,
            source_id: note.id,
            raw_target: occurrence_target,
            display: display,
            kind: node.type == :image ? :embed : :link,
            syntax: node.type == :image ? :markdown_image : :markdown_link,
            source_span: source_span(node.source_position)
          )
          note.occurrences << occurrence
          node.url = token_url(occurrence.index)
        end
      end
    end

    def annotate_external_media(note, node, raw_url)
      descriptor = ExternalMedia.resolve(raw_url)
      return unless descriptor

      if descriptor.kind != :image && node.parent&.type != :paragraph
        error(
          "invalid_external_media",
          "block external media must use a standalone Markdown image",
          note.id,
          source_span(node.source_position)
        )
        return
      end

      display = plain_node_text(node)
      options = {}
      if descriptor.kind == :image
        display, options = external_image_display(display)
      end
      occurrence = Occurrence.new(
        index: note.occurrences.length,
        source_id: note.id,
        raw_target: raw_url,
        display: display,
        kind: :embed,
        syntax: :markdown_image,
        source_span: source_span(node.source_position),
        resolved_type: :external_media,
        options: options,
        external_media: descriptor
      )
      note.occurrences << occurrence
      node.url = token_url(occurrence.index)
    rescue ExternalMedia::Invalid => exception
      error("invalid_external_media", exception.message, note.id, source_span(node.source_position))
    end

    def external_image_display(display)
      if (dimension = display.match(/\A(\d+)(?:x(\d+))?\z/))
        return ["", { "width" => dimension[1].to_i, "height" => dimension[2]&.to_i }.compact]
      end
      if (dimension = display.match(/\A(.*)\|(\d+)(?:x(\d+))?\z/m))
        return [dimension[1], { "width" => dimension[2].to_i, "height" => dimension[3]&.to_i }.compact]
      end

      [display, {}]
    end

    def annotate_frontmatter_topics(note)
      note.topics = Array(note.properties["tags"]).map do |tag|
        Topic.new(kind: "tag", name: tag)
      end

      { "author" => "author", "categories" => "category" }.each do |property, kind|
        Array(note.properties[property]).each do |value|
          link = FrontMatter.parse_wiki_link(value)
          unless link
            note.topics << Topic.new(kind: kind, name: value)
            next
          end
          target, display = link

          occurrence = Occurrence.new(
            index: note.occurrences.length,
            source_id: note.id,
            raw_target: target,
            display: display,
            kind: :link,
            syntax: :frontmatter_topic,
            property: property
          )
          note.occurrences << occurrence
          note.topics << Topic.new(kind: kind, occurrence: occurrence)
        end
      end
    end

    def resolve_all_occurrences
      @notes.values.sort_by(&:id).each do |note|
        note.occurrences.each do |occurrence|
          resolve_occurrence(note, occurrence) unless occurrence.resolved_type == :external_media
          if occurrence.resolved_type == :note
            @relations << Relation.new(
              source_id: note.id,
              target_id: occurrence.target_id,
              kind: occurrence.kind,
              fragment: occurrence.fragment,
              source_span: occurrence.source_span
            )
          elsif occurrence.resolved_type == :attachment
            @copied_asset_paths << occurrence.target_path
          end
        end

        image = note.properties["image"]
        next unless image

        resolved, ambiguous = resolve_attachment_path(note.id, image)
        if ambiguous
          error_or_warning("ambiguous_attachment", "image property matches more than one attachment", note.id, nil, fatal: production?)
        elsif resolved && MediaPolicy.kind(resolved) == :image
          @copied_asset_paths << resolved
          @image_paths[note.id] = resolved
        else
          error_or_warning("missing_image_property", "image property does not resolve to an attachment", note.id, nil, fatal: production?)
        end
      end
    end

    def resolve_occurrence(note, occurrence)
      target_text, fragment, options = split_target(occurrence.raw_target, occurrence.kind)
      occurrence.fragment = fragment
      occurrence.options = options

      if target_text.empty?
        occurrence.resolved_type = :note
        occurrence.target_id = note.id
        resolve_occurrence_fragment(note, occurrence)
        return
      end

      if local_target_escapes_vault?(note.id, target_text)
        occurrence.unresolved = true
        error_or_warning(
          "path_escape",
          "local target escapes the vault root",
          note.id,
          occurrence.source_span,
          fatal: production?
        )
        return
      end

      note_target, ambiguous = resolve_note_path(note.id, target_text)
      if ambiguous
        occurrence.unresolved = true
        code = "ambiguous_target"
        if production?
          error(code, "target is ambiguous", note.id, occurrence.source_span)
        else
          warning(code, "target is ambiguous; rendered as a placeholder", note.id, occurrence.source_span)
        end
        return
      end

      if note_target
        occurrence.resolved_type = :note
        occurrence.target_id = note_target
        resolve_occurrence_fragment(@notes.fetch(note_target), occurrence)
        return
      end

      if occurrence.syntax == :frontmatter_topic
        occurrence.unresolved = true
        warning(
          "unresolved_property_link",
          "#{occurrence.property} wiki link target is missing or not a public note",
          note.id,
          occurrence.source_span
        )
        return
      end

      attachment_target, ambiguous_attachment = resolve_attachment_path(note.id, target_text)
      if ambiguous_attachment
        occurrence.unresolved = true
        error_or_warning(
          "ambiguous_attachment",
          "attachment target is ambiguous",
          note.id,
          occurrence.source_span,
          fatal: production?
        )
        return
      end

      if attachment_target
        unless MediaPolicy.kind(attachment_target)
          occurrence.unresolved = true
          error(
            "unsupported_attachment",
            "attachment type is not supported for publication",
            note.id,
            occurrence.source_span
          )
          return
        end
        occurrence.resolved_type = :attachment
        occurrence.target_path = attachment_target
        return
      end

      occurrence.unresolved = true
      if occurrence.kind == :embed
        error_or_warning("missing_embed", "embed target is missing or not public", note.id, occurrence.source_span, fatal: production?)
      else
        warning("unresolved_link", "link target is missing or not public", note.id, occurrence.source_span)
      end
    end

    def resolve_occurrence_fragment(target_note, occurrence)
      fragment = occurrence.fragment
      return unless fragment && !fragment.empty?

      anchor = find_fragment_anchor(target_note, fragment)
      if anchor
        occurrence.anchor_id = anchor.id
        return
      end

      occurrence.unresolved = true
      if occurrence.kind == :embed
        error_or_warning(
          "missing_embed_fragment",
          "embed fragment does not exist in the public target",
          occurrence.source_id,
          occurrence.source_span,
          fatal: production?
        )
      else
        warning(
          "unresolved_fragment",
          "link fragment does not exist in the public target; rendered as unresolved",
          occurrence.source_id,
          occurrence.source_span
        )
      end
    end

    def find_fragment_anchor(note, raw_fragment)
      anchors = note.anchors || []
      fragment = safe_decode(raw_fragment).unicode_normalize(:nfc)
      if fragment.start_with?("^")
        identifier = fragment.delete_prefix("^")
        return anchors.find { |anchor| anchor.kind == :block && anchor.id == identifier }
      end

      direct = fragment
      by_id = anchors.find { |anchor| anchor.kind == :heading && anchor.id == direct }
      return by_id if by_id

      chain = fragment.split("#").map(&:strip).reject(&:empty?).map { |label| @url_builder.slug(label) }
      return nil if chain.empty?

      anchors.find do |anchor|
        next false unless anchor.kind == :heading

        anchor_chain = anchor.chain.map { |label| @url_builder.slug(label) }
        anchor_chain.last(chain.length) == chain
      end
    end

    def detect_embed_cycles
      graph = Hash.new { |hash, key| hash[key] = [] }
      @relations.each do |relation|
        graph[relation.source_id] << relation.target_id if relation.kind == :embed
      end

      state = {}
      stack = []
      visit = lambda do |id|
        return if state[id] == :done
        if state[id] == :visiting
          cycle = stack.drop_while { |candidate| candidate != id } + [id]
          error_or_warning("embed_cycle", "embed cycle detected: #{cycle.join(" -> ")}", id, nil, fatal: production?)
          return
        end

        state[id] = :visiting
        stack << id
        graph[id].sort.each { |target| visit.call(target) }
        stack.pop
        state[id] = :done
      end
      @notes.keys.sort.each { |id| visit.call(id) }
    end

    def render_authored_documents
      @notes.values.sort_by(&:id).each do |note|
        options = note.external_document ? REMOTE_COMMONMARK_OPTIONS : COMMONMARK_OPTIONS
        html = note.document.to_html(options: options, plugins: COMMONMARK_PLUGINS)
        fragment = Nokogiri::HTML5.fragment(html)
        bind_occurrence_nodes(note, fragment)
        normalize_document(note, fragment)
        note.base_fragment = fragment

        authored = fragment.dup
        authored.css("website-embed").remove
        note.authored_text = visible_text(authored)
        note.preview = truncate(note.properties["description"] || note.authored_text, 240)
        note.feature_flags = {
          "math" => !fragment.css("[data-math-style], .math, math").empty? || note.body.match?(/\$[^$]+\$/),
          "mermaid" => !fragment.css("pre code.language-mermaid").empty?
        }
      end
    end

    def merge_content_features
      content_features = {
        "math" => @notes.values.any? { |note| note.feature_flags["math"] },
        "mermaid" => @notes.values.any? { |note| note.feature_flags["mermaid"] }
      }
      @features = @features.merge(content_features).sort.to_h.freeze
    end

    def bind_occurrence_nodes(note, fragment)
      note.occurrences.select { |occurrence| occurrence.syntax == :wikilink }.each do |occurrence|
        node = fragment.at_css("a[data-website-wikilink-token='#{occurrence.scanner_token}']")
        node["data-website-occurrence"] = occurrence.index.to_s if node
      end

      note.occurrences.select { |occurrence| occurrence.syntax == :ofm_embed }.each do |occurrence|
        node = fragment.at_css("website-ofm-embed[data-token='#{occurrence.scanner_token}']")
        node["data-website-occurrence"] = occurrence.index.to_s if node
      end

      note.occurrences.select { |occurrence| occurrence.syntax == :html_iframe }.each do |occurrence|
        node = fragment.at_css("website-ofm-iframe[data-token='#{occurrence.scanner_token}']")
        node["data-website-occurrence"] = occurrence.index.to_s if node
      end

      note.occurrences.select { |occurrence| %i[markdown_link markdown_image].include?(occurrence.syntax) }.each do |occurrence|
        selector = occurrence.syntax == :markdown_image ? "img[src='#{token_url(occurrence.index)}']" : "a[href='#{token_url(occurrence.index)}']"
        node = fragment.at_css(selector)
        node["data-website-occurrence"] = occurrence.index.to_s if node
      end

      note.occurrences.each do |occurrence|
        node = fragment.at_css("[data-website-occurrence='#{occurrence.index}']")
        next unless node

        transform_reference_node(note, occurrence, node)
      end
      promote_embed_placeholders(fragment)
    end

    def promote_embed_placeholders(fragment)
      fragment.css("p").to_a.each do |paragraph|
        next unless paragraph.children.any? { |child| block_embed_node?(child) }

        replacement = Nokogiri::HTML5.fragment("")
        inline = new_paragraph_like(paragraph)
        discard_break = false
        paragraph.children.to_a.each do |child|
          if block_embed_node?(child)
            replacement.add_child(inline) if meaningful_paragraph?(inline)
            inline = new_paragraph_like(paragraph)
            replacement.add_child(child.unlink)
            discard_break = true
          elsif discard_break && (child.name == "br" || (child.text? && child.text.strip.empty?))
            child.unlink
          else
            discard_break = false
            inline.add_child(child.unlink)
          end
        end
        replacement.add_child(inline) if meaningful_paragraph?(inline)
        paragraph.replace(replacement)
      end
      fragment.css("p").each { |paragraph| paragraph.remove unless meaningful_paragraph?(paragraph) }
    end

    def block_embed_node?(node)
      return false unless node.element?
      return true if node.name == "website-embed"

      classes = node["class"].to_s.split
      classes.any? do |name|
        %w[website-external-player website-external-video website-external-frame website-tweet].include?(name)
      end
    end

    def new_paragraph_like(source)
      paragraph = Nokogiri::XML::Node.new("p", source.document)
      source.attribute_nodes.each { |attribute| paragraph[attribute.name] = attribute.value }
      paragraph
    end

    def meaningful_paragraph?(paragraph)
      paragraph.children.any? { |child| child.element? || child.text.strip != "" }
    end

    def transform_reference_node(note, occurrence, node)
      if occurrence.unresolved
        replacement = Nokogiri::XML::Node.new("span", node.document)
        replacement["class"] = occurrence.kind == :embed ? "website-embed website-embed--unresolved website-unresolved" : "website-link website-link--unresolved website-unresolved"
        replacement["role"] = "status"
        replacement.content = occurrence.display || occurrence.raw_target
        node.replace(replacement)
        return
      end

      if occurrence.resolved_type == :note
        target = @notes.fetch(occurrence.target_id)
        anchor = occurrence.anchor_id ? "^#{occurrence.anchor_id}" : occurrence.fragment
        href = @url_builder.href(target.route) + @url_builder.fragment(anchor)
        if occurrence.kind == :embed
          placeholder = Nokogiri::XML::Node.new("website-embed", node.document)
          placeholder["data-source-id"] = target.id
          placeholder["data-fragment"] = occurrence.fragment.to_s
          placeholder["data-anchor-id"] = occurrence.anchor_id.to_s if occurrence.anchor_id
          placeholder["data-href"] = href
          node.replace(placeholder)
        else
          node.name = "a"
          node["href"] = href
          node["class"] = [node["class"], "website-link"].compact.join(" ")
          node["data-note-id"] = target.id
          node.remove_attribute("data-website-occurrence")
        end
      elsif occurrence.resolved_type == :attachment
        transform_attachment_node(occurrence, node)
      elsif occurrence.resolved_type == :external_media
        transform_external_media_node(occurrence, node)
      end
    end

    def transform_external_media_node(occurrence, node)
      descriptor = occurrence.external_media
      if descriptor.kind != :image && node.parent&.name != "p"
        error(
          "invalid_external_media",
          "block external media must use a standalone Markdown image",
          occurrence.source_id,
          occurrence.source_span
        )
        return
      end

      replacement = case descriptor.kind
      when :image
        image_node(node.document, occurrence, descriptor.source_url)
      when :direct_video
        external_video_node(node.document, descriptor, occurrence.display)
      when :player
        external_player_node(node.document, descriptor, occurrence.display)
      when :web_frame
        external_web_frame_node(node.document, descriptor)
      when :tweet
        tweet_node(node.document, descriptor)
      else
        raise "unsupported external media descriptor: #{descriptor.kind.inspect}"
      end
      node.replace(replacement)
    end

    def transform_attachment_node(occurrence, node)
      entry = @attachments.fetch(occurrence.target_path)
      route = @url_builder.attachment_route(occurrence.target_path)
      href = @url_builder.href(route)

      kind = MediaPolicy.kind(occurrence.target_path)
      media_type = MediaPolicy.media_type(occurrence.target_path, fallback: entry.media_type)
      replacement = if occurrence.kind == :link || kind == :download
        download_card(node.document, occurrence.target_path, href, media_type)
      elsif kind == :image
        image_node(node.document, occurrence, href)
      elsif kind == :audio
        media_node(node.document, "audio", href, media_type)
      elsif kind == :video
        media_node(node.document, "video", href, media_type)
      elsif kind == :pdf
        pdf_node(node.document, occurrence, href)
      else
        unresolved_attachment_node(node.document, occurrence.target_path)
      end
      node.replace(replacement)
    end

    def normalize_document(note, fragment)
      fragment.xpath(".//comment()").remove
      assign_heading_ids(note, fragment)
      assign_block_ids(note, fragment)
      annotate_task_states(note, fragment)
      annotate_code_blocks(note, fragment)
      transform_callouts(fragment)
      fragment.css("pre code.language-mermaid").each { |node| node.parent["data-website-mermaid"] = "true" }
      fragment.css("a[href]").each do |link|
        next unless link["href"].match?(%r{\Ahttps?://}i)

        link["rel"] = "noopener noreferrer"
      end
      fragment.css("[data-sourcepos]").remove_attr("data-sourcepos")
    end

    def assign_heading_ids(note, fragment)
      headings = note.anchors.select { |anchor| anchor.kind == :heading }
      source_headings = note.document.select { |node| node.type == :heading }
      headings.zip(source_headings).each do |anchor, source|
        heading = fragment.at_css("h#{anchor.level}[data-sourcepos='#{sourcepos_value(source.source_position)}']")
        next unless heading

        heading["id"] = anchor.id
        heading.css("a.anchor").each do |permalink|
          permalink["href"] = "##{anchor.id}"
          label = permalink["data-heading-content"] || anchor.label
          permalink["aria-label"] = "Link to heading '#{label}'"
        end
      end
    end

    def assign_block_ids(note, fragment)
      block_ids = note.anchors.select { |anchor| anchor.kind == :block }.map(&:id)
      fragment.css("[data-website-block-id]").each do |marker|
        parent = marker.parent
        identifier = marker["data-website-block-id"]
        if parent&.element? && block_ids.include?(identifier)
          standalone = parent.children.all? do |child|
            child == marker || (child.text? && child.text.strip.empty?)
          end
          previous = parent.previous_element if standalone
          if previous
            if previous["id"].to_s.empty?
              previous["id"] = identifier
            else
              # A heading already owns its public heading ID. Preserve it and
              # place a second scroll target immediately before the block;
              # overwriting the heading ID would break its outline and links.
              anchor = Nokogiri::XML::Node.new("span", previous.document)
              anchor["id"] = identifier
              anchor["class"] = "website-block-anchor"
              anchor["aria-hidden"] = "true"
              previous.add_previous_sibling(anchor)
            end
            parent.remove
          else
            parent["id"] = identifier
          end
        end
        marker.remove
      end
    end

    def annotate_task_states(note, fragment)
      lines = note.scanner.markdown.lines
      fragment.css("li.task-list-item[data-sourcepos]").each do |item|
        position = parse_sourcepos_value(item["data-sourcepos"])
        line = lines.fetch(position.fetch(:start_line) - 1, "")
        source = line[(position.fetch(:start_column) - 1)..].to_s
        match = source.match(/\A(?:[-+*]|\d+[.)])\s+\[([^\]\r\n])\](?=\s|$)/)
        next unless match

        state = match[1]
        input = item.at_css("input.task-list-item-checkbox")
        next unless input
        item["data-task"] = state
        input["data-task"] = state
        input["aria-label"] = "Task state: #{task_state_label(state)}"
        input.remove_attribute("checked") unless state.match?(/\A[xX]\z/)
      end
    end

    def task_state_label(state)
      {
        " " => "open",
        "x" => "completed",
        "X" => "completed",
        "?" => "question",
        "/" => "in progress",
        "-" => "cancelled"
      }.fetch(state, state)
    end

    def transform_callouts(fragment)
      fragment.css("blockquote[data-sourcepos]").to_a.reverse_each do |blockquote|
        first = blockquote.at_css("p")
        next unless first

        text_node = first.xpath(".//text()").first
        next unless text_node
        match = text_node.text.match(/\A\s*\[!([a-z0-9_-]+)\]([+-])?\s*([^\n]*)/i)
        next unless match

        type = match[1].downcase.gsub(/[^a-z0-9_-]/, "")
        fold = match[2]
        title = match[3].to_s.strip
        title = type.tr("-_", " ").split.map(&:capitalize).join(" ") if title.empty?
        text_node.content = text_node.text.sub(match[0], "").sub(/\A\s+/, "")

        wrapper = Nokogiri::XML::Node.new(fold ? "details" : "aside", blockquote.document)
        wrapper["class"] = "website-callout website-callout--#{type} callout"
        wrapper["data-callout"] = type
        wrapper["role"] = "note" unless fold
        wrapper["open"] = "open" if fold == "+"
        transfer_replacement_identity(blockquote, wrapper)
        header = Nokogiri::XML::Node.new(fold ? "summary" : "header", blockquote.document)
        header["class"] = "website-callout__title callout__title"
        header.content = title
        wrapper.add_child(header)
        content = Nokogiri::XML::Node.new("div", blockquote.document)
        content["class"] = "website-callout__content callout__content"
        blockquote.children.to_a.each { |child| content.add_child(child.unlink) }
        content.css("p").first.remove if content.css("p").first&.text.to_s.strip.empty?
        first_paragraph = content.css("p").first
        first_paragraph.children.first.remove if first_paragraph&.children&.first&.name == "br"
        wrapper.add_child(content) unless content.children.empty?
        blockquote.replace(wrapper)
      end
    end

    def annotate_code_blocks(note, fragment)
      note.document.select { |node| node.type == :code_block }.each_with_index do |source, index|
        marker = code_marker(index)
        pre = fragment.css("pre").find { |candidate| candidate.at_css("code")&.text&.start_with?(marker) }
        next unless pre
        remove_text_prefix(pre.at_css("code"), "#{marker}\n")
        language = source.fence_info.to_s.split.first.to_s.downcase.gsub(/[^a-z0-9_+-]/, "")
        next if language.empty?

        code = pre.at_css("code")
        code["class"] = [code["class"], "language-#{language}"].compact.join(" ") if code
        pre["lang"] = language
        pre["data-website-mermaid"] = "true" if language == "mermaid"
      end
    end

    def remove_text_prefix(node, prefix)
      remaining = prefix
      node.xpath(".//text()").each do |text|
        break if remaining.empty?

        length = [text.text.length, remaining.length].min
        return false unless text.text[0, length] == remaining[0, length]

        text.content = text.text[length..].to_s
        remaining = remaining[length..].to_s
      end
      remaining.empty?
    end

    def annotate_code_markers(note)
      note.document.select { |node| node.type == :code_block }.each_with_index do |source, index|
        source.string_content = "#{code_marker(index)}\n#{source.string_content}"
      end
    end

    def code_marker(index)
      "JEKYLL_OBSIDIAN_CODE_#{index}_START"
    end

    def build_published_site_model
      relations = @relations.sort_by do |relation|
        [relation.source_id, relation.target_id, relation.kind.to_s, relation.fragment.to_s, span_key(relation.source_span)]
      end
      backlinks = relation_index(:link)
      embedded_by = relation_index(:embed)
      direct = @relations.group_by(&:source_id)

      notes = @notes.values.sort_by(&:id).map do |note|
        context = TransclusionContext.new(host_id: note.id, sequence: 0, instances: 0, bytes: 0)
        content = render_with_transclusions(note.id, [], context, depth: 0).to_html
        assert_block_anchors_rendered(note, content)
        PublishedNote.new(
          id: note.id,
          title: note.title,
          route: note.route,
          content: content,
          properties: note.properties,
          markdown_source: PublishedMarkdown.content(
            title: note.title,
            body: note.body,
            has_h1: note.has_h1
          ),
          authored_text: note.authored_text,
          preview: note.preview,
          outline: note.outline,
          updated: note.updated,
          created: note.created,
          content_type: note.content_type,
          published_at: note.published_at,
          nav_order: note.nav_order,
          nav_exclude: note.nav_exclude,
          has_h1: note.has_h1,
          feature_flags: note.feature_flags,
          content_security: content_security_needs(content),
          image_url: published_image_url(note),
          source_links: published_source_links(note),
          topics: published_topics(note),
          links: relation_cards(direct.fetch(note.id, []).select { |item| item.kind == :link }),
          backlinks: relation_cards(backlinks.fetch(note.id, []), source: true),
          embedded_by: relation_cards(embedded_by.fetch(note.id, []), source: true)
        )
      end
      graph_edges = graph_edges_for(relations)
      PublishedSiteModel.new(
        notes: notes,
        notes_by_id: notes.to_h { |note| [note.id, note] },
        relations: relations,
        graph_edges: graph_edges,
        graph_degrees: graph_degrees_for(notes, graph_edges)
      )
    end

    def content_security_needs(content)
      fragment = Nokogiri::HTML5.fragment(content)
      media_sources = fragment.css("video[src], audio[src], video source[src], audio source[src]")
        .filter_map { |node| ExternalMedia.https_origin(node["src"]) }
        .uniq
        .sort
      frame_sources = fragment.css("iframe[src]")
        .filter_map { |node| ExternalMedia.https_origin(node["src"]) }
        .uniq
        .sort
      tweet = !fragment.at_css("[data-website-tweet]").nil?
      ContentSecurityNeeds.new(
        media_sources: media_sources,
        frame_sources: (frame_sources + (tweet ? ["https://platform.twitter.com"] : [])).uniq.sort,
        script_sources: tweet ? ["https://platform.twitter.com"] : [],
        connect_sources: []
      )
    end

    def published_topics(note)
      note.topics.filter_map do |topic|
        occurrence = topic.occurrence
        unless occurrence
          next({ "kind" => topic.kind, "name" => topic.name })
        end

        target = @notes[occurrence.target_id]
        name = occurrence.display || target&.title || occurrence.raw_target
        value = { "kind" => topic.kind, "name" => name }
        if target && !occurrence.unresolved
          fragment = occurrence.anchor_id || occurrence.fragment
          value["url"] = "#{@url_builder.href(target.route)}#{fragment && !fragment.empty? ? "##{fragment}" : ""}"
        end
        value
      end.uniq
    end

    def render_with_transclusions(note_id, stack, context, depth:, raw_fragment: nil, resolved_anchor_id: nil)
      fragment = cached_transclusion_selection(note_id, raw_fragment, resolved_anchor_id)
      unless consume_transclusion_bytes(context, fragment.to_html.bytesize, note_id)
        return transclusion_limit_fragment(fragment.document, "expanded HTML exceeds #{MAX_TRANSCLUSION_BYTES} bytes")
      end

      fragment.css("website-embed").to_a.each do |placeholder|
        target_id = placeholder["data-source-id"]
        if stack.include?(target_id) || target_id == note_id
          replacement = Nokogiri::XML::Node.new("span", fragment.document)
          replacement["class"] = "website-embed website-embed--cycle"
          replacement.content = "Embed cycle"
          transfer_replacement_identity(placeholder, replacement)
          placeholder.replace(replacement)
          next
        end

        unless consume_transclusion_instance(context, depth + 1, note_id)
          placeholder.replace(transclusion_limit_node(fragment.document, "embed expansion limit reached"))
          next
        end

        selected = render_with_transclusions(
          target_id,
          stack + [note_id],
          context,
          depth: depth + 1,
          raw_fragment: placeholder["data-fragment"],
          resolved_anchor_id: placeholder["data-anchor-id"]
        )
        context.sequence += 1
        prefix = "embed-#{@url_builder.slug(context.host_id)}-#{context.sequence}-"
        rewrite_fragment_ids(selected, prefix)

        wrapper = Nokogiri::XML::Node.new("section", fragment.document)
        wrapper["class"] = "website-transclusion website-embed"
        wrapper["data-source-id"] = target_id
        transfer_replacement_identity(placeholder, wrapper)
        source = Nokogiri::XML::Node.new("a", fragment.document)
        source["class"] = "website-transclusion__source website-embed__source"
        source["href"] = placeholder["data-href"]
        source.content = "From #{@notes.fetch(target_id).title}"
        wrapper.add_child(source)
        embedded_content = Nokogiri::XML::Node.new("div", fragment.document)
        embedded_content["class"] = "website-transclusion__content website-embed__content"
        selected.children.to_a.each { |child| embedded_content.add_child(child.unlink) }
        wrapper.add_child(embedded_content)
        placeholder.replace(wrapper)
      end
      fragment
    end

    def cached_transclusion_selection(note_id, raw_fragment, resolved_anchor_id)
      key = [note_id, raw_fragment.to_s, resolved_anchor_id.to_s]
      cached = @transclusion_selection_cache[key]
      return Nokogiri::HTML5.fragment(cached) if cached

      fragment = @notes.fetch(note_id).base_fragment.dup
      selected = select_transclusion_fragment(fragment, raw_fragment, resolved_anchor_id)
      serialized = selected.to_html.freeze
      @transclusion_selection_cache[key] = serialized
      Nokogiri::HTML5.fragment(serialized)
    end

    def consume_transclusion_instance(context, depth, path)
      return transclusion_limit(context, "embed depth exceeds #{MAX_TRANSCLUSION_DEPTH}", path) if depth > MAX_TRANSCLUSION_DEPTH
      return transclusion_limit(context, "embed instances exceed #{MAX_TRANSCLUSION_INSTANCES}", path) if context.instances >= MAX_TRANSCLUSION_INSTANCES

      context.instances += 1
      true
    end

    def consume_transclusion_bytes(context, amount, path)
      return transclusion_limit(context, "expanded HTML exceeds #{MAX_TRANSCLUSION_BYTES} bytes", path) if context.bytes + amount > MAX_TRANSCLUSION_BYTES

      context.bytes += amount
      true
    end

    def transclusion_limit(_context, message, path)
      error_or_warning("embed_budget_exceeded", message, path, nil, fatal: production?)
      false
    end

    def transclusion_limit_fragment(document, message)
      fragment = Nokogiri::HTML5.fragment("")
      fragment.add_child(transclusion_limit_node(document, message))
      fragment
    end

    def transclusion_limit_node(document, message)
      node = Nokogiri::XML::Node.new("span", document)
      node["class"] = "website-embed website-embed--limited"
      node["role"] = "status"
      node.content = message
      node
    end

    def transfer_replacement_identity(source, replacement)
      replacement["id"] = source["id"] if source["id"]
    end

    def assert_block_anchors_rendered(note, content)
      document = Nokogiri::HTML5.fragment(content)
      counts = document.css("[id]").each_with_object(Hash.new(0)) { |node, memo| memo[node["id"]] += 1 }
      note.anchors.select { |anchor| anchor.kind == :block }.each do |anchor|
        next if counts[anchor.id] == 1

        error(
          "block_anchor_realization",
          "block ID #{anchor.id.inspect} rendered #{counts[anchor.id]} matching DOM targets instead of one",
          note.id
        )
      end
    end

    def select_transclusion_fragment(fragment, raw_fragment, resolved_anchor_id = nil)
      return fragment unless raw_fragment && !raw_fragment.empty?

      identifier = resolved_anchor_id.to_s
      identifier = raw_fragment.start_with?("^") ? raw_fragment.delete_prefix("^") : @url_builder.slug(raw_fragment.split("#").last) if identifier.empty?
      # Match the attribute value in Ruby instead of interpolating it into a
      # CSS ID selector. CSS selectors need a special escape for leading
      # digits, while HTML fragment IDs do not.
      target = fragment.css("[id]").find { |candidate| candidate["id"] == identifier }
      return empty_embed_fragment(fragment, raw_fragment) unless target
      if target["class"].to_s.split.include?("website-block-anchor") && target.next_element
        return fragment_for_node(target.next_element)
      end
      return fragment_for_node(target) unless target.name.match?(/\Ah[1-6]\z/)

      level = target.name.delete_prefix("h").to_i
      selected = Nokogiri::HTML5.fragment("")
      cursor = target
      while cursor
        break if cursor != target && cursor.element? && cursor.name.match?(/\Ah[1-6]\z/) && cursor.name.delete_prefix("h").to_i <= level

        following = cursor.next_sibling
        selected.add_child(cursor.unlink)
        cursor = following
      end
      selected
    end

    def fragment_for_node(node)
      selected = Nokogiri::HTML5.fragment("")
      if node.name == "li" && %w[ul ol].include?(node.parent&.name)
        list = Nokogiri::XML::Node.new(node.parent.name, node.document)
        node.parent.attribute_nodes.each { |attribute| list[attribute.name] = attribute.value }
        list.add_child(node.unlink)
        selected.add_child(list)
      else
        selected.add_child(node.unlink)
      end
      selected
    end

    def empty_embed_fragment(fragment, label)
      selected = Nokogiri::HTML5.fragment("")
      span = Nokogiri::XML::Node.new("span", fragment.document)
      span["class"] = "website-embed website-embed--unresolved"
      span.content = "Missing fragment: #{label}"
      selected.add_child(span)
      selected
    end

    def rewrite_fragment_ids(fragment, prefix)
      mapping = {}
      fragment.css("[id]").each do |node|
        old = node["id"]
        mapping[old] = "#{prefix}#{old}"
        node["id"] = mapping[old]
      end
      fragment.css("*").select { |node| node["href"] || node["xlink:href"] }.each do |node|
        %w[href xlink:href].each do |attribute|
          next unless node[attribute]&.start_with?("#")

          old = node[attribute].delete_prefix("#")
          node[attribute] = "##{mapping.fetch(old, "#{prefix}#{old}")}"
        end
      end
      %w[for list form aria-activedescendant aria-details aria-errormessage].each do |attribute|
        fragment.css("[#{attribute}]").each do |node|
          old = node[attribute]
          node[attribute] = mapping.fetch(old, "#{prefix}#{old}")
        end
      end
      %w[aria-labelledby aria-describedby aria-controls aria-owns headers itemref].each do |attribute|
        fragment.css("[#{attribute}]").each do |node|
          node[attribute] = node[attribute].split.map { |old| mapping.fetch(old, "#{prefix}#{old}") }.join(" ")
        end
      end
      %w[style clip-path fill filter mask marker-start marker-mid marker-end stroke].each do |attribute|
        fragment.css("[#{attribute}]").each do |node|
          node[attribute] = node[attribute].gsub(/url\(\s*(['"]?)#([^)'"\s]+)\1\s*\)/) do
            quote = Regexp.last_match(1)
            old = Regexp.last_match(2)
            "url(#{quote}##{mapping.fetch(old, "#{prefix}#{old}")}#{quote})"
          end
        end
      end
    end

    def published_image_url(note)
      path = @image_paths[note.id]
      return nil unless path

      route = @url_builder.attachment_route(path)
      @url_builder.absolute_url(route) || @url_builder.href(route)
    end

    def repository_links(path)
      repository = @config.repository.to_s
      return {} unless repository.match?(/\A[\w.-]+\/[\w.-]+\z/)

      branch = URI.encode_uri_component(@config.edit_branch.to_s.empty? ? "main" : @config.edit_branch.to_s)
      source = [@config.source.to_s, path].reject(&:empty?).map { |part| part.split("/").map { |segment| URI.encode_uri_component(segment) }.join("/") }.join("/")
      base = "https://github.com/#{repository}"
      {
        "edit" => "#{base}/edit/#{branch}/#{source}",
        "history" => "#{base}/commits/#{branch}/#{source}",
        "source" => "#{base}/blob/#{branch}/#{source}",
        "issue" => "#{base}/issues/new?title=#{URI.encode_uri_component("Issue with #{path}")}"
      }
    end

    def published_source_links(note)
      links = repository_links(note.id)
      links = links.merge("imported" => note.external_document.source_url) if note.external_document
      links
    end

    def build_generated_files(pages, model, theme_output)
      artifacts = theme_output.artifacts.filter_map do |artifact|
        case artifact
        when "catalog"
          json_file("/assets/website/catalog.v1.json", catalog_payload(model))
        when "graph"
          json_file("/assets/website/graph.v1.json", graph_payload(model))
        when "search"
          json_file("/assets/website/search.v1.json", search_payload(model))
        when "sitemap"
          GeneratedFile.new(route: "/sitemap.xml", content: sitemap_xml(pages), media_type: "application/xml")
        when "feed"
          candidates = theme_output.feed_note_ids.map { |id| model.notes_by_id.fetch(id) }
          feed = feed_xml(candidates)
          GeneratedFile.new(route: "/feed.xml", content: feed, media_type: "application/atom+xml") if feed
        else
          raise ArgumentError, "unknown generated artifact #{artifact.inspect}"
        end
      end
      markdown = model.notes.map do |note|
        GeneratedFile.new(
          route: PublishedMarkdown.route(note.route),
          content: note.markdown_source,
          media_type: "text/markdown"
        )
      end
      artifacts + markdown
    end

    def catalog_payload(model)
      {
        "schema_version" => 1,
        "notes" => model.notes.map do |note|
          {
            "id" => note.id,
            "title" => note.title,
            "url" => @url_builder.href(note.route),
            "aliases" => Array(note.properties["aliases"]),
            "tags" => Array(note.properties["tags"]),
            "description" => note.properties["description"],
            "preview" => note.preview,
            "updated" => note.updated,
            "content_type" => note.content_type,
            "published_at" => note.published_at
          }
        end
      }
    end

    def graph_payload(model)
      {
        "schema_version" => 1,
        "nodes" => model.notes.map do |note|
          {
            "id" => note.id,
            "title" => note.title,
            "url" => @url_builder.href(note.route),
            "tags" => Array(note.properties["tags"]),
            "degree" => model.graph_degrees.fetch(note.id)
          }
        end,
        "edges" => model.graph_edges
      }
    end

    def search_payload(model)
      {
        "schema_version" => 1,
        "documents" => model.notes.map do |note|
          {
            "id" => note.id,
            "title" => note.title,
            "url" => @url_builder.href(note.route),
            "aliases" => Array(note.properties["aliases"]),
            "tags" => Array(note.properties["tags"]),
            "text" => note.authored_text
          }
        end
      }
    end

    def graph_edges_for(relations)
      counts = Hash.new(0)
      relations.each { |relation| counts[[relation.source_id, relation.target_id, relation.kind.to_s]] += 1 }
      counts.keys.sort.map do |source, target, kind|
        { "source" => source, "target" => target, "kind" => kind, "count" => counts[[source, target, kind]] }
      end
    end

    def graph_degrees_for(notes, edges)
      neighbours = notes.to_h { |note| [note.id, {}] }
      edges.each do |edge|
        source = edge.fetch("source")
        target = edge.fetch("target")
        neighbours.fetch(source)[target] = true
        neighbours.fetch(target)[source] = true
      end
      neighbours.transform_values(&:length)
    end

    def json_file(route, payload)
      GeneratedFile.new(route: route, content: "#{JSON.generate(payload)}\n", media_type: "application/json")
    end

    def sitemap_xml(pages)
      urls = pages.reject { |page| %w[404 redirect].include?(page.data.dig("website", "kind")) }
        .map(&:route).sort
      body = urls.map { |route| "  <url><loc>#{h(@url_builder.absolute_url(route))}</loc></url>" }.join("\n")
      %(<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n#{body}\n</urlset>\n)
    end

    def feed_xml(candidates)
      if candidates.empty?
        warning("feed_skipped_empty", "feed skipped because there are no public notes")
        return nil
      end

      missing = candidates.select { |note| feed_timestamp(note).nil? }
      unless missing.empty?
        warning("feed_omitted_missing_time", "feed omitted #{missing.length} public note(s) without an explicit update time or post publication time")
      end

      candidates -= missing
      return nil if candidates.empty?

      notes = candidates.sort_by { |note| [chronology_key(feed_timestamp(note)), note.id] }.reverse
      updated = feed_timestamp(notes.first)
      entries = notes.map do |note|
        published = note.published_at ? "\n    <published>#{h(note.published_at)}</published>" : ""
        <<~XML.chomp
          <entry>
            <id>#{h(@url_builder.absolute_url(note.route))}</id>
            <title>#{h(note.title)}</title>
            <link href="#{h(@url_builder.absolute_url(note.route))}" />
            <updated>#{h(feed_timestamp(note))}</updated>#{published}
            <summary>#{h(note.preview)}</summary>
          </entry>
        XML
      end.join("\n")
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <id>#{h(@url_builder.absolute_url("/"))}</id>
          <title>#{h(@config.title.to_s)}</title>
          <updated>#{h(updated)}</updated>
          <link href="#{h(@url_builder.absolute_url("/feed.xml"))}" rel="self" />
        #{entries.lines.map { |line| "  #{line}" }.join}</feed>
      XML
    end

    def feed_timestamp(note)
      note.updated || (note.content_type == "post" ? note.published_at : nil)
    end

    def chronology_key(value)
      [0, DateTime.iso8601(value.to_s).new_offset(0).ajd]
    rescue Date::Error
      [1, value.to_s]
    end

    def build_copied_assets
      @copied_asset_paths.to_a.sort.map do |path|
        entry = @attachments.fetch(path)
        CopiedAsset.new(
          source_path: path,
          route: @url_builder.attachment_route(path),
          media_type: entry.media_type,
          size: entry.size,
          device: entry.device,
          inode: entry.inode,
          mtime_ns: entry.mtime_ns
        )
      end
    end

    def preflight_routes(pages, generated_files, copied_assets, reserved_namespaces)
      registry = DestinationRegistry.new
      (pages + generated_files + copied_assets).each do |output|
        destination = destination_key(output)
        conflict = registry.add(destination, output.route)
        if conflict
          error("route_collision", "output route collides with #{conflict}", output.route)
        end
      end

      namespace_keys = reserved_namespaces.map do |namespace|
        @url_builder.collision_key(namespace).delete_suffix("/")
      end
      @notes.each_value do |note|
        page_key = @url_builder.collision_key(note.route).delete_suffix("/")
        next unless namespace_keys.any? { |namespace| page_key == namespace || page_key.start_with?("#{namespace}/") }

        error("route_collision", "note route collides with a generated system namespace", note.route)
      end

      return unless production? && @notes.any?
      index_count = pages.count { |page| page.route == "/" }
      error("invalid_index_count", "production must generate exactly one /index.html", nil) unless index_count == 1
    end

    def destination_key(output)
      key = @url_builder.collision_key(output.route)
      if output.is_a?(PageOutput)
        key.end_with?("/") ? "#{key}index.html" : key
      else
        output.route.end_with?("/") ? key : key.delete_suffix("/")
      end
    end

    def resolve_note_path(source_id, raw_target)
      decoded = safe_decode(raw_target).unicode_normalize(:nfc).tr("\\", "/")
      return [nil, false] if decoded.empty?
      return [nil, false] if attachment_extension?(decoded)

      rooted = decoded.delete_prefix("/")
      root_candidate = ensure_md(rooted)
      return [root_candidate, false] if @notes.key?(root_candidate)

      if decoded.start_with?("./", "../")
        relative = clean_relative(File.dirname(source_id), decoded)
        return [nil, false] unless relative
        candidate = ensure_md(relative)
        return [candidate, false] if @notes.key?(candidate)
        return [nil, false]
      end

      relative = clean_relative(File.dirname(source_id), decoded)
      if relative
        candidate = ensure_md(relative)
        return [candidate, false] if @notes.key?(candidate)
      end

      basename = File.basename(rooted, NOTE_EXTENSION).unicode_normalize(:nfc).downcase(:fold)
      candidates = @basename_index.fetch(basename, [])
      return [candidates.first, false] if candidates.one?
      return [nil, true] if candidates.length > 1

      [nil, false]
    end

    def resolve_attachment_path(source_id, raw_target)
      decoded = safe_decode(raw_target).unicode_normalize(:nfc).tr("\\", "/").delete_prefix("/")
      return [nil, false] if decoded.empty?

      candidates = []
      candidates << decoded
      relative = clean_relative(File.dirname(source_id), decoded)
      candidates << relative if relative && relative != decoded
      candidates.each { |candidate| return [candidate, false] if @attachments.key?(candidate) }

      return [nil, false] if decoded.include?("/")

      folded = File.basename(decoded).unicode_normalize(:nfc).downcase(:fold)
      matches = @attachment_basename_index.fetch(folded, [])
      return [matches.first, false] if matches.one?

      [nil, matches.length > 1]
    end

    def split_target(raw, kind)
      text = raw.to_s.strip
      target_and_fragment, size_option = text.split("|", 2)
      target, fragment = target_and_fragment.split("#", 2)
      options = {}
      if size_option&.match?(/\A\d+(?:x\d+)?\z/)
        width, height = size_option.split("x", 2)
        options["width"] = width.to_i
        options["height"] = height.to_i if height
      end

      if File.extname(target.to_s).downcase == ".pdf" && fragment
        fragment.split("&").each do |part|
          key, value = part.split("=", 2)
          options[key] = value.to_i if %w[page height].include?(key) && value&.match?(/\A\d+\z/)
        end
        fragment = nil if options.any?
      end
      [target.to_s.strip, fragment&.strip, options]
    end

    def external_url?(raw_url, path, span, media: false)
      text = raw_url.to_s.strip
      scheme = text[/\A([a-z][a-z0-9+.-]*):/i, 1]&.downcase
      return false unless scheme

      if DANGEROUS_SCHEMES.include?(scheme) || !EXTERNAL_SCHEMES.include?(scheme)
        error("unsafe_url", "URL scheme is not allowed", path, span)
      elsif media && scheme != "https"
        error("unsafe_url", "author media URLs must use HTTPS", path, span)
      end
      true
    end

    def attachment_extension?(target)
      extension = File.extname(target).downcase
      !extension.empty? && extension != NOTE_EXTENSION
    end

    def deterministic_created(note)
      note.properties["created"] || note.entry.first_committed_at
    end

    def relation_index(kind)
      index = Hash.new { |hash, key| hash[key] = [] }
      @relations.each { |relation| index[relation.target_id] << relation if relation.kind == kind }
      index
    end

    def relation_cards(relations, source: false)
      ids = relations.map { |relation| source ? relation.source_id : relation.target_id }.uniq.sort
      ids.map do |id|
        note = @notes.fetch(id)
        { "id" => id, "title" => note.title, "url" => @url_builder.href(note.route) }
      end
    end

    def token_url(index)
      "https://obsidian.invalid/ref/#{index}"
    end

    def source_span(position)
      return nil unless position
      SourceSpan.new(
        start_line: position[:start_line],
        start_column: position[:start_column],
        end_line: position[:end_line],
        end_column: position[:end_column]
      )
    end

    def sourcepos_value(position)
      "#{position.fetch(:start_line)}:#{position.fetch(:start_column)}-#{position.fetch(:end_line)}:#{position.fetch(:end_column)}"
    end

    def parse_sourcepos_value(value)
      match = value.to_s.match(/\A(\d+):(\d+)-(\d+):(\d+)\z/)
      return { start_line: 0, start_column: 0, end_line: 0, end_column: 0 } unless match

      {
        start_line: match[1].to_i,
        start_column: match[2].to_i,
        end_line: match[3].to_i,
        end_column: match[4].to_i
      }
    end

    def span_key(span)
      return [0, 0, 0, 0] unless span
      [span.start_line, span.start_column, span.end_line, span.end_column]
    end

    def first_h1(document)
      heading = document.find { |node| node.type == :heading && node.header_level == 1 }
      heading && plain_node_text(heading).strip
    end

    def plain_node_text(node)
      node.walk.filter_map do |child|
        child.string_content if %i[text code].include?(child.type)
      rescue TypeError
        nil
      end.join
    end

    def filename_title(path)
      File.basename(path, NOTE_EXTENSION).tr("-_", " ")
    end

    def visible_text(fragment)
      copy = fragment.dup
      copy.css("script, style, template, website-embed, .website-transclusion__source").remove
      copy.text.gsub(/\s+/, " ").strip
    end

    def truncate(text, limit)
      value = text.to_s.gsub(/\s+/, " ").strip
      return value if value.length <= limit

      "#{value[0, limit - 1].rstrip}…"
    end

    def image_node(document, occurrence, href)
      node = Nokogiri::XML::Node.new("img", document)
      node["src"] = href
      node["alt"] = occurrence.display.to_s
      node["loading"] = "lazy"
      node["decoding"] = "async"
      node["width"] = occurrence.options["width"].to_s if occurrence.options&.key?("width")
      node["height"] = occurrence.options["height"].to_s if occurrence.options&.key?("height")
      node
    end

    def media_node(document, name, href, media_type)
      node = Nokogiri::XML::Node.new(name, document)
      node["controls"] = "controls"
      node["preload"] = "metadata"
      node["playsinline"] = "playsinline" if name == "video"
      source = Nokogiri::XML::Node.new("source", document)
      source["src"] = href
      source["type"] = media_type.to_s unless media_type.to_s.empty?
      node.add_child(source)
      node
    end

    def external_video_node(document, descriptor, label)
      node = media_node(document, "video", descriptor.source_url, descriptor.media_type)
      node["class"] = "website-external-video"
      node["aria-label"] = label.to_s.strip unless label.to_s.strip.empty?
      fallback = Nokogiri::XML::Node.new("a", document)
      fallback["href"] = descriptor.fallback_url
      fallback["rel"] = "noopener noreferrer"
      fallback.content = label.to_s.strip.empty? ? "Open video" : label.to_s.strip
      node.add_child(fallback)
      node
    end

    def external_player_node(document, descriptor, label)
      node = Nokogiri::XML::Node.new("iframe", document)
      node["class"] = "website-external-player website-external-player--#{descriptor.provider}"
      node["data-website-external-player"] = descriptor.provider.to_s
      node["src"] = descriptor.source_url
      node["title"] = label.to_s.strip.empty? ? (descriptor.title || external_player_title(descriptor.provider)) : label.to_s.strip
      node["loading"] = "lazy"
      node["referrerpolicy"] = "strict-origin-when-cross-origin"
      node["allow"] = descriptor.iframe_allow if descriptor.iframe_allow
      node["allowfullscreen"] = "allowfullscreen"
      node["width"] = descriptor.width.to_s if descriptor.width
      node["height"] = descriptor.height.to_s if descriptor.height
      node
    end

    def external_web_frame_node(document, descriptor)
      wrapper = Nokogiri::XML::Node.new("figure", document)
      wrapper["class"] = "website-external-frame"
      frame = Nokogiri::XML::Node.new("iframe", document)
      frame["class"] = "website-external-frame__viewport"
      frame["data-website-external-frame"] = "web"
      frame["src"] = descriptor.source_url
      frame["title"] = descriptor.title
      frame["loading"] = "lazy"
      frame["referrerpolicy"] = "strict-origin-when-cross-origin"
      frame["sandbox"] = descriptor.iframe_sandbox
      frame["allowfullscreen"] = "allowfullscreen"
      frame["width"] = descriptor.width.to_s if descriptor.width
      frame["height"] = descriptor.height.to_s
      wrapper.add_child(frame)
      fallback = Nokogiri::XML::Node.new("a", document)
      fallback["class"] = "website-external-frame__fallback"
      fallback["href"] = descriptor.fallback_url
      fallback["target"] = "_blank"
      fallback["rel"] = "noopener noreferrer"
      fallback.content = "Open embedded page"
      wrapper.add_child(fallback)
      wrapper
    end

    def tweet_node(document, descriptor)
      wrapper = Nokogiri::XML::Node.new("figure", document)
      wrapper["class"] = "website-tweet"
      wrapper["data-website-tweet"] = descriptor.identifier
      mount = Nokogiri::XML::Node.new("div", document)
      mount["class"] = "website-tweet__mount"
      mount["data-website-tweet-mount"] = ""
      wrapper.add_child(mount)
      fallback = Nokogiri::XML::Node.new("a", document)
      fallback["class"] = "website-tweet__fallback"
      fallback["data-website-tweet-fallback"] = ""
      fallback["href"] = descriptor.fallback_url
      fallback["target"] = "_blank"
      fallback["rel"] = "noopener noreferrer"
      fallback.content = "View post on X"
      wrapper.add_child(fallback)
      wrapper
    end

    def external_player_title(provider)
      {
        youtube: "YouTube video player",
        bilibili: "Bilibili video player",
        vimeo: "Vimeo video player"
      }.fetch(provider, "Video player")
    end

    def pdf_node(document, occurrence, href)
      data = href
      data = "#{data}#page=#{occurrence.options["page"]}" if occurrence.options&.key?("page")
      node = Nokogiri::XML::Node.new("object", document)
      node["data"] = data
      node["type"] = "application/pdf"
      node["height"] = occurrence.options.fetch("height", 640).to_s
      fallback = Nokogiri::XML::Node.new("a", document)
      fallback["href"] = href
      fallback.content = "Download PDF"
      node.add_child(fallback)
      node
    end

    def download_card(document, path, href, media_type)
      node = Nokogiri::XML::Node.new("a", document)
      node["class"] = "website-download-card attachment-card"
      node["href"] = href
      node["download"] = ""
      title = Nokogiri::XML::Node.new("span", document)
      title["class"] = "website-download-card__title attachment-card__title"
      title.content = File.basename(path)
      meta = Nokogiri::XML::Node.new("span", document)
      meta["class"] = "website-download-card__meta attachment-card__type"
      meta.content = media_type.to_s.empty? ? "Download" : media_type.to_s
      node.add_child(title)
      node.add_child(meta)
      node
    end

    def clean_relative(base, target)
      joined = base.empty? || base == "." ? target : File.join(base, target)
      clean = Pathname.new(joined).cleanpath.to_s.tr("\\", "/")
      return nil if clean == ".." || clean.start_with?("../") || clean.start_with?("/")

      clean.delete_prefix("./")
    end

    def local_target_escapes_vault?(source_id, raw_target)
      decoded = safe_decode(raw_target).unicode_normalize(:nfc).tr("\\", "/")
      if decoded.start_with?("/")
        clean_relative("", decoded.delete_prefix("/")).nil?
      elsif decoded.start_with?("./", "../")
        clean_relative(File.dirname(source_id), decoded).nil?
      else
        clean_relative("", decoded).nil?
      end
    rescue ArgumentError, EncodingError
      true
    end

    def ensure_md(path)
      path.end_with?(NOTE_EXTENSION) ? path : "#{path}#{NOTE_EXTENSION}"
    end

    def safe_decode(value)
      URI.decode_uri_component(value.to_s)
    rescue ArgumentError
      value.to_s
    end

    def validated_path(entry)
      path = entry.path.to_s
      if path.empty? || path.start_with?("/", "\\") || path.include?("\0") || path.include?("\\")
        error("invalid_path", "snapshot paths must be relative POSIX paths", path)
        return nil
      end
      segments = path.split("/")
      if segments.any? { |segment| segment.empty? || segment == "." || segment == ".." } || path != path.unicode_normalize(:nfc)
        error("invalid_path", "snapshot paths must be normalized NFC paths without traversal", path)
        return nil
      end
      path
    rescue Encoding::CompatibilityError
      error("invalid_path", "snapshot path is not valid Unicode", path)
      nil
    end

    def production?
      @config&.environment.to_s != "development"
    end

    def error_or_warning(code, message, path = nil, span = nil, fatal:)
      fatal ? error(code, message, path, span) : warning(code, message, path, span)
    end

    def error(code, message, path = nil, span = nil)
      @diagnostics << Diagnostic.new(severity: :error, code: code, message: message, path: path, span: span)
    end

    def warning(code, message, path = nil, span = nil)
      @diagnostics << Diagnostic.new(severity: :warning, code: code, message: message, path: path, span: span)
    end

    def sorted_diagnostics
      @diagnostics.uniq { |item| [item.severity, item.code, item.message, item.path, span_key(item.span)] }
        .sort_by { |item| [item.path.to_s, span_key(item.span), item.severity.to_s, item.code] }
    end

    def h(value)
      text = value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
      CGI.escapeHTML(text.gsub(FrontMatter::XML_INVALID_CHARACTER, "\uFFFD"))
    end
  end
end
