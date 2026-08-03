# frozen_string_literal: true

require "open3"
require "pathname"

module JekyllObsidian
  class WorkspaceLayout
    class Invalid < StandardError; end

    DEFAULT_SOURCE = Object.new.freeze
    BUNDLED_SOURCE_BASENAME = "docs"

    attr_reader :workspace_root, :site_root, :source_root, :source,
      :destination_root, :jekyll_cache_root, :application_cache_root, :application_assets_root

    def self.resolve(site:, source: DEFAULT_SOURCE)
      new(site:, source:).tap(&:validate!)
    end

    def initialize(site:, source:)
      @site_root = canonical_directory(site.source, "Jekyll source")
      @workspace_root = discover_workspace_root(@site_root)
      @source = source.equal?(DEFAULT_SOURCE) ? bundled_source : normalize_source(source)
      @source_root = File.expand_path(@source, @workspace_root)
      @destination_root = File.expand_path(site.dest)
      @jekyll_cache_root = File.expand_path(site.cache_dir)
      @application_cache_root = File.join(@site_root, ".jekyll-obsidian-cache")
      @application_assets_root = File.join(@application_cache_root, "assets")
    end

    def validate!
      validate_site_root!
      validate_source_root!
      validate_destination_root!
      validate_jekyll_cache_root!
      validate_owned_path!(@application_cache_root, "application cache")
      validate_owned_path!(@application_assets_root, "application assets")
      instance_variables.each { |name| instance_variable_get(name).freeze }
      freeze
    end

    private

    def canonical_directory(path, label)
      expanded = File.expand_path(path)
      stat = File.lstat(expanded)
      raise Invalid, "#{label} must be a non-symlink directory" unless stat.directory? && !stat.symlink?

      File.realpath(expanded)
    rescue SystemCallError => exception
      raise Invalid, "cannot resolve #{label}: #{exception.message}"
    end

    def discover_workspace_root(site_root)
      stdout, _stderr, status = Open3.capture3("git", "-C", site_root, "rev-parse", "--show-toplevel")
      candidate = status.success? ? stdout.strip : ""
      candidate = File.dirname(site_root) if candidate.empty?
      canonical_directory(candidate, "workspace root")
    rescue SystemCallError
      canonical_directory(File.dirname(site_root), "workspace root")
    end

    def normalize_source(raw)
      raise Invalid, "website.source must be a repository-relative directory" unless raw.is_a?(String)

      source = raw.unicode_normalize(:nfc).tr("\\", "/")
      path = Pathname.new(source)
      invalid = source.empty? || source == "." || source.include?("\0") || source.match?(/\A[A-Za-z]:\//) ||
        path.absolute? || path.cleanpath.to_s != source ||
        source.split("/").any? { |part| part.empty? || part == "." || part == ".." }
      raise Invalid, "website.source must be a normalized repository-relative directory" if invalid

      source
    rescue ArgumentError => exception
      raise Invalid, "invalid website.source: #{exception.message}"
    end

    def bundled_source
      Pathname.new(File.join(@site_root, BUNDLED_SOURCE_BASENAME))
        .relative_path_from(Pathname.new(@workspace_root))
        .to_s
        .tr(File::SEPARATOR, "/")
    rescue ArgumentError => exception
      raise Invalid, "cannot resolve bundled website.source: #{exception.message}"
    end

    def validate_site_root!
      unless strict_descendant?(@site_root, @workspace_root)
        raise Invalid, "Jekyll source must be a directory inside the workspace root"
      end

      assert_no_symlink_components!(@workspace_root, @site_root, "Jekyll source", missing: false)
    end

    def validate_source_root!
      unless strict_descendant?(@source_root, @workspace_root)
        raise Invalid, "website.source escapes the repository"
      end
      unless File.directory?(@source_root)
        raise Invalid, "website.source does not exist: #{@source}"
      end

      assert_no_symlink_components!(@workspace_root, @source_root, "website.source", missing: false)
      real_source = File.realpath(@source_root)
      unless real_source == @source_root
        raise Invalid, "website.source cannot contain symlink path components"
      end
      bundled_source_root = File.join(@site_root, BUNDLED_SOURCE_BASENAME)
      if paths_overlap?(@source_root, @site_root) && @source_root != bundled_source_root
        raise Invalid, "website.source must not overlap the Jekyll source"
      end
    rescue SystemCallError => exception
      raise Invalid, "invalid website.source: #{exception.message}"
    end

    def validate_owned_path!(path, label)
      unless strict_descendant?(path, @site_root)
        raise Invalid, "#{label} must stay inside the Jekyll source"
      end

      assert_no_symlink_components!(@site_root, path, label, missing: true)
      if File.exist?(path) && !File.directory?(path)
        raise Invalid, "#{label} must be a directory"
      end
    end

    def validate_destination_root!
      unless strict_descendant?(@destination_root, @site_root)
        raise Invalid, "destination must stay inside the Jekyll source"
      end

      public_destination = File.dirname(@destination_root) == @site_root &&
        File.basename(@destination_root).match?(/\A_site(?:-[A-Za-z0-9][A-Za-z0-9._-]*)?\z/)
      internal_destination = File.dirname(@destination_root) == @application_cache_root &&
        File.basename(@destination_root).match?(/\Asite-build\.[A-Za-z0-9]+\z/)
      unless public_destination || internal_destination
        raise Invalid, "destination must be a top-level _site or _site-NAME directory"
      end

      validate_owned_path!(@destination_root, "destination")
    end

    def validate_jekyll_cache_root!
      expected = File.join(@site_root, ".jekyll-cache")
      unless strict_descendant?(@jekyll_cache_root, @site_root)
        raise Invalid, "Jekyll cache must stay inside the Jekyll source"
      end
      unless @jekyll_cache_root == expected
        raise Invalid, "Jekyll cache must use the site-local .jekyll-cache directory"
      end

      validate_owned_path!(@jekyll_cache_root, "Jekyll cache")
    end

    def assert_no_symlink_components!(root, target, label, missing:)
      relative = Pathname.new(target).relative_path_from(Pathname.new(root))
      cursor = root
      relative.each_filename do |part|
        cursor = File.join(cursor, part)
        stat = File.lstat(cursor)
        raise Invalid, "#{label} path contains a symbolic link: #{cursor}" if stat.symlink?
      rescue Errno::ENOENT
        break if missing
        raise Invalid, "#{label} does not exist: #{cursor}"
      end
    rescue ArgumentError
      raise Invalid, "#{label} escapes its allowed root"
    end

    def strict_descendant?(candidate, root)
      candidate.start_with?("#{root}#{File::SEPARATOR}")
    end

    def paths_overlap?(left, right)
      left == right || strict_descendant?(left, right) || strict_descendant?(right, left)
    end
  end
end
