# frozen_string_literal: true

require "cgi/escape"
require "commonmarker"
require "json"
require "nokogiri"
require "pathname"
require "set"

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
        escaped_char_spans: true
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
    DANGEROUS_SCHEMES = %w[data file javascript vbscript].freeze
    EXTERNAL_SCHEMES = %w[http https mailto tel].freeze
    NOTE_EXTENSION = ".md"
    CANVAS_BASE_EXTENSIONS = %w[.canvas .base].freeze
    IMAGE_EXTENSIONS = %w[.avif .bmp .gif .jpeg .jpg .png .svg .webp].freeze
    AUDIO_EXTENSIONS = %w[.flac .m4a .mp3 .ogg .wav .webm .3gp].freeze
    VIDEO_EXTENSIONS = %w[.mkv .mov .mp4 .ogv .webm].freeze
    THEMES = BuiltInThemes::IDS
    FEATURE_KEYS = %w[search tags feed graph relations previews outline].freeze
    THEME_FEATURE_DEFAULTS = {
      "blog" => {
        "search" => true, "tags" => true, "feed" => true,
        "graph" => false, "relations" => false, "previews" => false, "outline" => false
      },
      "docs" => {
        "search" => true, "tags" => false, "feed" => false,
        "graph" => false, "relations" => false, "previews" => false, "outline" => true
      },
      "digital-garden" => {
        "search" => true, "tags" => true, "feed" => true,
        "graph" => true, "relations" => true, "previews" => true, "outline" => true
      }
    }.transform_values(&:freeze).freeze
    DEFAULT_CONTENT = {
      "default_type" => "page",
      "directories" => { "post" => ["blog"].freeze, "doc" => ["docs"].freeze }.freeze
    }.freeze
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
      :wiki_index,
      :resolved_type,
      :target_id,
      :target_path,
      :fragment,
      :options,
      :anchor_id,
      :unresolved,
      keyword_init: true
    )

    Anchor = Struct.new(:kind, :id, :label, :level, :chain, keyword_init: true)

    def self.compile(request)
      new(request).compile
    rescue StandardError => exception
      diagnostic = Diagnostic.new(
        severity: :error,
        code: "compiler_failure",
        message: "compiler failed safely: #{exception.class}: #{exception.message}",
        path: nil,
        span: nil
      )
      BuildResult.new(
        pages: [],
        generated_files: [],
        copied_assets: [],
        diagnostics: [diagnostic],
        relations: [],
        notes: [],
        theme: "digital-garden",
        features: THEME_FEATURE_DEFAULTS.fetch("digital-garden")
      )
    end

    def initialize(request)
      @request = request
      @config = request.config
      @diagnostics = []
      @notes = {}
      @all_note_paths = Set.new
      @attachments = {}
      @relations = []
      @copied_asset_paths = Set.new
      @render_sequence = 0
      @url_builder = nil
      @theme = "digital-garden"
      @features = THEME_FEATURE_DEFAULTS.fetch(@theme)
      @content = DEFAULT_CONTENT
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
      theme_config = EffectiveThemeConfig.new(
        theme: @theme,
        features: @features,
        content: @content,
        site: @config,
        url_builder: @url_builder
      )
      theme_output = BuiltInThemes.resolve(@theme).render(model: published_site, config: theme_config)
      pages = theme_output.pages
      generated_files = build_generated_files(pages, published_site, theme_output)
      copied_assets = build_copied_assets
      preflight_routes(pages, generated_files, copied_assets, theme_output.reserved_namespaces)

      note_outputs = published_site.notes.map do |note|
        NoteOutput.new(id: note.id, title: note.title, route: note.route, properties: note.properties)
      end
      BuildResult.new(
        pages: pages.sort_by(&:route),
        generated_files: generated_files.sort_by(&:route),
        copied_assets: copied_assets.sort_by(&:route),
        diagnostics: sorted_diagnostics,
        relations: published_site.relations,
        notes: note_outputs,
        theme: @theme,
        features: @features
      )
    end

    private

    def validate_request
      unless @request.is_a?(BuildRequest) && @request.snapshot.is_a?(Snapshot) && @config.is_a?(BuildConfig)
        error("invalid_request", "compile expects a BuildRequest containing Snapshot and BuildConfig")
        return
      end

      @config.each_pair do |name, value|
        next if FrontMatter.valid_output_text?(value.to_s)

        error("invalid_config_character", "#{name} contains a character forbidden by XML 1.0")
      end
      if @config.syntax_profile != "ofm@1"
        error("unsupported_syntax_profile", "syntax_profile must be ofm@1")
      end
      resolve_theme_config
      resolve_content_config
      @url_builder = UrlBuilder.new(origin: @config.url, baseurl: @config.baseurl)
    rescue ArgumentError => exception
      error("invalid_url_config", exception.message)
      @url_builder = UrlBuilder.new(origin: "", baseurl: "")
    end

    def resolve_theme_config
      requested = @config.theme.to_s
      requested = "digital-garden" if requested.empty?
      if THEMES.include?(requested)
        @theme = requested
      else
        error("invalid_theme", "theme must be one of: #{THEMES.join(', ')}")
        @theme = "digital-garden"
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

    def resolve_content_config
      raw = @config.content
      unless raw.nil? || raw.is_a?(Hash)
        error("invalid_content_config", "content must be a mapping")
        return
      end
      raw ||= {}
      unknown = raw.keys.map(&:to_s) - %w[default_type directories]
      unknown.each { |key| error("invalid_content_config", "unknown content setting #{key.inspect}") }

      default_type = fetch_hash_value(raw, "default_type") || "page"
      unless FrontMatter::CONTENT_TYPES.include?(default_type)
        error("invalid_content_config", "content.default_type must be one of: #{FrontMatter::CONTENT_TYPES.join(', ')}")
        default_type = "page"
      end

      directories = if raw.key?("directories") || raw.key?(:directories)
        fetch_hash_value(raw, "directories")
      else
        DEFAULT_CONTENT.fetch("directories")
      end
      unless directories.is_a?(Hash)
        error("invalid_content_directories", "content.directories must be a mapping")
        directories = {}
      end
      unknown_directories = directories.keys.map(&:to_s) - %w[post doc]
      unknown_directories.each { |key| error("invalid_content_directories", "unknown content directory type #{key.inspect}") }

      normalized = %w[post doc].to_h do |type|
        values = fetch_hash_value(directories, type) || []
        unless values.is_a?(Array)
          error("invalid_content_directories", "content.directories.#{type} must be an array")
          values = []
        end
        valid = values.filter_map { |value| normalize_content_directory(value, type) }.uniq.sort
        [type, valid]
      end
      normalized.fetch("post").product(normalized.fetch("doc")).each do |post_directory, doc_directory|
        next unless directory_overlaps?(post_directory, doc_directory)

        error(
          "overlapping_content_directories",
          "post and doc directories overlap: #{post_directory.inspect} and #{doc_directory.inspect}"
        )
      end
      @content = {
        "default_type" => default_type,
        "directories" => normalized.transform_values(&:freeze).freeze
      }.freeze
    end

    def fetch_hash_value(hash, key)
      hash.key?(key) ? hash[key] : hash[key.to_sym]
    end

    def normalize_content_directory(value, type)
      unless FrontMatter.valid_output_text?(value)
        error("invalid_content_directory", "content.directories.#{type} entries must be strings")
        return nil
      end
      if value.empty? || value.start_with?("/", "\\") || value.include?("\\") || value != value.unicode_normalize(:nfc)
        error("invalid_content_directory", "content directories must be normalized vault-relative POSIX paths")
        return nil
      end
      segments = value.split("/", -1)
      if segments.any? { |segment| segment.empty? || segment == "." || segment == ".." }
        error("invalid_content_directory", "content directories must not contain empty or traversal segments")
        return nil
      end
      value
    rescue EncodingError
      error("invalid_content_directory", "content directories must be valid Unicode")
      nil
    end

    def directory_overlaps?(first, second)
      left = first.downcase(:fold)
      right = second.downcase(:fold)
      left == right || left.start_with?("#{right}/") || right.start_with?("#{left}/")
    end

    def index_snapshot
      seen = {}
      Array(@request.snapshot&.entries).sort_by { |entry| entry.path.to_s.b }.each do |entry|
        path = validated_path(entry)
        next unless path

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
          next unless parsed.properties["publish"] == true
          unless FrontMatter.valid_output_text?(parsed.body)
            error("invalid_character", "public note body contains a character forbidden by XML 1.0", path)
            next
          end

          @notes[path] = MutableNote.new(
            id: path,
            entry: entry,
            properties: parsed.properties,
            body: parsed.body,
            occurrences: [],
            outline: [],
            feature_flags: {}
          )
        when :attachment
          @attachments[path] = entry
        when :symlink
          error("symlink_rejected", "symlinks are not accepted in a vault snapshot", path)
        else
          error("invalid_entry_kind", "snapshot entry kind must be note or attachment", path)
        end
      end
    end

    def parse_public_notes
      # Frontmatter parsing intentionally happens before Markdown parsing. This
      # method is a named pipeline checkpoint for profiling and conformance.
      unless @notes.key?("index.md")
        error("missing_index", "a public root vault/index.md is required", "index.md")
      end
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
        note.updated = deterministic_updated(note)
        note.created = deterministic_created(note)
        note.content_type = classify_content(note)
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

    def classify_content(note)
      explicit = note.properties["content_type"]
      if note.id == "index.md"
        error("invalid_root_content_type", "the public root index must have content_type: page", note.id) if explicit && explicit != "page"
        return "page"
      end
      return explicit if explicit

      directory = File.dirname(note.id)
      matches = @content.fetch("directories").flat_map do |type, configured|
        configured.filter_map { |prefix| type if directory == prefix || directory.start_with?("#{prefix}/") }
      end
      matches.first || @content.fetch("default_type")
    end

    def published_at(note)
      return nil unless note.content_type == "post"

      note.properties["date"] || note.properties["created"] || note.entry.first_committed_at
    end

    def parse_markdown_once
      @notes.values.sort_by(&:id).each do |note|
        prepared = OfmScanner.prepare(note.body)
        note.scanner = prepared
        merged_tags = (Array(note.properties["tags"]) + prepared.tags).uniq.sort
        note.properties = note.properties.merge("tags" => merged_tags)
        note.document = Commonmarker.parse(prepared.markdown, options: COMMONMARK_OPTIONS)
        note.has_h1 = note.document.any? { |node| node.type == :heading && node.header_level == 1 }
        note.title = note.properties["title"] || first_h1(note.document) || filename_title(note.id)
        build_anchor_registry(note)
        annotate_occurrences(note)
      rescue StandardError => exception
        error("markdown_parse_error", "could not parse Markdown: #{exception.message}", note.id)
      end
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
        identifier = used_heading_ids[base] == 1 ? base : "#{base}-#{used_heading_ids[base]}"
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
      prepared_lines = note.scanner.markdown.lines

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

      wiki_index = 0
      note.document.walk do |node|
        case node.type
        when :wikilink
          source = source_slice(prepared_lines, node.source_position)
          inner = source.sub(/\A\[\[/, "").sub(/\]\]\z/, "")
          target, display = inner.split("|", 2)
          occurrence = Occurrence.new(
            index: note.occurrences.length,
            source_id: note.id,
            raw_target: target.to_s,
            display: display,
            kind: :link,
            syntax: :wikilink,
            source_span: source_span(node.source_position),
            wiki_index: wiki_index
          )
          note.occurrences << occurrence
          wiki_index += 1
        when :link, :image
          raw_url = node.url.to_s
          next if raw_url.empty?
          next if external_url?(raw_url, note.id, source_span(node.source_position), media: node.type == :image)

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

    def resolve_all_occurrences
      @notes.values.sort_by(&:id).each do |note|
        note.occurrences.each do |occurrence|
          resolve_occurrence(note, occurrence)
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

        resolved = resolve_attachment_path(note.id, image)
        if resolved && attachment_kind(resolved, @attachments.fetch(resolved).media_type) == :image
          @copied_asset_paths << resolved
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

      attachment_target = resolve_attachment_path(note.id, target_text)
      if attachment_target
        unless attachment_kind(attachment_target, @attachments.fetch(attachment_target).media_type)
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
        html = note.document.to_html(options: COMMONMARK_OPTIONS, plugins: COMMONMARK_PLUGINS)
        fragment = Nokogiri::HTML5.fragment(html)
        bind_occurrence_nodes(note, fragment)
        normalize_document(note, fragment)
        note.base_fragment = fragment

        authored = fragment.dup
        authored.css("obsidian-embed").remove
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
      wiki_nodes = fragment.css("a[data-wikilink='true']")
      note.occurrences.select { |occurrence| occurrence.syntax == :wikilink }.sort_by(&:wiki_index).each_with_index do |occurrence, index|
        node = wiki_nodes[index]
        node["data-obsidian-occurrence"] = occurrence.index.to_s if node
      end

      note.occurrences.select { |occurrence| occurrence.syntax == :ofm_embed }.each do |occurrence|
        node = fragment.at_css("obsidian-ofm-embed[data-token='#{occurrence.scanner_token}']")
        node["data-obsidian-occurrence"] = occurrence.index.to_s if node
      end

      note.occurrences.select { |occurrence| %i[markdown_link markdown_image].include?(occurrence.syntax) }.each do |occurrence|
        selector = occurrence.syntax == :markdown_image ? "img[src='#{token_url(occurrence.index)}']" : "a[href='#{token_url(occurrence.index)}']"
        node = fragment.at_css(selector)
        node["data-obsidian-occurrence"] = occurrence.index.to_s if node
      end

      note.occurrences.each do |occurrence|
        node = fragment.at_css("[data-obsidian-occurrence='#{occurrence.index}']")
        next unless node

        transform_reference_node(note, occurrence, node)
      end
      promote_embed_placeholders(fragment)
    end

    def promote_embed_placeholders(fragment)
      fragment.css("p").to_a.each do |paragraph|
        next if paragraph.xpath("./obsidian-embed").empty?

        replacement = Nokogiri::HTML5.fragment("")
        inline = new_paragraph_like(paragraph)
        discard_break = false
        paragraph.children.to_a.each do |child|
          if child.element? && child.name == "obsidian-embed"
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
        replacement["class"] = occurrence.kind == :embed ? "obsidian-embed obsidian-embed--unresolved obsidian-unresolved" : "obsidian-link obsidian-link--unresolved obsidian-unresolved"
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
          placeholder = Nokogiri::XML::Node.new("obsidian-embed", node.document)
          placeholder["data-source-id"] = target.id
          placeholder["data-fragment"] = occurrence.fragment.to_s
          placeholder["data-anchor-id"] = occurrence.anchor_id.to_s if occurrence.anchor_id
          placeholder["data-href"] = href
          node.replace(placeholder)
        else
          node.name = "a"
          node["href"] = href
          node["class"] = [node["class"], "obsidian-link"].compact.join(" ")
          node["data-note-id"] = target.id
          node.remove_attribute("data-obsidian-occurrence")
        end
      elsif occurrence.resolved_type == :attachment
        transform_attachment_node(occurrence, node)
      end
    end

    def transform_attachment_node(occurrence, node)
      entry = @attachments.fetch(occurrence.target_path)
      route = @url_builder.attachment_route(occurrence.target_path)
      href = @url_builder.href(route)

      kind = attachment_kind(occurrence.target_path, entry.media_type)
      replacement = if occurrence.kind == :link || kind == :download
        download_card(node.document, occurrence.target_path, href, entry.media_type)
      elsif kind == :image
        image_node(node.document, occurrence, href)
      elsif kind == :audio
        media_node(node.document, "audio", href, entry.media_type)
      elsif kind == :video
        media_node(node.document, "video", href, entry.media_type)
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
      fragment.css("pre code.language-mermaid").each { |node| node.parent["data-obsidian-mermaid"] = "true" }
      fragment.css("a[href]").each do |link|
        next unless link["href"].match?(%r{\Ahttps?://}i)

        link["rel"] = "noopener noreferrer"
      end
    end

    def assign_heading_ids(note, fragment)
      headings = note.anchors.select { |anchor| anchor.kind == :heading }
      fragment.css("h1, h2, h3, h4, h5, h6").each_with_index do |heading, index|
        anchor = headings[index]
        next unless anchor

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
      fragment.css("[data-obsidian-block-id]").each do |marker|
        parent = marker.parent
        identifier = marker["data-obsidian-block-id"]
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
              anchor["class"] = "obsidian-block-anchor"
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
      inputs = fragment.css("li.task-list-item input.task-list-item-checkbox")
      note.scanner.tasks.each_with_index do |task, index|
        input = inputs[index]
        next unless input

        state = task.state
        item = input.ancestors("li.task-list-item").first
        item["data-task"] = state if item
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
      fragment.css("blockquote").to_a.reverse_each do |blockquote|
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
        wrapper["class"] = "obsidian-callout obsidian-callout--#{type} callout"
        wrapper["data-callout"] = type
        wrapper["role"] = "note" unless fold
        wrapper["open"] = "open" if fold == "+"
        transfer_replacement_identity(blockquote, wrapper)
        header = Nokogiri::XML::Node.new(fold ? "summary" : "header", blockquote.document)
        header["class"] = "obsidian-callout__title callout__title"
        header.content = title
        wrapper.add_child(header)
        content = Nokogiri::XML::Node.new("div", blockquote.document)
        content["class"] = "obsidian-callout__content callout__content"
        blockquote.children.to_a.each { |child| content.add_child(child.unlink) }
        content.css("p").first.remove if content.css("p").first&.text.to_s.strip.empty?
        first_paragraph = content.css("p").first
        first_paragraph.children.first.remove if first_paragraph&.children&.first&.name == "br"
        wrapper.add_child(content) unless content.children.empty?
        blockquote.replace(wrapper)
      end
    end

    def annotate_code_blocks(note, fragment)
      source_blocks = note.document.select { |node| node.type == :code_block }
      fragment.css("pre").each_with_index do |pre, index|
        source = source_blocks[index]
        next unless source
        language = source.fence_info.to_s.split.first.to_s.downcase.gsub(/[^a-z0-9_+-]/, "")
        next if language.empty?

        code = pre.at_css("code")
        code["class"] = [code["class"], "language-#{language}"].compact.join(" ") if code
        pre["lang"] = language
        pre["data-obsidian-mermaid"] = "true" if language == "mermaid"
      end
    end

    def build_published_site_model
      relations = @relations.sort_by do |relation|
        [relation.source_id, relation.target_id, relation.kind.to_s, relation.fragment.to_s, span_key(relation.source_span)]
      end
      backlinks = relation_index(:link)
      embedded_by = relation_index(:embed)
      direct = @relations.group_by(&:source_id)

      notes = @notes.values.sort_by(&:id).map do |note|
        content = render_with_transclusions(note.id, [], note.id)
        assert_block_anchors_rendered(note, content)
        PublishedNote.new(
          id: note.id,
          title: note.title,
          route: note.route,
          content: content,
          properties: note.properties,
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
          base_data: published_note_base_data(note),
          links: relation_cards(direct.fetch(note.id, []).select { |item| item.kind == :link }),
          backlinks: relation_cards(backlinks.fetch(note.id, []), source: true),
          embedded_by: relation_cards(embedded_by.fetch(note.id, []), source: true)
        )
      end
      PublishedSiteModel.new(
        notes: notes,
        notes_by_id: notes.to_h { |note| [note.id, note] },
        relations: relations,
        graph_edges: graph_edges_for(relations)
      )
    end

    def render_with_transclusions(note_id, stack, host_id)
      note = @notes.fetch(note_id)
      fragment = note.base_fragment.dup
      fragment.css("obsidian-embed").each do |placeholder|
        target_id = placeholder["data-source-id"]
        if stack.include?(target_id) || target_id == note_id
          replacement = Nokogiri::XML::Node.new("span", fragment.document)
          replacement["class"] = "obsidian-embed obsidian-embed--cycle"
          replacement.content = "Embed cycle"
          transfer_replacement_identity(placeholder, replacement)
          placeholder.replace(replacement)
          next
        end

        target_html = render_with_transclusions(target_id, stack + [note_id], host_id)
        target_fragment = Nokogiri::HTML5.fragment(target_html)
        selected = select_transclusion_fragment(
          target_fragment,
          placeholder["data-fragment"],
          placeholder["data-anchor-id"]
        )
        @render_sequence += 1
        prefix = "embed-#{@url_builder.slug(host_id)}-#{@render_sequence}-"
        rewrite_fragment_ids(selected, prefix)

        wrapper = Nokogiri::XML::Node.new("section", fragment.document)
        wrapper["class"] = "obsidian-transclusion obsidian-embed"
        wrapper["data-source-id"] = target_id
        transfer_replacement_identity(placeholder, wrapper)
        source = Nokogiri::XML::Node.new("a", fragment.document)
        source["class"] = "obsidian-transclusion__source obsidian-embed__source"
        source["href"] = placeholder["data-href"]
        source.content = "From #{@notes.fetch(target_id).title}"
        wrapper.add_child(source)
        embedded_content = Nokogiri::XML::Node.new("div", fragment.document)
        embedded_content["class"] = "obsidian-transclusion__content obsidian-embed__content"
        selected.children.to_a.each { |child| embedded_content.add_child(child.unlink) }
        wrapper.add_child(embedded_content)
        placeholder.replace(wrapper)
      end
      fragment.to_html
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
      if target["class"].to_s.split.include?("obsidian-block-anchor") && target.next_element
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
      span["class"] = "obsidian-embed obsidian-embed--unresolved"
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
      fragment.css("a[href^='#']").each do |link|
        old = link["href"].delete_prefix("#")
        link["href"] = "##{mapping.fetch(old, "#{prefix}#{old}")}"
      end
    end

    def published_note_base_data(note)
      properties = note.properties
      obsidian = {
        "kind" => "note",
        "id" => note.id,
        "content_type" => note.content_type,
        "published_at" => note.published_at,
        "route" => note.route,
        "href" => @url_builder.href(note.route),
        "absolute_url" => @url_builder.absolute_url(note.route),
        "aliases" => Array(properties["aliases"]),
        "tags" => Array(properties["tags"]),
        "cssclasses" => Array(properties["cssclasses"]),
        "created" => note.created,
        "updated" => note.updated,
        "has_h1" => note.has_h1,
        "source_links" => repository_links(note.id)
      }
      {
        "title" => note.title,
        "description" => properties["description"] || note.preview,
        "image" => properties["image"],
        "obsidian" => obsidian
      }.compact
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

    def build_generated_files(pages, model, theme_output)
      theme_output.artifacts.filter_map do |artifact|
        case artifact
        when "catalog"
          json_file("/assets/obsidian/catalog.v1.json", catalog_payload(model))
        when "graph"
          json_file("/assets/obsidian/graph.v1.json", graph_payload(model))
        when "search"
          json_file("/assets/obsidian/search.v1.json", search_payload(model))
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
          { "id" => note.id, "title" => note.title, "url" => @url_builder.href(note.route), "tags" => Array(note.properties["tags"]) }
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

    def json_file(route, payload)
      GeneratedFile.new(route: route, content: "#{JSON.generate(payload)}\n", media_type: "application/json")
    end

    def sitemap_xml(pages)
      urls = pages.map(&:route).reject { |route| route == "/404.html" }.sort
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
        warning("feed_skipped_missing_time", "feed skipped because a public note has no property or Git update time")
        return nil
      end

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
          size: entry.size
        )
      end
    end

    def preflight_routes(pages, generated_files, copied_assets, reserved_namespaces)
      registry = {}
      (pages + generated_files + copied_assets).each do |output|
        key = @url_builder.collision_key(output.route)
        if registry.key?(key)
          error("route_collision", "output route collides with #{registry[key]}", output.route)
        else
          registry[key] = output.route
        end
      end

      namespace_keys = reserved_namespaces.map do |namespace|
        @url_builder.collision_key(namespace).delete_suffix("/")
      end
      pages.select { |page| page.data.dig("obsidian", "kind") == "note" }.each do |page|
        page_key = @url_builder.collision_key(page.route).delete_suffix("/")
        next unless namespace_keys.any? { |namespace| page_key == namespace || page_key.start_with?("#{namespace}/") }

        error("route_collision", "note route collides with a generated system namespace", page.route)
      end

      return unless production?
      index_count = pages.count { |page| page.route == "/" }
      error("invalid_index_count", "production must generate exactly one /index.html", nil) unless index_count == 1
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

      basename = File.basename(rooted, NOTE_EXTENSION).unicode_normalize(:nfc).downcase(:fold)
      candidates = @basename_index.fetch(basename, [])
      return [candidates.first, false] if candidates.one?
      return [nil, true] if candidates.length > 1

      [nil, false]
    end

    def resolve_attachment_path(source_id, raw_target)
      decoded = safe_decode(raw_target).unicode_normalize(:nfc).tr("\\", "/").delete_prefix("/")
      return nil if decoded.empty?

      candidates = []
      candidates << decoded
      relative = clean_relative(File.dirname(source_id), decoded)
      candidates << relative if relative && relative != decoded
      candidates.each { |candidate| return candidate if @attachments.key?(candidate) }

      return nil if decoded.include?("/")

      folded = File.basename(decoded).unicode_normalize(:nfc).downcase(:fold)
      matches = @attachments.keys.select do |path|
        File.basename(path).unicode_normalize(:nfc).downcase(:fold) == folded
      end
      matches.one? ? matches.first : nil
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

    def attachment_kind(path, media_type)
      extension = File.extname(path).downcase
      type = media_type.to_s.downcase
      return :download if CANVAS_BASE_EXTENSIONS.include?(extension)
      return :image if IMAGE_EXTENSIONS.include?(extension)
      return :pdf if extension == ".pdf"

      if %w[.webm .3gp].include?(extension)
        return :audio if type.start_with?("audio/")
        return :video if type.start_with?("video/")
        return nil
      end

      return :audio if AUDIO_EXTENSIONS.include?(extension)
      return :video if VIDEO_EXTENSIONS.include?(extension)

      nil
    end

    def deterministic_updated(note)
      note.properties["updated"] || note.entry.last_committed_at
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

    def source_slice(lines, position)
      return "" unless position
      line = lines.fetch(position.fetch(:start_line) - 1, "")
      line[(position.fetch(:start_column) - 1)...position.fetch(:end_column)].to_s
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
      copy.css("script, style, template, obsidian-embed, .obsidian-transclusion__source").remove
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
      source = Nokogiri::XML::Node.new("source", document)
      source["src"] = href
      source["type"] = media_type.to_s unless media_type.to_s.empty?
      node.add_child(source)
      node
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
      node["class"] = "obsidian-download-card attachment-card"
      node["href"] = href
      node["download"] = ""
      title = Nokogiri::XML::Node.new("span", document)
      title["class"] = "obsidian-download-card__title attachment-card__title"
      title.content = File.basename(path)
      meta = Nokogiri::XML::Node.new("span", document)
      meta["class"] = "obsidian-download-card__meta attachment-card__type"
      meta.content = media_type.to_s.empty? ? "Download" : media_type.to_s
      node.add_child(title)
      node.add_child(meta)
      node
    end

    def unresolved_attachment_node(document, path)
      node = Nokogiri::XML::Node.new("span", document)
      node["class"] = "obsidian-embed obsidian-embed--unresolved obsidian-unresolved"
      node["role"] = "status"
      node.content = path
      node
    end

    def css_escape(value)
      value.to_s.gsub(/([^a-zA-Z0-9_-])/) { |char| "\\#{char.ord.to_s(16)} " }
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
