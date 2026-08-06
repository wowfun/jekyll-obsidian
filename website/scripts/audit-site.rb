#!/usr/bin/env ruby
# frozen_string_literal: true

require "find"
require "pathname"

MAX_BYTES = 1_073_741_824
EXACT_FILES = %w[
  index.html 404.html feed.xml sitemap.xml
  assets/website/catalog.v1.json assets/website/graph.v1.json assets/website/search.v1.json
  robots.txt site.webmanifest favicon.ico .nojekyll
].freeze
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

site_dir = File.expand_path(ARGV.fetch(0, File.expand_path("../_site", __dir__)))
fail_audit("#{site_dir} is not a directory") unless File.directory?(site_dir)
fail_audit("the site root must not be a symbolic link") if File.lstat(site_dir).symlink?
fail_audit("index.html is missing") unless File.file?(File.join(site_dir, "index.html"))

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
  allowed = EXACT_FILES.include?(relative) || localized_artifact || relative.end_with?("/index.html") ||
    generated_markdown_resource?(site_dir, relative) || ALLOWED_EXTENSIONS.include?(File.extname(relative).downcase)
  fail_audit("output is not on the extension allowlist: #{relative}") unless allowed

  total += stat.size
  fail_audit("site is larger than 1 GB (#{total} bytes)") if total > MAX_BYTES
end

puts "site audit: ok (#{(total + 1023) / 1024} KiB)"
