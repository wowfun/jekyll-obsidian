#!/usr/bin/env ruby
# frozen_string_literal: true

require "find"
require "json"
require "pathname"
require "set"
require "uri"

require_relative "../lib/jekyll_obsidian/raw_html_manifest"

MAX_BYTES = 1_073_741_824
EXACT_FILES = %w[
  index.html 404.html feed.xml sitemap.xml
  assets/website/catalog.v1.json assets/website/graph.v1.json assets/website/search.v1.json
  robots.txt site.webmanifest favicon.ico .nojekyll
].append(JekyllObsidian::RawHtmlManifest::PATH).freeze
RAW_HTML_MANIFEST = JekyllObsidian::RawHtmlManifest::PATH
ALLOWED_EXTENSIONS = %w[
  .html .css .js .mjs .woff .woff2
  .avif .bmp .gif .jpeg .jpg .png .svg .webp
  .flac .m4a .mp3 .ogg .wav .webm .3gp
  .mkv .mov .mp4 .ogv .pdf .canvas .base
].freeze

def fail_audit(message)
  warn "site audit: #{message}"
  exit 1
end

def generated_markdown_resource?(site_dir, relative)
  return false unless File.extname(relative).casecmp(".md").zero?

  candidates = ["#{relative.delete_suffix('.md')}/index.html"]
  if File.basename(relative).casecmp("index.md").zero?
    directory = File.dirname(relative)
    candidates << (directory == "." ? "index.html" : "#{directory}/index.html")
  end
  candidates.any? { |html| File.file?(File.join(site_dir, html)) }
end

def raw_html_relative_path(value, label, allow_directory: false)
  unless value.is_a?(String) && value.valid_encoding? && value.start_with?("/") &&
      !value.match?(/[?#\\\x00-\x1f\x7f]/) && !value.match?(/%(?:2f|5c)/i)
    fail_audit("unsafe #{label}: #{value.inspect}")
  end

  decoded = URI.decode_uri_component(value)
  segments = decoded.split("/", -1)
  segments.pop if allow_directory && decoded.end_with?("/")
  unless decoded.valid_encoding? && segments.first == "" &&
      segments.drop(1).none? { |segment| segment.empty? || segment == "." || segment == ".." }
    fail_audit("unsafe #{label}: #{value.inspect}")
  end
  decoded.delete_prefix("/")
rescue ArgumentError
  fail_audit("unsafe #{label}: #{value.inspect}")
end

def raw_html_output_files(site_dir)
  manifest_path = File.join(site_dir, RAW_HTML_MANIFEST)
  return Set.new unless File.exist?(manifest_path) || File.symlink?(manifest_path)

  stat = File.lstat(manifest_path)
  fail_audit("raw HTML manifest must be a non-symlink regular file") unless stat.file? && !stat.symlink?
  payload = JekyllObsidian::RawHtmlManifest.parse(File.read(manifest_path, encoding: "UTF-8"))
  documents = payload.fetch("documents")
  files = payload.fetch("files")

  relative_files = files.map { |route| raw_html_relative_path(route, "raw HTML file route") }
  documents.each do |document|
    raw_html_relative_path(document.fetch("route"), "raw HTML document route", allow_directory: true)
    raw_html_relative_path(document.fetch("output"), "raw HTML document output")
  end

  relative_files.each do |relative|
    target = File.expand_path(relative, site_dir)
    inside = target.start_with?("#{site_dir}#{File::SEPARATOR}")
    unless inside && File.exist?(target) && File.lstat(target).file? && !File.lstat(target).symlink?
      fail_audit("raw HTML manifest target is missing or unsafe: #{relative}")
    end
  end
  Set.new(relative_files)
rescue JekyllObsidian::RawHtmlManifest::Invalid => exception
  fail_audit("raw HTML manifest has an unsupported schema: #{exception.message}")
end

site_dir = File.expand_path(ARGV.fetch(0, File.expand_path("../_site", __dir__)))
fail_audit("#{site_dir} is not a directory") unless File.directory?(site_dir)
fail_audit("the site root must not be a symbolic link") if File.lstat(site_dir).symlink?
fail_audit("index.html is missing") unless File.file?(File.join(site_dir, "index.html"))
raw_html_files = raw_html_output_files(site_dir)

root = Pathname.new(site_dir)
total = 0
Find.find(site_dir) do |path|
  next if path == site_dir

  stat = File.lstat(path)
  relative = Pathname.new(path).relative_path_from(root).to_s
  unless relative.valid_encoding? && !relative.match?(/[\x00-\x1f\x7f\\]/) &&
      !relative.start_with?("/") && relative.split("/").none? { |segment| segment.empty? || segment == "." || segment == ".." }
    fail_audit("unsafe output path: #{relative.inspect}")
  end

  fail_audit("symbolic link found: #{relative}") if stat.symlink?
  next if stat.directory?
  fail_audit("non-regular output found: #{relative}") unless stat.file?

  localized_artifact = relative.match?(%r{\Aassets/website/i18n/[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*/(?:catalog|graph|search)\.v1\.json\z}) ||
    relative.match?(%r{\A[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*/feed\.xml\z})
  allowed = EXACT_FILES.include?(relative) || raw_html_files.include?(relative) || localized_artifact || relative.end_with?("/index.html") ||
    generated_markdown_resource?(site_dir, relative) || ALLOWED_EXTENSIONS.include?(File.extname(relative).downcase)
  fail_audit("output is not on the extension allowlist: #{relative}") unless allowed

  total += stat.size
  fail_audit("site is larger than 1 GB (#{total} bytes)") if total > MAX_BYTES
end

puts "site audit: ok (#{(total + 1023) / 1024} KiB)"
