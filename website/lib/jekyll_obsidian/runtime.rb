# frozen_string_literal: true

require "date"
require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"
require "jekyll"
require_relative "version"
require_relative "workspace_layout"
require_relative "adapter"

module JekyllObsidian
  class Runtime
    class Error < StandardError; end

    PACKAGE_ROOT = File.realpath(File.expand_path("../..", __dir__))
    CONFIG_PATH = ".github/jekyll-obsidian.yml"
    PUBLIC_KEYS = %w[title description lang url baseurl website].freeze
    SITE_OPTIONS = {
      "safe" => false, "incremental" => false, "disable_disk_cache" => true,
      "strict_front_matter" => true, "permalink" => "pretty", "encoding" => "UTF-8",
      "markdown" => "kramdown", "highlighter" => "none", "plugins" => [], "plugins_dir" => [],
      "liquid" => { "error_mode" => "strict", "strict_filters" => true, "strict_variables" => false }
    }.freeze

    attr_reader :root, :config_path, :cache_root, :destination, :assets_root

    def self.discover_root(start = Dir.pwd)
      Pathname.new(File.expand_path(start)).ascend do |path|
        return path.to_s if File.exist?(path.join(CONFIG_PATH)) || File.symlink?(path.join(CONFIG_PATH))
      end
      raise Error, "Missing #{CONFIG_PATH}. Run jekyll-obsidian init from your repository root."
    end

    def initialize(root:, config_path: nil, assets_root: nil, destination_name: "site")
      @root = File.realpath(root)
      @config_path = config_path || File.join(@root, CONFIG_PATH)
      @assets_root = assets_root || File.join(PACKAGE_ROOT, "assets")
      @cache_root = File.join(@root, WorkspaceLayout::CACHE_DIRECTORY)
      unless destination_name.match?(/\Asite(?:-[A-Za-z0-9][A-Za-z0-9._-]*)?\z/)
        raise Error, "destination name must be site or site-NAME"
      end
      @destination = File.join(@cache_root, destination_name)
    end

    def configuration
      WorkspaceLayout.assert_path!(@root, @config_path, "configuration")
      raise Error, "configuration must be a regular file" unless File.file?(@config_path)

      user = YAML.safe_load_file(@config_path, permitted_classes: [Date, Time], aliases: true)
      raise Error, "#{CONFIG_PATH} must be a mapping" unless user.is_a?(Hash)
      unknown = user.keys - PUBLIC_KEYS
      raise Error, "unsupported site configuration: #{unknown.first}" unless unknown.empty?
      if user.key?("website") && !user["website"].is_a?(Hash)
        raise Error, "website must be a mapping"
      end
      defaults = YAML.safe_load_file(File.join(PACKAGE_ROOT, "_config.yml"), aliases: false)
      Jekyll::Utils.deep_merge_hashes(defaults, user)
    rescue Psych::Exception => exception
      raise Error, "Cannot read #{CONFIG_PATH}: #{exception.message}"
    end

    def source_root(config = configuration)
      source = WorkspaceLayout.relative_source(config.fetch("website").fetch("source"))
      path = File.join(@root, source)
      WorkspaceLayout.assert_path!(@root, path, "website.source")
      raise Error, "website.source must be a directory: #{source}" unless File.directory?(path)
      path
    end

    def build(url: nil, baseurl: nil, theme: nil, environment: "production", quiet: false)
      config = configuration
      config["website"]["theme"] = theme if theme
      config["url"] = url unless url.nil?
      config["baseurl"] = baseurl unless baseurl.nil?
      validate_urls!(config, environment)
      # Validate content before creating or changing any build state.
      source_root(config)
      with_lock do
        runtime_root = prepare_runtime
        staging = Dir.mktmpdir("site-build.", @cache_root)
        previous_environment = ENV["JEKYLL_ENV"]
        begin
          ENV["JEKYLL_ENV"] = environment
          site_config = Jekyll.configuration(config.merge(SITE_OPTIONS).merge(
            "config" => [], "source" => runtime_root, "destination" => staging,
            "cache_dir" => ".jekyll-cache", "quiet" => quiet,
            "layouts_dir" => "_layouts", "includes_dir" => "_includes",
            "data_dir" => "_data", "collections_dir" => "",
            WorkspaceLayout::CONTEXT_KEY => { "workspace_root" => @root, "assets_root" => @assets_root }
          ))
          Jekyll::Site.new(site_config).process
          audit!(staging, config, quiet:) if environment == "production"
          publish!(staging)
        ensure
          previous_environment.nil? ? ENV.delete("JEKYLL_ENV") : ENV["JEKYLL_ENV"] = previous_environment
          FileUtils.remove_entry(staging) if File.exist?(staging)
        end
      end
      @destination
    end

    def clean
      return unless File.exist?(@cache_root) || File.symlink?(@cache_root)

      with_lock do
        Dir.children(@cache_root).each do |entry|
          next if %w[.lock .gitignore].include?(entry)

          FileUtils.remove_entry(File.join(@cache_root, entry))
        end
      end
    end

    private

    def validate_urls!(config, environment)
      origin = config.fetch("url", "").to_s.delete_suffix("/")
      baseurl = config.fetch("baseurl", "").to_s.delete_suffix("/")
      if environment == "production" && origin.empty?
        raise Error, "production builds require --url or url in #{CONFIG_PATH}"
      end
      unless origin.empty? || origin.match?(%r{\Ahttps?://(?:[A-Za-z0-9][A-Za-z0-9.-]*|\[[0-9A-Fa-f:]+\])(?::[0-9]+)?\z})
        raise Error, "url must be an HTTP or HTTPS origin without a path, query, or fragment"
      end
      unless baseurl.empty? || (baseurl.match?(%r{\A(/[A-Za-z0-9._~!$&()*+,;=:@%-]+)+\z}) &&
          baseurl.split("/").none? { |part| %w[. ..].include?(part) })
        raise Error, "baseurl must be empty or a normalized site path such as /project"
      end
      config["url"] = origin
      config["baseurl"] = baseurl
    end

    def with_lock
      WorkspaceLayout.assert_path!(@root, @cache_root, "application cache", missing: true)
      FileUtils.mkdir_p(@cache_root)
      ignore = File.join(@cache_root, ".gitignore")
      WorkspaceLayout.assert_path!(@root, ignore, "cache ignore file", missing: true)
      File.write(ignore, "*\n") unless File.exist?(ignore)
      lock_path = File.join(@cache_root, ".lock")
      WorkspaceLayout.assert_path!(@root, lock_path, "build lock", missing: true)
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        raise Error, "another jekyll-obsidian command is using this workspace" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        yield
      ensure
        lock.flock(File::LOCK_UN)
      end
    end

    def prepare_runtime
      runtime_root = File.join(@cache_root, "runtime")
      WorkspaceLayout.assert_path!(@root, runtime_root, "Jekyll source", missing: true)
      FileUtils.remove_entry(runtime_root) if File.exist?(runtime_root)
      FileUtils.mkdir_p(runtime_root)
      %w[_layouts _includes].each do |directory|
        FileUtils.cp_r(File.join(PACKAGE_ROOT, directory), File.join(runtime_root, directory))
      end
      runtime_root
    end

    def audit!(staging, config, quiet:)
      [
        ["audit-site.rb", staging],
        ["verify-site-urls.rb", staging, config.fetch("url"), config.fetch("baseurl")]
      ].each do |script, *arguments|
        output, status = Open3.capture2e(RbConfig.ruby, File.join(PACKAGE_ROOT, "scripts", script), *arguments)
        raise Error, output.strip unless status.success?
        puts output unless quiet
      end
    end

    def publish!(staging)
      WorkspaceLayout.assert_path!(@root, @destination, "destination", missing: true)
      if File.exist?(@destination) && !File.directory?(@destination)
        raise Error, "destination must be a directory"
      end
      backup = File.join(@cache_root, "site-backup")
      raise Error, "stale site backup exists: #{backup}" if File.exist?(backup) || File.symlink?(backup)

      moved_previous = false
      begin
        if File.exist?(@destination)
          File.rename(@destination, backup)
          moved_previous = true
        end
        File.rename(staging, @destination)
      rescue SystemCallError
        File.rename(backup, @destination) if moved_previous && !File.exist?(@destination)
        raise
      end
      FileUtils.remove_entry(backup) if moved_previous
    end
  end
end
