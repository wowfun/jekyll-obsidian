# frozen_string_literal: true

require "find"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tempfile"
require "tmpdir"
require "jekyll"
require_relative "../jekyll_obsidian"
require_relative "workspace_layout"

module JekyllObsidian
  module Adapter
    BUNDLED_FEATURE_IDS = %w[search graph previews math mermaid].freeze
    CONFIG_KEYS = %w[source syntax_profile theme repository edit_branch content features i18n comments analytics contacts navigation].freeze
    GIT_FIRST_COMMIT_CACHE_VERSION = 1
    GITHUB_MARKDOWN_MANIFEST_INPUT = "JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_IN"
    GITHUB_MARKDOWN_MANIFEST_OUTPUT = "JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_OUT"
    IGNORED_CONTENT_DIRECTORIES = %w[.obsidian .trash].freeze
    STAGING_BASENAME_PATTERN = /\Avault-assets\.[A-Za-z0-9.-]+\z/
    StagingLease = Struct.new(:parent, :path, keyword_init: true)

    module SiteProcessCleanup
      def process(...)
        super
      ensure
        Adapter.cleanup_staging(self)
      end
    end

    class GeneratedPage < Jekyll::PageWithoutAFile
      attr_reader :website_route

      def initialize(site, output, generated: false)
        @compiler_generated_file = generated
        @website_route = output.route
        directory, filename = self.class.route_parts(output.route)
        super(site, site.source, directory, filename)
        self.content = output.content
        self.data = generated ? {} : output.data.dup
        data["layout"] = nil if generated
        data["permalink"] = output.route
        data["render_with_liquid"] = false
        data["website_generated"] = true
      end

      # Compiler-owned artifacts are already final bytes. Present an inert
      # source extension to Jekyll's renderer while the permalink retains the
      # public extension (including `.md`).
      def extname
        @compiler_generated_file ? ".website-generated" : super
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
    end

    class ProjectedStaticFile < Jekyll::StaticFile
      attr_reader :website_route, :source_path

      def initialize(site, source_root, source_relative_path, route)
        @source_path = File.join(source_root, source_relative_path)
        @website_route = route
        super(site, source_root, File.dirname(source_relative_path), File.basename(source_relative_path))
        @relative_path = route
      end

      def path
        @source_path
      end

      def url
        @website_route
      end

      def destination(destination_root)
        @website_destinations ||= {}
        @website_destinations[destination_root] ||= @site.in_dest_dir(
          destination_root,
          Jekyll::URL.unescape_path(@website_route.delete_prefix("/"))
        )
      end

      def destination_rel_dir
        File.dirname(@website_route)
      end
    end

    class << self

    def prepare_site(site)
      site.singleton_class.prepend(SiteProcessCleanup) unless site.singleton_class < SiteProcessCleanup
      website, _layout = normalize_website_configuration(site)
      exclude_bundled_source(site)
      site.config["website"] = website
    end

    def generate(site)
      source = site.config.fetch("website").fetch("source")
      layout = resolve_workspace_layout(site, source)
      assert_vault_was_not_read(site, layout)
      result = compile(site, layout)
      log_diagnostics(result)
      unless result.success?
        summary = result.diagnostics.select { |item| item.severity == :error }
          .map { |item| "#{[item.path, item.code].compact.join(":")} (#{item.message})" }
          .join(", ")
        fatal("website compilation failed: #{summary}")
      end

      staging_root = stage_vault_assets(site, layout, result)
      begin
        site.data["website_feed_available"] = result.generated_files.any? { |output| output.route == "/feed.xml" }
        site.data.merge!(result.site_data)
        pages, vault_assets = generated_objects(site, result, staging_root)
        app_assets = app_asset_objects(site, layout:, theme: result.theme, features: result.features)
        preflight_collisions(site, pages, vault_assets + app_assets)
        site.pages.concat(pages)
        site.static_files.concat(vault_assets).concat(app_assets)
      rescue StandardError
        cleanup_staging(site)
        raise
      end
    end

    def cleanup_staging(site)
      lease = site.remove_instance_variable(:@jekyll_website_staging_lease)
      return unless lease.is_a?(StagingLease)
      return unless File.dirname(lease.path) == lease.parent
      return unless File.basename(lease.path).match?(STAGING_BASENAME_PATTERN)

      FileUtils.remove_entry(lease.path) if File.exist?(lease.path) || File.symlink?(lease.path)
    rescue NameError
      nil
    end

    private

    def normalize_website_configuration(site)
      if site.config.key?("obsidian")
        fatal("obsidian configuration is no longer supported; rename the root mapping to website")
      end
      raw = site.config["website"]
      fatal("website must be a mapping") unless raw.nil? || raw.is_a?(Hash)
      configured = raw || {}
      unknown = configured.keys.map(&:to_s) - CONFIG_KEYS
      fatal("website contains unsupported key: #{unknown.sort.first}") unless unknown.empty?

      source = configured.key?("source") ? configured["source"] : WorkspaceLayout::DEFAULT_SOURCE
      layout = resolve_workspace_layout(site, source)
      website = {
        "source" => layout.source,
        "syntax_profile" => configured.fetch("syntax_profile", "ofm@1"),
        "theme" => configured.fetch("theme", "docs"),
        "repository" => configured.fetch("repository", ""),
        "edit_branch" => configured.fetch("edit_branch", "main"),
        "content" => configured["content"],
        "features" => configured["features"],
        "i18n" => configured["i18n"],
        "comments" => configured["comments"],
        "analytics" => configured["analytics"],
        "contacts" => configured["contacts"],
        "navigation" => configured["navigation"]
      }
      [website, layout]
    end

    def resolve_workspace_layout(site, source)
      WorkspaceLayout.resolve(site:, source:)
    rescue WorkspaceLayout::Invalid => exception
      fatal(exception.message)
    end

    def exclude_bundled_source(site)
      excluded = (Array(site.exclude).map(&:to_s) + [WorkspaceLayout::BUNDLED_SOURCE_BASENAME]).uniq
      site.exclude = excluded
      site.config["exclude"] = excluded
    end

    def assert_vault_was_not_read(site, layout)
      root = layout.source_root
      leaked = []
      site.pages.each { |page| leaked << page.path if path_inside?(page.path, root, site.source) }
      site.static_files.each { |file| leaked << file.path if path_inside?(file.path, root, site.source) }
      site.collections.each_value do |collection|
        collection.docs.each { |document| leaked << document.path if path_inside?(document.path, root, site.source) }
      end
      return if leaked.empty?

      fatal("website.source entered Jekyll Reader despite exclusion: #{leaked.sort.first}")
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

    def build_snapshot(layout)
      root = layout.source_root
      git_first_commit_times = git_first_commit_time_map(layout)
      entries = []
      Find.find(root) do |absolute|
        relative = Pathname.new(absolute).relative_path_from(Pathname.new(root)).to_s
        next if relative == "."

        stat = File.lstat(absolute)
        fatal("vault symlink rejected: #{relative}") if stat.symlink?
        ignored = IGNORED_CONTENT_DIRECTORIES.any? do |directory|
          relative == directory || relative.start_with?("#{directory}#{File::SEPARATOR}")
        end
        if ignored
          Find.prune if stat.directory?
          next
        end

        next if stat.directory?
        fatal("vault contains a non-regular file: #{relative}") unless stat.file?

        normalized = relative.tr(File::SEPARATOR, "/")
        kind = if File.extname(normalized).downcase == ".md"
          :note
        elsif File.basename(normalized) == LocalizedCompiler::LOCALE_MANIFEST
          :locale_manifest
        else
          :attachment
        end
        flags = File::RDONLY | (File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0)
        File.open(absolute, flags) do |file|
          pinned = file.stat
          fatal("vault file changed during snapshot: #{relative}") unless pinned.file? && pinned.dev == stat.dev && pinned.ino == stat.ino
          entries << SnapshotEntry.new(
            path: normalized,
            bytes: %i[note locale_manifest].include?(kind) ? file.read : nil,
            kind: kind,
            media_type: kind == :note ? "text/markdown" : MediaPolicy.media_type(normalized),
            size: pinned.size,
            device: pinned.dev,
            inode: pinned.ino,
            mtime_ns: pinned.mtime.to_i * 1_000_000_000 + pinned.mtime.nsec,
            first_committed_at: git_first_commit_times[normalized]
          )
        end
      end
      Snapshot.new(entries: entries.sort_by(&:path))
    rescue Errno::ENOENT => exception
      fatal("vault changed during snapshot: #{exception.message}")
    end

    def git_first_commit_time_map(layout)
      source = layout.source
      head, _head_error, head_status = Open3.capture3("git", "-C", layout.workspace_root, "rev-parse", "HEAD")
      return {} unless head_status.success?

      head = head.strip
      cache_path = File.join(layout.jekyll_cache_root, "jekyll-obsidian-git-times.json")
      ensure_runtime_directory!(layout.jekyll_cache_root, "Jekyll cache")
      cached_bytes = read_regular_cache_file(cache_path, "Git first-commit cache")
      if cached_bytes
        cached = JSON.parse(cached_bytes)
        cached_times = cached["first_committed_at"]
        if cached["version"] == GIT_FIRST_COMMIT_CACHE_VERSION && cached["head"] == head &&
            cached["source"] == source && cached_times.is_a?(Hash) &&
            cached_times.all? { |path, time| path.is_a?(String) && time.is_a?(String) }
          return cached_times
        end
      end

      command = [
        "git", "-C", layout.workspace_root, "-c", "core.quotePath=false",
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
        result[relative] = current_time
      end
      FileUtils.mkdir_p(File.dirname(cache_path))
      temporary = Tempfile.create(["jekyll-obsidian-git-times.", ".tmp"], File.dirname(cache_path))
      temporary_path = temporary.path
      temporary.write(JSON.generate(
        "version" => GIT_FIRST_COMMIT_CACHE_VERSION,
        "head" => head,
        "source" => source,
        "first_committed_at" => result
      ))
      temporary.flush
      temporary.fsync
      temporary.close
      File.rename(temporary_path, cache_path)
      result
    rescue JSON::ParserError, SystemCallError
      {}
    ensure
      temporary.close if defined?(temporary) && temporary && !temporary.closed?
      FileUtils.rm_f(temporary_path) if defined?(temporary_path) && temporary_path
    end

    def ensure_runtime_directory!(root, label)
      FileUtils.mkdir_p(root)
      stat = File.lstat(root)
      unless stat.directory? && !stat.symlink? && File.realpath(root) == root
        fatal("#{label} must be a non-symlink directory")
      end
    rescue SystemCallError => exception
      fatal("cannot validate #{label}: #{exception.message}")
    end

    def read_regular_cache_file(path, label)
      return nil unless File.exist?(path) || File.symlink?(path)

      before = File.lstat(path)
      fatal("#{label} must be a non-symlink regular file") unless before.file? && !before.symlink?
      flags = File::RDONLY | (File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0)
      File.open(path, flags) do |file|
        opened = file.stat
        unless opened.file? && opened.dev == before.dev && opened.ino == before.ino
          fatal("#{label} changed while opening")
        end
        file.read
      end
    rescue SystemCallError => exception
      fatal("cannot read #{label}: #{exception.message}")
    end

    def repository_identity(site, layout)
      explicit = site.config.dig("website", "repository").to_s.strip
      return explicit unless explicit.empty?
      environment = ENV.fetch("GITHUB_REPOSITORY", "").strip
      return environment unless environment.empty?

      stdout, _stderr, status = Open3.capture3(
        "git", "-C", layout.workspace_root, "config", "--get", "remote.origin.url"
      )
      return nil unless status.success?
      remote = stdout.strip
      match = remote.match(%r{(?:github\.com[:/])([^/\s]+/[^/\s]+?)(?:\.git)?\z}i)
      match && match[1]
    rescue SystemCallError
      nil
    end

    def compile(site, layout)
      repository = repository_identity(site, layout)
      Jekyll.logger.warn("Website:", "repository identity unavailable; GitHub collaboration links are hidden") unless repository
      website = site.config.fetch("website")
      request = BuildRequest.new(
        snapshot: build_snapshot(layout),
        config: BuildConfig.new(
          title: site.config["title"].to_s,
          description: site.config["description"].to_s,
          lang: site.config.fetch("lang", "en").to_s,
          url: site.config["url"].to_s,
          baseurl: site.config["baseurl"].to_s,
          source: layout.source,
          syntax_profile: website.fetch("syntax_profile"),
          theme: website.fetch("theme"),
          content: website.fetch("content"),
          features: website.fetch("features"),
          i18n: website.fetch("i18n"),
          comments: website.fetch("comments"),
          analytics: website.fetch("analytics"),
          contacts: website.fetch("contacts"),
          navigation: website.fetch("navigation"),
          repository: repository.to_s,
          edit_branch: website.fetch("edit_branch"),
          environment: ENV.fetch("JEKYLL_ENV", "development")
        )
      )
      ensure_runtime_directory!(layout.application_cache_root, "Application cache")
      manifest_input = github_markdown_manifest_path(layout, GITHUB_MARKDOWN_MANIFEST_INPUT)
      manifest = manifest_input && read_regular_cache_file(manifest_input, "GitHub Markdown manifest")
      fatal("GitHub Markdown manifest does not exist") if manifest_input && manifest.nil?
      result = SiteCompilation.compile(
        request,
        transport: GitHubMarkdown::HttpTransport.new,
        cache_root: layout.application_cache_root,
        manifest: manifest
      )
      manifest_output = github_markdown_manifest_path(layout, GITHUB_MARKDOWN_MANIFEST_OUTPUT)
      if result.success? && manifest_output
        content = result.github_markdown_manifest || GitHubMarkdown.dump_manifest([])
        write_github_markdown_manifest(manifest_output, content)
      end
      result
    end

    def github_markdown_manifest_path(layout, environment_key)
      raw = ENV.fetch(environment_key, "").to_s
      return nil if raw.empty?

      path = File.expand_path(raw, layout.site_root)
      unless File.dirname(path) == layout.application_cache_root &&
          File.basename(path).match?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\.json\z/)
        fatal("#{environment_key} must name a JSON file directly inside the application cache")
      end
      path
    end

    def write_github_markdown_manifest(path, content)
      if File.exist?(path) || File.symlink?(path)
        stat = File.lstat(path)
        fatal("GitHub Markdown manifest output must be a non-symlink regular file") unless stat.file? && !stat.symlink?
      end
      temporary = Tempfile.create(["github-markdown-manifest.", ".tmp"], File.dirname(path))
      temporary_path = temporary.path
      temporary.binmode
      temporary.write(content)
      temporary.flush
      temporary.fsync
      temporary.close
      File.rename(temporary_path, path)
    rescue SystemCallError => exception
      fatal("cannot write GitHub Markdown manifest: #{exception.message}")
    ensure
      temporary.close if defined?(temporary) && temporary && !temporary.closed?
      FileUtils.rm_f(temporary_path) if defined?(temporary_path) && temporary_path
    end

    def stage_vault_assets(site, layout, result)
      cleanup_staging(site)
      FileUtils.mkdir_p(layout.application_cache_root)
      validate_application_cache_root!(layout)
      staging_root = Dir.mktmpdir("vault-assets.", layout.application_cache_root)
      vault_root = layout.source_root
      result.copied_assets.each do |output|
        source_path = File.join(vault_root, output.source_path)
        destination = File.join(staging_root, output.source_path)
        FileUtils.mkdir_p(File.dirname(destination))
        flags = File::RDONLY | (File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0)
        File.open(source_path, flags) do |file|
          stat = file.stat
          actual_mtime_ns = stat.mtime.to_i * 1_000_000_000 + stat.mtime.nsec
          expected = [output.device, output.inode, output.size, output.mtime_ns]
          actual = [stat.dev, stat.ino, stat.size, actual_mtime_ns]
          fatal("vault asset changed after compilation: #{output.source_path}") unless stat.file? && actual == expected
          File.open(destination, File::WRONLY | File::CREAT | File::EXCL, 0o644) { |target| IO.copy_stream(file, target) }
        end
      end
      site.instance_variable_set(
        :@jekyll_website_staging_lease,
        StagingLease.new(parent: layout.application_cache_root, path: staging_root).freeze
      )
      staging_root
    rescue StandardError
      FileUtils.remove_entry(staging_root) if staging_root && File.exist?(staging_root)
      raise
    end

    def generated_objects(site, result, staging_root)
      pages = result.pages.map { |output| GeneratedPage.new(site, output) }
      generated = result.generated_files.map do |output|
        page_output = PageOutput.new(route: output.route, content: output.content, data: {})
        GeneratedPage.new(site, page_output, generated: true)
      end
      assets = result.copied_assets.map do |output|
        ProjectedStaticFile.new(site, staging_root, output.source_path, output.route)
      end
      [pages + generated, assets]
    end

    def app_asset_objects(site, layout:, theme:, features:)
      root = layout.application_assets_root
      validate_application_asset_root!(layout, root)
      manifest_path = File.join(root, "manifest.json")
      unless File.file?(manifest_path)
        fatal("application asset manifest is missing: #{manifest_path}") unless Jekyll.env == "development"

        Jekyll.logger.warn("Website:", "application asset manifest is missing; frontend assets are unavailable")
        return []
      end
      validate_application_asset_file!(
        manifest_path,
        cache_root: root,
        label: "application asset manifest"
      )

      manifest = JSON.parse(File.read(manifest_path, encoding: "UTF-8"))
      fatal("asset manifest schema is unsupported") unless manifest["schema_version"] == 1
      entries = manifest["entries"]
      fatal("asset manifest entries must be a mapping") unless entries.is_a?(Hash)
      active_entry = entries[theme]
      fatal("asset manifest has no entry for active theme: #{theme}") unless active_entry.is_a?(Hash)
      validate_manifest_entry!(active_entry, "entries.#{theme}")

      manifest_features = manifest.fetch("features", {})
      fatal("asset manifest features must be a mapping") unless manifest_features.is_a?(Hash)
      files = active_entry.fetch("files").dup
      features.each do |feature, enabled|
        next unless enabled && BUNDLED_FEATURE_IDS.include?(feature)

        entry = manifest_features[feature]
        fatal("asset manifest is missing enabled bundle feature: features.#{feature}") unless entry
        validate_manifest_file_list!(entry, "features.#{feature}")
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

      site.data["website_assets"] = manifest
      files.map do |relative|
        validate_manifest_path!(relative)
        absolute = File.join(root, relative)
        validate_application_asset_file!(
          absolute,
          cache_root: root,
          label: "application asset #{relative}"
        )
        ProjectedStaticFile.new(site, root, relative, "/assets/website/#{relative}")
      end
    rescue JSON::ParserError => exception
      fatal("invalid asset manifest: #{exception.message}")
    rescue SystemCallError => exception
      fatal("cannot load application assets: #{exception.message}")
    end

    def validate_application_cache_root!(layout)
      root = layout.application_cache_root
      stat = File.lstat(root)
      fatal("application cache must be a non-symlink directory") unless stat.directory? && !stat.symlink?
    rescue SystemCallError => exception
      fatal("cannot validate application cache: #{exception.message}")
    end

    def validate_application_asset_root!(layout, root)
      site_root = layout.site_root
      expanded_root = File.expand_path(root)
      unless path_descendant?(expanded_root, site_root) && expanded_root != site_root
        fatal("application asset cache escapes the site source")
      end

      return unless File.exist?(expanded_root)

      stat = File.lstat(expanded_root)
      fatal("application asset cache must be a non-symlink directory") unless stat.directory? && !stat.symlink?
    rescue SystemCallError => exception
      fatal("cannot validate application asset cache: #{exception.message}")
    end

    def validate_application_asset_file!(path, cache_root:, label:)
      expanded = File.expand_path(path)
      expanded_cache_root = File.expand_path(cache_root)
      unless path_descendant?(expanded, expanded_cache_root) && expanded != expanded_cache_root
        fatal("#{label} escapes the application asset cache")
      end

      relative = Pathname.new(expanded).relative_path_from(Pathname.new(expanded_cache_root))
      cursor = expanded_cache_root
      parts = relative.each_filename.to_a
      parts.each_with_index do |part, index|
        cursor = File.join(cursor, part)
        stat = File.lstat(cursor)
        fatal("#{label} path contains a symbolic link: #{cursor}") if stat.symlink?
        if index == parts.length - 1
          fatal("#{label} is not a regular file") unless stat.file?
        else
          fatal("#{label} path contains a non-directory: #{cursor}") unless stat.directory?
        end
      end
    rescue ArgumentError
      fatal("#{label} escapes the application asset cache")
    end

    def validate_manifest_entry!(entry, location)
      fatal("asset manifest #{location} must be a mapping") unless entry.is_a?(Hash)
      js = entry["js"]
      fatal("asset manifest #{location}.js is invalid") unless js.is_a?(String)
      validate_manifest_path!(js)
      color_scheme = entry["color_scheme"]
      fatal("asset manifest #{location}.color_scheme is invalid") unless color_scheme.is_a?(String)
      validate_manifest_path!(color_scheme)
      if entry.key?("css")
        fatal("asset manifest #{location}.css is invalid") unless entry["css"].is_a?(String)
        validate_manifest_path!(entry["css"])
      end
      validate_manifest_file_list!(entry, location)
      fatal("asset manifest #{location}.files must contain its js") unless entry.fetch("files").include?(js)
      unless entry.fetch("files").include?(color_scheme)
        fatal("asset manifest #{location}.files must contain its color scheme bootstrap")
      end
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
      pages.each { |page| register_output!(registry, site, page, page.website_route, "website output") }
      static_files.each { |file| register_output!(registry, site, file, file.website_route, "website asset") }
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
          Jekyll.logger.error("Website #{label}:", diagnostic.message)
        else
          Jekyll.logger.warn("Website #{label}:", diagnostic.message)
        end
      end
    end

    def fatal(message)
      raise Jekyll::Errors::FatalException, message
    end
    end

    class Generator < Jekyll::Generator
      safe false
      priority :highest

      def generate(site)
        Adapter.generate(site)
      end
    end
  end
end

Jekyll::Hooks.register :site, :after_init do |site|
  JekyllObsidian::Adapter.prepare_site(site)
end

Jekyll::Hooks.register :site, :post_write do |site|
  JekyllObsidian::Adapter.cleanup_staging(site)
end
