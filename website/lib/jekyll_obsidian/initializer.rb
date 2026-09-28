# frozen_string_literal: true

require "fileutils"
require "yaml"
require_relative "version"
require_relative "workspace_layout"

module JekyllObsidian
  class Initializer
    def self.run(root:, source: "docs", theme: "minimal")
      root = File.realpath(root)
      source = WorkspaceLayout.relative_source(source)
      raise ArgumentError, "theme must be minimal or docs" unless %w[minimal docs].include?(theme)

      content_root = File.join(root, source)
      WorkspaceLayout.assert_path!(root, content_root, "website.source", missing: true)
      if File.exist?(content_root) && !File.directory?(content_root)
        raise ArgumentError, "website.source must be a directory: #{source}"
      end
      template_root = File.expand_path("../../scripts/templates", __dir__)
      files = {
        ".github/jekyll-obsidian.yml" => YAML.dump({
          "title" => "My Site", "website" => { "source" => source, "theme" => theme }
        }).delete_prefix("---\n"),
        ".github/workflows/pages.yml" => File.read(File.join(template_root, "pages.yml"))
          .gsub("__JEKYLL_OBSIDIAN_VERSION__", VERSION)
      }
      if !File.directory?(content_root) || Dir.empty?(content_root)
        files["#{source}/index.md"] = "---\npublish: true\ntitle: Welcome\n---\n\n# Welcome\n\nYour site is ready for Markdown.\n"
      end

      pending = files.reject do |relative, content|
        path = File.join(root, relative)
        WorkspaceLayout.assert_path!(root, path, relative, missing: true)
        next false unless File.exist?(path)
        unless File.file?(path) && File.binread(path) == content
          raise ArgumentError, "#{relative} already exists. Edit it directly; init does not overwrite files."
        end
        true
      end

      created_files = []
      created_directories = []
      begin
        pending.each do |relative, content|
          path = File.join(root, relative)
          missing = []
          parent = File.dirname(path)
          until File.directory?(parent)
            missing << parent
            parent = File.dirname(parent)
          end
          missing.reverse_each do |directory|
            Dir.mkdir(directory)
            created_directories << directory
          end
          File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o644) { |file| file.write(content) }
          created_files << path
        end
      rescue StandardError
        created_files.reverse_each { |path| File.unlink(path) }
        created_directories.reverse_each { |path| Dir.rmdir(path) if Dir.empty?(path) }
        raise
      end
      pending.keys
    end
  end
end
