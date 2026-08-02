#!/usr/bin/env ruby
# frozen_string_literal: true

require "find"
require "pathname"

MAX_BYTES = 1_073_741_824
EXACT_FILES = %w[
  index.html 404.html feed.xml sitemap.xml
  assets/obsidian/catalog.v1.json assets/obsidian/graph.v1.json assets/obsidian/search.v1.json
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

  allowed = EXACT_FILES.include?(relative) || relative.end_with?("/index.html") || ALLOWED_EXTENSIONS.include?(File.extname(relative).downcase)
  fail_audit("output is not on the extension allowlist: #{relative}") unless allowed

  total += stat.size
  fail_audit("site is larger than 1 GB (#{total} bytes)") if total > MAX_BYTES
end

puts "site audit: ok (#{(total + 1023) / 1024} KiB)"
