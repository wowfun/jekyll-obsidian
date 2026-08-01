# frozen_string_literal: true

require "find"
require "json"
require "open3"
require "pathname"
require "jekyll"
require_relative "../jekyll_obsidian"

module JekyllObsidian
  module Adapter
    THEMES = %w[blog docs digital-garden].freeze
    CONTENT_TYPES = %w[page post doc].freeze
    DIRECTORY_CONTENT_TYPES = %w[post doc].freeze
    FEATURE_IDS = %w[search tags feed graph relations previews outline].freeze
    DEFAULT_CONTENT = {
      "default_type" => "page",
      "directories" => { "post" => ["blog"], "doc" => ["docs"] }
    }.freeze
    BUNDLED_FEATURE_IDS = %w[search graph previews preview math mermaid].freeze
    MANIFEST_FEATURE_ALIASES = { "previews" => "preview" }.freeze
    CONFIG_KEYS = %w[source syntax_profile theme repository edit_branch content features].freeze
    CONTENT_KEYS = %w[default_type directories].freeze
    MIME_TYPES = {
      ".avif" => "image/avif",
      ".bmp" => "image/bmp",
      ".base" => "application/json",
      ".canvas" => "application/json",
      ".3gp" => "audio/3gpp",
      ".flac" => "audio/flac",
      ".gif" => "image/gif",
      ".jpeg" => "image/jpeg",
      ".jpg" => "image/jpeg",
      ".m4a" => "audio/mp4",
      ".md" => "text/markdown",
      ".mkv" => "video/x-matroska",
      ".mov" => "video/quicktime",
      ".mp3" => "audio/mpeg",
      ".mp4" => "video/mp4",
      ".ogg" => "audio/ogg",
      ".ogv" => "video/ogg",
      ".pdf" => "application/pdf",
      ".png" => "image/png",
      ".svg" => "image/svg+xml",
      ".wav" => "audio/wav",
      ".webm" => "video/webm",
      ".webp" => "image/webp"
    }.freeze

    class GeneratedPage < Jekyll::PageWithoutAFile
      attr_reader :obsidian_route

      def initialize(site, output, generated: false)
        @obsidian_route = output.route
        directory, filename = self.class.route_parts(output.route)
        super(site, site.source, directory, filename)
        self.content = output.content
        self.data = generated ? {} : deep_copy(output.data)
        data["layout"] = nil if generated
        data["permalink"] = output.route
        data["render_with_liquid"] = false
        data["obsidian_generated"] = true
      end

      def self.route_parts(route)
        return ["", "index.html"] if route == "/"

        clean = route.delete_prefix("/")
        if clean.end_with?("/")
          [clean.delete_suffix("/"), "index.html"]
        else
          directory = File.dirname(clean)
          directory = "" if directory == "."
          [directory, File.basename(clean)]
        end
      end

      private

      def deep_copy(value)
        Marshal.load(Marshal.dump(value))
      end
    end

    class ProjectedStaticFile < Jekyll::StaticFile
      attr_reader :obsidian_route, :source_path

      def initialize(site, source_root, source_relative_path, route)
        @source_path = File.join(source_root, source_relative_path)
        @obsidian_route = route
        super(site, source_root, File.dirname(source_relative_path), File.basename(source_relative_path))
        @relative_path = route
      end

      def path
        @source_path
      end

      def url
        @obsidian_route
      end

      def destination(destination_root)
        @obsidian_destinations ||= {}
        @obsidian_destinations[destination_root] ||= @site.in_dest_dir(
          destination_root,
          Jekyll::URL.unescape_path(@obsidian_route.delete_prefix("/"))
        )
      end

      def destination_rel_dir
        File.dirname(@obsidian_route)
      end
    end

    module_function

    def prepare_site(site)
      obsidian = validate_obsidian_configuration(site)
      source = obsidian.fetch("source")
      assert_safe_destination(site, source)
      site.exclude = Array(site.exclude).dup
      site.exclude << source unless site.exclude.include?(source)
      site.config["exclude"] = site.exclude.dup
      site.config["obsidian"] = obsidian
    end

    def validate_obsidian_configuration(site)
      raw = site.config["obsidian"]
      fatal("obsidian must be a mapping") unless raw.nil? || raw.is_a?(Hash)
      configured = raw || {}
      unknown = configured.keys.map(&:to_s) - CONFIG_KEYS
      fatal("obsidian contains unsupported key: #{unknown.sort.first}") unless unknown.empty?

      source = validate_source_configuration(site, configured.fetch("source", "vault"))
      theme = configured.fetch("theme", "digital-garden")
      unless theme.is_a?(String) && THEMES.include?(theme)
        fatal("obsidian.theme must be one of: #{THEMES.join(", ")}")
      end

      syntax_profile = configured.fetch("syntax_profile", "ofm@1")
      fatal("obsidian.syntax_profile must be a string") unless syntax_profile.is_a?(String)
      repository = configured.fetch("repository", "")
      fatal("obsidian.repository must be a string") unless repository.is_a?(String)
      edit_branch = configured.fetch("edit_branch", "main")
      fatal("obsidian.edit_branch must be a non-empty string") unless edit_branch.is_a?(String) && !edit_branch.empty?

      {
        "source" => source,
        "syntax_profile" => syntax_profile,
        "theme" => theme,
        "repository" => repository,
        "edit_branch" => edit_branch,
        "content" => validate_content_configuration(site, source, configured["content"]),
        "features" => validate_feature_configuration(configured["features"])
      }
    end

    def validate_source_configuration(site, raw)
      fatal("obsidian.source must be a repository-relative directory") unless raw.is_a?(String)

      source = raw.unicode_normalize(:nfc).tr("\\", "/")
      path = Pathname.new(source)
      if source.empty? || source == "." || path.absolute? || path.cleanpath.to_s != source || source.split("/").any? { |part| part.empty? || part == ".." }
        fatal("obsidian.source must be a normalized repository-relative directory")
      end

      Array(site.include).each do |included|
        next unless included.is_a?(String)
        normalized = included.delete_prefix("./").delete_suffix("/")
        fatal("obsidian.source overlaps Jekyll include: #{included}") if path_overlap?(source, normalized)
      end

      collections_dir = site.config.fetch("collections_dir", "").to_s.delete_suffix("/")
      Array(site.collection_names).each do |label|
        collection_path = [collections_dir, "_#{label}"].reject(&:empty?).join("/")
        fatal("obsidian.source overlaps Jekyll collection #{label}") if path_overlap?(source, collection_path)
      end

      absolute = site.in_source_dir(source)
      fatal("obsidian.source does not exist: #{source}") unless File.directory?(absolute)
      assert_regular_directory_chain(site.source, absolute)
      real_source = File.realpath(site.source)
      real_vault = File.realpath(absolute)
      unless real_vault == real_source || real_vault.start_with?("#{real_source}#{File::SEPARATOR}")
        fatal("obsidian.source escapes the repository")
      end
      fatal("obsidian.source cannot be the repository root") if real_vault == real_source
      source
    rescue ArgumentError, SystemCallError => exception
      fatal("invalid obsidian.source: #{exception.message}")
    end

    def validate_content_configuration(site, source, raw)
      fatal("obsidian.content must be a mapping") unless raw.nil? || raw.is_a?(Hash)
      content = raw || DEFAULT_CONTENT
      unknown = content.keys.map(&:to_s) - CONTENT_KEYS
      fatal("obsidian.content contains unsupported key: #{unknown.sort.first}") unless unknown.empty?
      default_type = content.fetch("default_type", "page")
      unless default_type.is_a?(String) && CONTENT_TYPES.include?(default_type)
        fatal("obsidian.content.default_type must be one of: #{CONTENT_TYPES.join(", ")}")
      end

      raw_directories = content.fetch("directories", DEFAULT_CONTENT.fetch("directories"))
      fatal("obsidian.content.directories must be a mapping") unless raw_directories.is_a?(Hash)
      unknown = raw_directories.keys.map(&:to_s) - DIRECTORY_CONTENT_TYPES
      fatal("obsidian.content.directories contains unsupported type: #{unknown.sort.first}") unless unknown.empty?

      directories = DIRECTORY_CONTENT_TYPES.to_h do |type|
        values = raw_directories.fetch(type, [])
        fatal("obsidian.content.directories.#{type} must be an array of paths") unless values.is_a?(Array)
        normalized = values.map do |value|
          normalize_content_directory(site, source, type, value)
        end
        fatal("obsidian.content.directories.#{type} contains duplicate paths") unless normalized.uniq.length == normalized.length
        [type, normalized.sort]
      end

      assignments = directories.flat_map { |type, paths| paths.map { |path| [type, path] } }
      assignments.combination(2) do |(left_type, left), (right_type, right)|
        next if left_type == right_type
        next unless path_overlap?(left, right)

        fatal("obsidian.content.directories overlap across #{left_type} and #{right_type}: #{left}, #{right}")
      end

      { "default_type" => default_type, "directories" => directories }
    end

    def normalize_content_directory(site, source, type, raw)
      fatal("obsidian.content.directories.#{type} entries must be strings") unless raw.is_a?(String)
      normalized = raw.unicode_normalize(:nfc).tr("\\", "/")
      path = Pathname.new(normalized)
      if normalized.empty? || normalized == "." || path.absolute? || path.cleanpath.to_s != normalized || normalized.split("/").any? { |part| part.empty? || part == ".." }
        fatal("obsidian.content.directories.#{type} contains an unsafe path: #{raw.inspect}")
      end

      root = site.in_source_dir(source)
      cursor = root
      normalized.split("/").each do |part|
        cursor = File.join(cursor, part)
        stat = File.lstat(cursor)
        fatal("obsidian.content.directories.#{type} cannot contain symlink path components") if stat.symlink?
      rescue Errno::ENOENT
        break
      end
      if File.exist?(cursor) && !File.directory?(cursor)
        fatal("obsidian.content.directories.#{type} must refer to directories")
      end
      normalized
    rescue ArgumentError, SystemCallError => exception
      fatal("invalid obsidian.content.directories.#{type}: #{exception.message}")
    end

    def validate_feature_configuration(raw)
      fatal("obsidian.features must be a mapping") unless raw.nil? || raw.is_a?(Hash)
      features = raw || {}
      unknown = features.keys.map(&:to_s) - FEATURE_IDS
      fatal("obsidian.features contains unsupported feature: #{unknown.sort.first}") unless unknown.empty?

      features.keys.sort.to_h do |feature|
        value = features.fetch(feature)
        unless value == true || value == false
          fatal("obsidian.features.#{feature} must be a YAML boolean")
        end
        [feature, value]
      end
    end

    def assert_regular_directory_chain(root, target)
      relative = Pathname.new(target).relative_path_from(Pathname.new(root)).each_filename.to_a
      cursor = root
      relative.each do |part|
        cursor = File.join(cursor, part)
        stat = File.lstat(cursor)
        fatal("obsidian.source cannot contain symlink path components") if stat.symlink?
      end
    end

    def path_overlap?(left, right)
      return false if right.nil? || right.empty?
      left == right || left.start_with?("#{right}/") || right.start_with?("#{left}/")
    end

    def assert_vault_was_not_read(site, source)
      root = site.in_source_dir(source)
      leaked = []
      site.pages.each { |page| leaked << page.path if path_inside?(page.path, root, site.source) }
      site.static_files.each { |file| leaked << file.path if path_inside?(file.path, root, site.source) }
      site.collections.each_value do |collection|
        collection.docs.each { |document| leaked << document.path if path_inside?(document.path, root, site.source) }
      end
      return if leaked.empty?

      fatal("obsidian.source entered Jekyll Reader despite exclusion: #{leaked.sort.first}")
    end

    def path_inside?(candidate, root, site_source)
      return false if candidate.nil? || candidate.to_s.empty?
      expanded = File.expand_path(candidate.to_s, site_source)
      expanded_root = File.expand_path(root)
      return true if path_descendant?(expanded, expanded_root)
      return false unless File.exist?(expanded) || File.symlink?(expanded)

      resolved = File.realpath(expanded)
      resolved_root = File.realpath(expanded_root)
      path_descendant?(resolved, resolved_root)
    rescue SystemCallError => exception
      fatal("cannot resolve Jekyll Reader input #{candidate}: #{exception.message}")
    end

    def path_descendant?(candidate, root)
      candidate == root || candidate.start_with?("#{root}#{File::SEPARATOR}")
    end

    def assert_safe_destination(site, source)
      repository_root = File.expand_path(site.source)
      vault_root = File.expand_path(site.in_source_dir(source))
      destination_root = File.expand_path(site.dest)

      if path_descendant?(destination_root, vault_root) || path_descendant?(vault_root, destination_root)
        fatal("destination overlaps obsidian.source")
      end
      if path_descendant?(repository_root, destination_root)
        fatal("destination cannot contain the repository source")
      end

      assert_no_destination_symlink_components(destination_root)
      return unless File.exist?(destination_root)
      fatal("destination must be a directory: #{destination_root}") unless File.directory?(destination_root)

      Find.find(destination_root) do |entry|
        fatal("destination tree contains a symlink: #{entry}") if File.lstat(entry).symlink?
      end
    rescue SystemCallError => exception
      fatal("cannot validate destination #{site.dest}: #{exception.message}")
    end

    def assert_no_destination_symlink_components(destination)
      cursor = Pathname.new(File::SEPARATOR)
      Pathname.new(destination).each_filename do |component|
        cursor = cursor.join(component)
        stat = File.lstat(cursor)
        fatal("destination path contains a symlink: #{cursor}") if stat.symlink?
      rescue Errno::ENOENT
        break
      end
    end

    def build_snapshot(site, source)
      root = site.in_source_dir(source)
      git_times = git_time_map(site, source)
      entries = []
      Find.find(root) do |absolute|
        relative = Pathname.new(absolute).relative_path_from(Pathname.new(root)).to_s
        next if relative == "."

        stat = File.lstat(absolute)
        fatal("vault symlink rejected: #{relative}") if stat.symlink?
        if relative == ".obsidian" || relative.start_with?(".obsidian#{File::SEPARATOR}")
          Find.prune if stat.directory?
          next
        end

        next if stat.directory?
        fatal("vault contains a non-regular file: #{relative}") unless stat.file?

        normalized = relative.tr(File::SEPARATOR, "/")
        kind = File.extname(normalized).downcase == ".md" ? :note : :attachment
        times = git_times.fetch(normalized, {})
        entries << SnapshotEntry.new(
          path: normalized,
          bytes: kind == :note ? File.binread(absolute) : nil,
          kind: kind,
          media_type: MIME_TYPES.fetch(File.extname(normalized).downcase, "application/octet-stream"),
          size: stat.size,
          first_committed_at: times[:first],
          last_committed_at: times[:last]
        )
      end
      Snapshot.new(entries: entries.sort_by(&:path))
    rescue Errno::ENOENT => exception
      fatal("vault changed during snapshot: #{exception.message}")
    end

    def git_time_map(site, source)
      command = [
        "git", "-C", site.source, "-c", "core.quotePath=false",
        "log", "--format=%x1e%aI", "--name-only", "--", source
      ]
      stdout, _stderr, status = Open3.capture3(*command)
      return {} unless status.success?

      result = {}
      current_time = nil
      stdout.each_line do |line|
        stripped = line.strip
        next if stripped.empty?
        if stripped.start_with?("\x1e")
          # Git 2.45+ emits Z for UTC while older versions emit +00:00.
          current_time = stripped.delete_prefix("\x1e").sub(/\+00:00\z/, "Z")
          next
        end
        next unless current_time
        prefix = "#{source}/"
        next unless stripped.start_with?(prefix)

        relative = stripped.delete_prefix(prefix).unicode_normalize(:nfc)
        item = (result[relative] ||= { first: current_time, last: current_time })
        item[:first] = current_time
      end
      result
    rescue SystemCallError
      {}
    end

    def repository_identity(site)
      explicit = site.config.dig("obsidian", "repository").to_s.strip
      return explicit unless explicit.empty?
      environment = ENV.fetch("GITHUB_REPOSITORY", "").strip
      return environment unless environment.empty?

      stdout, _stderr, status = Open3.capture3("git", "-C", site.source, "config", "--get", "remote.origin.url")
      return nil unless status.success?
      remote = stdout.strip
      match = remote.match(%r{(?:github\.com[:/])([^/\s]+/[^/\s]+?)(?:\.git)?\z}i)
      match && match[1]
    rescue SystemCallError
      nil
    end

    def compile(site, source)
      repository = repository_identity(site)
      Jekyll.logger.warn("Obsidian:", "repository identity unavailable; GitHub collaboration links are hidden") unless repository
      obsidian = site.config.fetch("obsidian")
      request = BuildRequest.new(
        snapshot: build_snapshot(site, source),
        config: BuildConfig.new(
          title: site.config["title"].to_s,
          description: site.config["description"].to_s,
          lang: site.config.fetch("lang", "en").to_s,
          url: site.config["url"].to_s,
          baseurl: site.config["baseurl"].to_s,
          source: source,
          syntax_profile: obsidian.fetch("syntax_profile"),
          theme: obsidian.fetch("theme"),
          content: obsidian.fetch("content"),
          features: obsidian.fetch("features"),
          repository: repository.to_s,
          edit_branch: obsidian.fetch("edit_branch"),
          environment: ENV.fetch("JEKYLL_ENV", "development")
        )
      )
      VaultCompiler.compile(request)
    end

    def generated_objects(site, result, source)
      pages = result.pages.map { |output| GeneratedPage.new(site, output) }
      generated = result.generated_files.map do |output|
        page_output = PageOutput.new(route: output.route, content: output.content, data: {})
        GeneratedPage.new(site, page_output, generated: true)
      end
      vault_root = site.in_source_dir(source)
      assets = result.copied_assets.map do |output|
        source_path = site.in_source_dir(source, output.source_path)
        stat = File.lstat(source_path)
        fatal("projected vault asset became a symlink: #{output.source_path}") if stat.symlink?
        fatal("projected vault asset is no longer regular: #{output.source_path}") unless stat.file?
        ProjectedStaticFile.new(site, vault_root, output.source_path, output.route)
      end
      [pages + generated, assets]
    end

    def app_asset_objects(site, theme:, features:)
      root = site.in_source_dir(".jekyll-obsidian-cache", "assets")
      real_site_root, real_cache_root = validate_application_asset_root!(site, root)
      manifest_path = File.join(root, "manifest.json")
      unless File.file?(manifest_path)
        fatal("application asset manifest is missing: #{manifest_path}") unless Jekyll.env == "development"

        Jekyll.logger.warn("Obsidian:", "application asset manifest is missing; frontend assets are unavailable")
        return []
      end
      validate_application_asset_file!(
        manifest_path,
        cache_root: root,
        real_cache_root: real_cache_root,
        real_site_root: real_site_root,
        label: "application asset manifest"
      )

      manifest = JSON.parse(File.read(manifest_path, encoding: "UTF-8"))
      fatal("asset manifest schema is unsupported") unless manifest["schema_version"] == 1
      entries = manifest["entries"]
      fatal("asset manifest entries must be a mapping") unless entries.is_a?(Hash)
      missing_themes = THEMES - entries.keys
      fatal("asset manifest is missing theme entry: #{missing_themes.first}") unless missing_themes.empty?
      unknown_themes = entries.keys - THEMES
      fatal("asset manifest contains an unsupported theme entry: #{unknown_themes.first}") unless unknown_themes.empty?

      entries.each do |entry_theme, entry|
        validate_manifest_entry!(entry, "entries.#{entry_theme}")
      end
      active_entry = entries[theme]
      fatal("asset manifest has no entry for active theme: #{theme}") unless active_entry.is_a?(Hash)

      manifest_features = manifest.fetch("features", {})
      fatal("asset manifest features must be a mapping") unless manifest_features.is_a?(Hash)
      manifest_features.each do |feature, entry|
        validate_manifest_file_list!(entry, "features.#{feature}")
      end

      files = active_entry.fetch("files").dup
      features.each do |feature, enabled|
        next unless enabled && BUNDLED_FEATURE_IDS.include?(feature)

        manifest_feature = MANIFEST_FEATURE_ALIASES.fetch(feature, feature)
        entry = manifest_features[manifest_feature]
        fatal("asset manifest is missing enabled bundle feature: features.#{manifest_feature}") unless entry
        files.concat(entry.fetch("files"))
      end
      files = files.uniq.sort
      allowlist = manifest["files"]
      if allowlist
        fatal("asset manifest files must be an array") unless allowlist.is_a?(Array)
        allowlist.each { |relative| validate_manifest_path!(relative) }
        outside_allowlist = files - allowlist
        fatal("active asset is absent from manifest files: #{outside_allowlist.first}") unless outside_allowlist.empty?
      end

      site.data["obsidian_assets"] = manifest
      files.map do |relative|
        validate_manifest_path!(relative)
        absolute = File.join(root, relative)
        validate_application_asset_file!(
          absolute,
          cache_root: root,
          real_cache_root: real_cache_root,
          real_site_root: real_site_root,
          label: "application asset #{relative}"
        )
        ProjectedStaticFile.new(site, root, relative, "/assets/obsidian/#{relative}")
      end
    rescue JSON::ParserError => exception
      fatal("invalid asset manifest: #{exception.message}")
    rescue SystemCallError => exception
      fatal("cannot load application assets: #{exception.message}")
    end

    def validate_application_asset_root!(site, root)
      site_root = File.expand_path(site.source)
      expanded_root = File.expand_path(root)
      unless path_descendant?(expanded_root, site_root) && expanded_root != site_root
        fatal("application asset cache escapes the site source")
      end

      assert_no_symlink_components!(site_root, expanded_root, "application asset cache")
      real_site_root = File.realpath(site_root)
      return [real_site_root, nil] unless File.exist?(expanded_root)

      stat = File.lstat(expanded_root)
      fatal("application asset cache must be a directory") unless stat.directory? && !stat.symlink?
      real_cache_root = File.realpath(expanded_root)
      unless path_descendant?(real_cache_root, real_site_root) && real_cache_root != real_site_root
        fatal("application asset cache resolves outside the site source")
      end
      [real_site_root, real_cache_root]
    rescue SystemCallError => exception
      fatal("cannot validate application asset cache: #{exception.message}")
    end

    def validate_application_asset_file!(path, cache_root:, real_cache_root:, real_site_root:, label:)
      fatal("#{label} has no validated cache root") unless real_cache_root
      expanded = File.expand_path(path)
      expanded_cache_root = File.expand_path(cache_root)
      unless path_descendant?(expanded, expanded_cache_root) && expanded != expanded_cache_root
        fatal("#{label} escapes the application asset cache")
      end

      assert_no_symlink_components!(expanded_cache_root, expanded, label)
      stat = File.lstat(expanded)
      fatal("#{label} is not a regular file") unless stat.file? && !stat.symlink?
      real_path = File.realpath(expanded)
      unless path_descendant?(real_path, real_cache_root) && path_descendant?(real_path, real_site_root)
        fatal("#{label} resolves outside the application asset cache or site source")
      end
    end

    def assert_no_symlink_components!(root, target, label)
      expanded_root = File.expand_path(root)
      expanded_target = File.expand_path(target)
      relative = Pathname.new(expanded_target).relative_path_from(Pathname.new(expanded_root))
      components = relative.each_filename.to_a
      cursor = expanded_root
      components.each_with_index do |component, index|
        cursor = File.join(cursor, component)
        stat = File.lstat(cursor)
        fatal("#{label} contains a symlink path component: #{cursor}") if stat.symlink?
        if index < components.length - 1 && !stat.directory?
          fatal("#{label} contains a non-directory path component: #{cursor}")
        end
      rescue Errno::ENOENT
        break
      end
    rescue ArgumentError => exception
      fatal("cannot validate #{label}: #{exception.message}")
    end

    def validate_manifest_entry!(entry, location)
      fatal("asset manifest #{location} must be a mapping") unless entry.is_a?(Hash)
      js = entry["js"]
      fatal("asset manifest #{location}.js is invalid") unless js.is_a?(String)
      validate_manifest_path!(js)
      if entry.key?("css")
        fatal("asset manifest #{location}.css is invalid") unless entry["css"].is_a?(String)
        validate_manifest_path!(entry["css"])
      end
      validate_manifest_file_list!(entry, location)
      fatal("asset manifest #{location}.files must contain its js") unless entry.fetch("files").include?(js)
      if entry.key?("css") && !entry.fetch("files").include?(entry["css"])
        fatal("asset manifest #{location}.files must contain its css")
      end
    end

    def validate_manifest_file_list!(entry, location)
      fatal("asset manifest #{location} must be a mapping") unless entry.is_a?(Hash)
      files = entry["files"]
      fatal("asset manifest #{location}.files must be an array") unless files.is_a?(Array)
      files.each { |relative| validate_manifest_path!(relative) }
    end

    def validate_manifest_path!(path)
      fatal("asset manifest contains an unsafe path") unless safe_relative_path?(path)
    end

    def safe_relative_path?(path)
      path.is_a?(String) && !path.empty? && !path.include?("\\") && !path.include?("\0") &&
        !Pathname.new(path).absolute? && Pathname.new(path).cleanpath.to_s == path &&
        path.split("/").none? { |part| part.empty? || part == "." || part == ".." }
    rescue ArgumentError
      false
    end

    def preflight_collisions(site, pages, static_files)
      registry = {}
      site.pages.each { |page| register_output!(registry, site, page, page.url, "Jekyll page #{page.path}") }
      site.static_files.each { |file| register_output!(registry, site, file, file.url, "Jekyll static file #{file.path}") }
      site.collections.each_value do |collection|
        collection.docs.each do |document|
          next unless document.write?

          register_output!(registry, site, document, document.url, "Jekyll document #{document.path}")
        end
      end
      pages.each { |page| register_output!(registry, site, page, page.obsidian_route, "obsidian output") }
      static_files.each { |file| register_output!(registry, site, file, file.obsidian_route, "obsidian asset") }
    end

    def register_output!(registry, site, output, route, owner)
      validate_output_route!(route)
      key = destination_collision_key(site, output.destination(site.dest))
      fatal("output route collision at #{route} (already owned by #{registry[key]})") if registry.key?(key)
      registry[key] = owner
    end

    def validate_output_route!(route)
      UrlBuilder.new(origin: "", baseurl: "").collision_key(route.to_s)
    rescue ArgumentError => exception
      fatal("unsafe output route #{route.inspect}: #{exception.message}")
    end

    def destination_collision_key(site, destination)
      root = File.expand_path(site.dest)
      expanded = File.expand_path(destination.to_s)
      unless path_descendant?(expanded, root) && expanded != root
        fatal("output destination escapes the configured destination: #{destination.inspect}")
      end

      Pathname.new(expanded).relative_path_from(Pathname.new(root)).to_s
        .tr(File::SEPARATOR, "/")
        .unicode_normalize(:nfc)
        .downcase(:fold)
    rescue ArgumentError => exception
      fatal("unsafe output destination #{destination.inspect}: #{exception.message}")
    end

    def log_diagnostics(result)
      result.diagnostics.each do |diagnostic|
        label = [diagnostic.path, diagnostic.code].compact.join(":")
        if diagnostic.severity == :error
          Jekyll.logger.error("Obsidian #{label}:", diagnostic.message)
        else
          Jekyll.logger.warn("Obsidian #{label}:", diagnostic.message)
        end
      end
    end

    def fatal(message)
      raise Jekyll::Errors::FatalException, message
    end

    class Generator < Jekyll::Generator
      safe false
      priority :highest

      def generate(site)
        source = site.config.fetch("obsidian").fetch("source")
        Adapter.assert_safe_destination(site, source)
        Adapter.assert_vault_was_not_read(site, source)
        result = Adapter.compile(site, source)
        Adapter.log_diagnostics(result)
        unless result.success?
          summary = result.diagnostics.select { |item| item.severity == :error }
            .map { |item| [item.path, item.code].compact.join(":") }
            .join(", ")
          Adapter.fatal("obsidian compilation failed: #{summary}")
        end

        site.data["obsidian_feed_available"] = result.generated_files.any? { |output| output.route == "/feed.xml" }
        pages, vault_assets = Adapter.generated_objects(site, result, source)
        app_assets = Adapter.app_asset_objects(site, theme: result.theme, features: result.features)
        Adapter.preflight_collisions(site, pages, vault_assets + app_assets)
        site.pages.concat(pages)
        site.static_files.concat(vault_assets).concat(app_assets)
      end
    end
  end
end

Jekyll::Hooks.register :site, :after_init do |site|
  JekyllObsidian::Adapter.prepare_site(site)
end
