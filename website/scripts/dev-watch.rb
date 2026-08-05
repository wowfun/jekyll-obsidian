#!/usr/bin/env ruby
# frozen_string_literal: true

require "listen"
require "open3"
require "optparse"
require_relative "../lib/jekyll_obsidian/dev_watch"
require_relative "../lib/jekyll_obsidian/workspace_layout"

Options = Struct.new(:host, :port, :baseurl, :theme, keyword_init: true)
WatcherSite = Struct.new(:source, :dest, :cache_dir, keyword_init: true)

SITE_IGNORE_PATTERN = %r{\A(?:\.git|\.bundle|\.jekyll-cache|\.jekyll-obsidian-cache|node_modules|vendor|_site(?:-[^/]+)?)(?:/|\z)}
CONTENT_IGNORE_PATTERN = %r{\A(?:\.obsidian|\.trash)(?:/|\z)}
HOST_CONFIG_RELATIVE_PATH = ".github/jekyll-obsidian.yml"
SITE_WATCH_ENTRIES = %w[
  lib
  _plugins
  _layouts
  _includes
  _data
  src
  _config.yml
  Gemfile
  Gemfile.lock
  package.json
  package-lock.json
  scripts/build-assets.mjs
  scripts/cache-boundary.mjs
  tsconfig.json
].freeze
ASSET_WATCH_ENTRIES = %w[
  src
  package.json
  package-lock.json
  scripts/build-assets.mjs
  scripts/cache-boundary.mjs
  tsconfig.json
].freeze

options = Options.new(host: "127.0.0.1", port: 58_000, baseurl: "", theme: "minimal")
OptionParser.new do |parser|
  parser.banner = "Usage: <site-dir>/bin/dev [--host HOST] [--port PORT] [--baseurl PATH] [--theme minimal|docs]"
  parser.on("--host HOST") { |value| options.host = value }
  parser.on("--port PORT", Integer) { |value| options.port = value }
  parser.on("--baseurl PATH") { |value| options.baseurl = value }
  parser.on("--theme THEME", %w[minimal docs], "Preview theme (default: minimal)") { |value| options.theme = value }
end.parse!

site_dir = File.expand_path("..", __dir__)
destination = "_site"

def host_config_path(site_dir)
  File.join(File.dirname(site_dir), HOST_CONFIG_RELATIVE_PATH)
end

def configuration_paths(site_dir)
  paths = [File.join(site_dir, "_config.yml")]
  host_config = host_config_path(site_dir)
  paths << host_config if File.file?(host_config) && !File.symlink?(host_config)
  paths
end

def configured_source(site_dir)
  JekyllObsidian::DevWatch.configured_source(
    site_dir:,
    configuration_paths: configuration_paths(site_dir)
  )
end

def resolve_layout(site_dir, destination)
  site = WatcherSite.new(
    source: site_dir,
    dest: File.join(site_dir, destination),
    cache_dir: File.join(site_dir, ".jekyll-cache")
  )
  JekyllObsidian::WorkspaceLayout.resolve(site:, source: configured_source(site_dir))
end

def relative_path(root, path)
  absolute = File.expand_path(path)
  prefix = "#{root}#{File::SEPARATOR}"
  return nil unless absolute.start_with?(prefix)

  absolute.delete_prefix(prefix)
end

def under_entry?(path, entry)
  path == entry || path.start_with?("#{entry}/")
end

def run_build(site_dir, options, destination, build_assets:)
  command = [
    File.join(site_dir, "bin/build"),
    "--url", "http://#{options.host}:#{options.port}",
    "--baseurl", options.baseurl,
    "--destination", destination
  ]
  command.concat(["--theme", options.theme])
  command << "--skip-assets" unless build_assets

  success = false
  Open3.popen2e({ "JEKYLL_ENV" => "development" }, *command, chdir: site_dir) do |stdin, output, wait|
    stdin.close
    output.each { |line| $stdout.write(line) }
    success = wait.value.success?
  end
  success
