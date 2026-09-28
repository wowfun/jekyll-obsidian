# frozen_string_literal: true

require "pathname"

module JekyllObsidian
  class WorkspaceLayout
    class Invalid < StandardError; end

    DEFAULT_SOURCE = Object.new.freeze
    CONTEXT_KEY = "_jekyll_obsidian_runtime"
    CACHE_DIRECTORY = ".jekyll-obsidian-cache"

    attr_reader :workspace_root, :site_root, :source_root, :source,
      :destination_root, :jekyll_cache_root, :application_cache_root, :application_assets_root

    def self.resolve(site:, source: DEFAULT_SOURCE)
      new(site:, source:).tap(&:validate!)
    end

    def self.relative_source(raw)
      raise Invalid, "website.source must be a repository-relative directory" unless raw.is_a?(String)

      source = raw.unicode_normalize(:nfc).tr("\\", "/")
      invalid = source.empty? || source == "." || source.match?(/[[:cntrl:]]/) ||
        source.match?(/\A[A-Za-z]:\//) || Pathname.new(source).absolute? ||
        Pathname.new(source).cleanpath.to_s != source ||
        source.split("/").any? { |part| part.empty? || part == "." || part == ".." }
      raise Invalid, "website.source must be a normalized repository-relative directory" if invalid
      if source == CACHE_DIRECTORY || source.start_with?("#{CACHE_DIRECTORY}/")
        raise Invalid, "website.source must not overlap the application cache"
      end

      source
    rescue ArgumentError => exception
      raise Invalid, "invalid website.source: #{exception.message}"
    end

    def self.assert_path!(root, target, label, missing: false)
      relative = Pathname.new(target).relative_path_from(Pathname.new(root))
      raise Invalid, "#{label} escapes its allowed root" if relative.each_filename.any? { |part| part == ".." }

      cursor = root
      ([root] + relative.each_filename.map { |part| cursor = File.join(cursor, part) }).each do |path|
        stat = File.lstat(path)
        raise Invalid, "#{label} path contains a symbolic link: #{path}" if stat.symlink?
      rescue Errno::ENOENT
        break if missing
        raise Invalid, "#{label} does not exist: #{path}"
      end
    rescue ArgumentError
      raise Invalid, "#{label} escapes its allowed root"
    end

    def initialize(site:, source:)
      context = site.config.fetch(CONTEXT_KEY)
      @workspace_root = File.realpath(context.fetch("workspace_root"))
      @site_root = File.expand_path(site.source)
      @source = self.class.relative_source(source.equal?(DEFAULT_SOURCE) ? "docs" : source)
      @source_root = File.expand_path(@source, @workspace_root)
      @destination_root = File.expand_path(site.dest)
      @jekyll_cache_root = File.expand_path(site.cache_dir)
      @application_cache_root = File.join(@workspace_root, CACHE_DIRECTORY)
      @application_assets_root = File.expand_path(context.fetch("assets_root"))
    rescue KeyError => exception
      raise Invalid, "missing runtime context; use jekyll-obsidian build or dev (#{exception.message})"
    end

    def validate!
      self.class.assert_path!(@workspace_root, @application_cache_root, "application cache", missing: true)
      unless @site_root == File.join(@application_cache_root, "runtime")
        raise Invalid, "Jekyll source must use the isolated runtime directory"
      end
      validate_directory!(@site_root, "Jekyll source", missing: false)
      self.class.assert_path!(@workspace_root, @source_root, "website.source")
      raise Invalid, "website.source must be a directory: #{@source}" unless File.directory?(@source_root)
      unless File.realpath(@source_root) == @source_root
        raise Invalid, "website.source casing must match the repository path exactly"
      end

      unless File.dirname(@destination_root) == @application_cache_root &&
          File.basename(@destination_root).match?(/\Asite(?:-[A-Za-z0-9][A-Za-z0-9._-]*|\-build\.[A-Za-z0-9]+)?\z/)
        raise Invalid, "destination must be a site directory inside the application cache"
      end
      validate_directory!(@destination_root, "destination")
      unless @jekyll_cache_root == File.join(@site_root, ".jekyll-cache")
        raise Invalid, "Jekyll cache must use the runtime-local .jekyll-cache directory"
      end
      validate_directory!(@jekyll_cache_root, "Jekyll cache")
      instance_variables.each { |name| instance_variable_get(name).freeze }
      freeze
    rescue SystemCallError => exception
      raise Invalid, "invalid workspace: #{exception.message}"
    end

    private

    def validate_directory!(path, label, missing: true)
      self.class.assert_path!(@workspace_root, path, label, missing:)
      if File.exist?(path) && !File.directory?(path)
        raise Invalid, "#{label} must be a directory"
      end
    end
  end
end
