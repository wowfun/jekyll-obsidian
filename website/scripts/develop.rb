#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require_relative "../lib/jekyll_obsidian/runtime"

command = ARGV.shift
options = { destination_name: "site" }
build_options = {}
example = false
skip_assets = false
parser = OptionParser.new do |parser|
  parser.banner = "Usage: website/bin/#{command} [options] (contributor command)"
  parser.on("--example", "Use the bundled documentation fixture") { example = true }
  parser.on("--theme minimal|docs", %w[minimal docs]) { |value| build_options[:theme] = value }
  parser.on("--url ORIGIN") { |value| build_options[:url] = value }
  parser.on("--baseurl PATH") { |value| build_options[:baseurl] = value }
  parser.on("--destination NAME", "Cache output name: site or site-NAME") { |value| options[:destination_name] = value }
  parser.on("--skip-assets", "Use existing frontend assets") { skip_assets = true }
  parser.on("--quiet") { build_options[:quiet] = true }
  parser.on("-h", "--help") { puts parser; exit 0 }
end
begin
  parser.parse!
  raise ArgumentError, "unexpected argument: #{ARGV.first}" unless ARGV.empty?
  raise ArgumentError, "expected build command" unless command == "build"
  website = File.expand_path("..", __dir__)
  root = File.dirname(website)
  unless skip_assets
    abort "frontend build failed" unless system("npm", "run", "build", chdir: website)
  end
  options[:config_path] = File.join(website, "scripts", "example-config.yml") if example
  runtime = JekyllObsidian::Runtime.new(root:, assets_root: File.join(website, ".jekyll-obsidian-cache", "assets"), **options)
  build_options[:environment] = ENV.fetch("JEKYLL_ENV", "production")
  puts runtime.build(**build_options)
rescue OptionParser::ParseError, ArgumentError, JekyllObsidian::Runtime::Error,
    JekyllObsidian::WorkspaceLayout::Invalid, Jekyll::Errors::FatalException, SystemCallError => exception
  warn "Error: #{exception.message}"
  exit 1
end
