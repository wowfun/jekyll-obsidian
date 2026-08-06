# frozen_string_literal: true

module JekyllObsidian
  # Owns the publication and content-classification rules for authored notes.
  # Callers resolve configuration once, then use the same policy while selecting
  # default-language notes, applying locale overlays, and classifying output.
  class ContentPolicy
    ROOT_DIRECTORY = "."
    DEFAULT_SETTINGS = DeepFreeze.call(
      "publish_by_default" => [],
      "default_type" => "page",
      "directories" => { "post" => ["blog"], "doc" => ["docs"] }
    )
    Resolution = ImmutableRecord.define(:policy, :diagnostics)

    class << self
      def resolve(raw)
        diagnostics = []
        settings = normalize(raw, diagnostics)
        Resolution.new(policy: new(settings), diagnostics: diagnostics)
      end

      private

      def normalize(raw, diagnostics)
        unless raw.nil? || raw.is_a?(Hash)
          diagnostics << diagnostic("invalid_content_config", "content must be a mapping")
          return DEFAULT_SETTINGS
        end
        raw ||= {}
        unknown = raw.keys.map(&:to_s) - %w[publish_by_default default_type directories]
        unknown.sort.each do |key|
          diagnostics << diagnostic("invalid_content_config", "unknown content setting #{key.inspect}")
        end

        default_type = fetch(raw, "default_type") || DEFAULT_SETTINGS.fetch("default_type")
        unless FrontMatter::CONTENT_TYPES.include?(default_type)
          diagnostics << diagnostic(
            "invalid_content_config",
            "content.default_type must be one of: #{FrontMatter::CONTENT_TYPES.join(', ')}"
          )
          default_type = DEFAULT_SETTINGS.fetch("default_type")
        end

        publish_by_default = normalize_publish_directories(raw, diagnostics)
        directories = normalize_content_directories(raw, diagnostics)
        directories.fetch("post").product(directories.fetch("doc")).each do |post_directory, doc_directory|
          next unless directory_overlaps?(post_directory, doc_directory)

          diagnostics << diagnostic(
            "overlapping_content_directories",
            "post and doc directories overlap: #{post_directory.inspect} and #{doc_directory.inspect}"
          )
        end

        DeepFreeze.call(
          "publish_by_default" => publish_by_default,
          "default_type" => default_type,
          "directories" => directories
        )
      end

      def normalize_publish_directories(raw, diagnostics)
        values = if raw.key?("publish_by_default") || raw.key?(:publish_by_default)
          fetch(raw, "publish_by_default")
        else
          DEFAULT_SETTINGS.fetch("publish_by_default")
        end
        unless values.is_a?(Array)
          diagnostics << diagnostic(
            "invalid_publish_by_default",
            "content.publish_by_default must be an array"
          )
          values = []
        end
        values.filter_map do |value|
          normalize_directory(value, "content.publish_by_default", diagnostics, allow_root: true)
        end.uniq.sort
      end

      def normalize_content_directories(raw, diagnostics)
        directories = if raw.key?("directories") || raw.key?(:directories)
          fetch(raw, "directories")
        else
          DEFAULT_SETTINGS.fetch("directories")
        end
        unless directories.is_a?(Hash)
          diagnostics << diagnostic("invalid_content_directories", "content.directories must be a mapping")
          directories = {}
        end
        unknown = directories.keys.map(&:to_s) - %w[post doc]
        unknown.sort.each do |key|
          diagnostics << diagnostic(
            "invalid_content_directories",
            "unknown content directory type #{key.inspect}"
          )
        end

        %w[post doc].to_h do |type|
          values = fetch(directories, type) || []
          unless values.is_a?(Array)
            diagnostics << diagnostic(
              "invalid_content_directories",
              "content.directories.#{type} must be an array"
            )
            values = []
          end
          normalized = values.filter_map do |value|
            normalize_directory(value, "content.directories.#{type}", diagnostics, allow_root: false)
          end.uniq.sort
          [type, normalized]
        end
      end

      def normalize_directory(value, setting, diagnostics, allow_root:)
        unless FrontMatter.valid_output_text?(value)
          diagnostics << diagnostic("invalid_content_directory", "#{setting} entries must be strings")
          return nil
        end
        return ROOT_DIRECTORY if allow_root && value == ROOT_DIRECTORY

        if value.empty? || value.start_with?("/", "\\") || value.include?("\\") || value != value.unicode_normalize(:nfc)
          diagnostics << diagnostic(
            "invalid_content_directory",
            "#{setting} entries must be normalized vault-relative POSIX directories"
          )
          return nil
        end
        segments = value.split("/", -1)
        if segments.any? { |segment| segment.empty? || segment == "." || segment == ".." }
          diagnostics << diagnostic(
            "invalid_content_directory",
            "#{setting} entries must not contain empty or traversal segments"
          )
          return nil
        end
        value
      rescue EncodingError
        diagnostics << diagnostic("invalid_content_directory", "#{setting} entries must contain valid Unicode")
        nil
      end

      def directory_overlaps?(first, second)
        left = first.downcase(:fold)
        right = second.downcase(:fold)
        left == right || left.start_with?("#{right}/") || right.start_with?("#{left}/")
      end

      def fetch(hash, key)
        hash.key?(key) ? hash[key] : hash[key.to_sym]
      end

      def diagnostic(code, message)
        Diagnostic.new(severity: :error, code: code, message: message, path: nil, span: nil)
      end
    end

    private_class_method :new

    attr_reader :settings

    def initialize(settings)
      @settings = settings
      @publish_by_default = settings.fetch("publish_by_default")
      @directories = settings.fetch("directories")
      @default_type = settings.fetch("default_type")
      freeze
    end

    def publish?(path, properties)
      return false if properties["publish"] == false
      return true if properties["publish"] == true

      @publish_by_default.any? { |directory| inside_directory?(path, directory) }
    end

    def classify(path, properties)
      return "page" if path == "index.md"
      return properties["content_type"] if properties["content_type"]

      directory = File.dirname(path)
      @directories.each do |type, configured|
        return type if configured.any? { |prefix| directory == prefix || directory.start_with?("#{prefix}/") }
      end
      @default_type
    end

    private

    def inside_directory?(path, directory)
      directory == ROOT_DIRECTORY || path.start_with?("#{directory}/")
    end
  end
end