end

def start_site_listener(site_dir, changes)
  Listen.to(site_dir, ignore: SITE_IGNORE_PATTERN) do |modified, added, removed|
    (modified + added + removed).each do |path|
      relative = relative_path(site_dir, path)
      next unless relative && SITE_WATCH_ENTRIES.any? { |entry| under_entry?(relative, entry) }

      changes << [:site, relative]
    end
  end.tap(&:start)
end

def start_content_listener(content_root, changes)
  Listen.to(content_root, ignore: CONTENT_IGNORE_PATTERN) do |modified, added, removed|
    (modified + added + removed).each do |path|
      relative = relative_path(content_root, path)
      changes << [:content, relative] if relative
    end
  end.tap(&:start)
end

def start_host_config_listener(site_dir, changes)
  config_path = host_config_path(site_dir)
  config_directory = File.dirname(config_path)
  return nil unless File.directory?(config_directory) && !File.symlink?(config_directory)

  Listen.to(config_directory) do |modified, added, removed|
    next unless (modified + added + removed).any? { |path| File.expand_path(path) == config_path }

    changes << [:host_config, HOST_CONFIG_RELATIVE_PATH]
  end.tap(&:start)
end

begin
  layout = resolve_layout(site_dir, destination)
rescue JekyllObsidian::WorkspaceLayout::Invalid => exception
  warn exception.message
  exit 1
end

unless run_build(site_dir, options, destination, build_assets: true)
  warn "Initial build failed. The watcher will stay active so you can repair the source."
end

server_command = [
  "bundle", "exec", "jekyll", "serve",
  "--skip-initial-build",
  "--no-watch",
  "--config", configuration_paths(site_dir).join(","),
  "--destination", File.join(site_dir, destination),
  "--baseurl", options.baseurl,
  "--host", options.host,
  "--port", options.port.to_s
]
server_pid = Process.spawn({ "JEKYLL_ENV" => "development" }, *server_command, chdir: site_dir, pgroup: true)

stopping = false
stop = proc do
  next if stopping

  stopping = true
  begin
    Process.kill("TERM", -server_pid)
  rescue Errno::ESRCH
    nil
  end
end

Signal.trap("INT", &stop)
Signal.trap("TERM", &stop)
at_exit { stop.call }

puts "Watching #{layout.source}/ and site sources. Serving http://#{options.host}:#{options.port}#{options.baseurl}/"

changes = Queue.new
site_listener = start_site_listener(site_dir, changes)
content_listener = start_content_listener(layout.source_root, changes)
host_config_listener = start_host_config_listener(site_dir, changes)
exited_server = nil

begin
  until stopping
    changed = changes.pop(timeout: 0.25)

    exited_server = Process.waitpid(server_pid, Process::WNOHANG)
    if exited_server
      warn "Jekyll server exited. Stop the watcher and inspect the server output."
      stopping = true
      next
    end

    next unless changed

    batch = [changed]
    loop do
      pending = changes.pop(timeout: 0.25)
      break unless pending

      batch << pending
    end
    batch << changes.pop(true) until changes.empty?

    build_assets = batch.any? do |kind, path|
      kind == :site && ASSET_WATCH_ENTRIES.any? { |entry| under_entry?(path, entry) }
    end
    layout, content_listener = JekyllObsidian::DevWatch.rebuild_and_refresh(
      batch:,
      build_assets:,
      site_dir:,
      destination:,
      layout:,
      content_listener:,
      changes:,
      build_runner: ->(with_assets) { run_build(site_dir, options, destination, build_assets: with_assets) },
      layout_resolver: method(:resolve_layout),
      listener_starter: method(:start_content_listener)
    )
  end
ensure
  site_listener.stop
  content_listener.stop
  host_config_listener&.stop
end

Process.wait(server_pid) unless exited_server
