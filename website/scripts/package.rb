#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "rubygems/package"
require_relative "../lib/jekyll_obsidian/version"

website = File.expand_path("..", __dir__)
root = File.dirname(website)
unless ARGV.empty? || ARGV == ["--skip-assets"]
  abort "Usage: ruby website/scripts/package.rb [--skip-assets]"
end
unless ARGV == ["--skip-assets"]
  abort "frontend build failed" unless system("npm", "run", "build", chdir: website)
end
source = File.join(website, ".jekyll-obsidian-cache", "assets")
manifest_path = File.join(source, "manifest.json")
abort "Missing frontend manifest. Run npm run build in website/." unless File.file?(manifest_path)
manifest = JSON.parse(File.read(manifest_path))
abort "Unsupported frontend manifest" unless manifest["schema_version"] == 1 && manifest["files"].is_a?(Array)
manifest.fetch("files").each do |relative|
  unless relative.is_a?(String) && !relative.start_with?("/") && !relative.include?("\\") &&
      relative.split("/").none? { |part| ["", ".", ".."].include?(part) }
    abort "Unsafe frontend asset: #{relative.inspect}"
  end
  cursor = source
  relative.split("/").each do |part|
    cursor = File.join(cursor, part)
    abort "Asset must not be a symlink: #{relative}" if File.symlink?(cursor)
  end
  abort "Missing frontend asset: #{relative}" unless File.file?(cursor)
end
assets = File.join(website, "assets")
abort "Asset directories must not be symlinks" if File.symlink?(source) || File.symlink?(assets)
FileUtils.rm_rf(assets)
FileUtils.mkdir_p(assets)
(manifest.fetch("files") + ["manifest.json"]).each do |relative|
  target = File.join(assets, relative)
  FileUtils.mkdir_p(File.dirname(target))
  FileUtils.copy_file(File.join(source, relative), target)
end
output = File.join(root, "pkg", "#{JekyllObsidian::GEM_NAME}-#{JekyllObsidian::VERSION}.gem")
FileUtils.mkdir_p(File.dirname(output))
Dir.chdir(root) do
  spec = Gem::Specification.load("jekyll-obsidian-site.gemspec")
  abort "Cannot load gem specification" unless spec
  abort "Gem does not include its frontend manifest" unless spec.files.include?("website/assets/manifest.json")
  Gem::Package.build(spec, false, false, output)
end
puts output
