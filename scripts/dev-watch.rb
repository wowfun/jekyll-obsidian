#!/usr/bin/env ruby
# frozen_string_literal: true

require "listen"
require "open3"
require "optparse"
require "yaml"

Options = Struct.new(:host, :port, :baseurl, :theme, keyword_init: true)
WATCH_IGNORE_PATTERN = %r{\A(?:\.git|\.bundle|\.jekyll-cache|\.jekyll-obsidian-cache|node_modules|vendor|_site(?:-[^/]+)?)(?:/|\z)}

options = Options.new(host: "127.0.0.1", port: 4000, baseurl: "", theme: nil)
OptionParser.new do |parser|
  parser.banner = "Usage: bin/dev [--host HOST] [--port PORT] [--baseurl PATH] [--theme blog|docs|digital-garden]"
  parser.on("--host HOST") { |value| options.host = value }
  parser.on("--port PORT", Integer) { |value| options.port = value }
  parser.on("--baseurl PATH") { |value| options.baseurl = value }
  parser.on("--theme THEME", %w[blog docs digital-garden]) { |value| options.theme = value }
end.parse!

project_dir = File.expand_path("..", __dir__)
destination = "_site"
base_watch_entries = %w[
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
asset_watch_entries = %w[
  src
  package.json
  package-lock.json
  scripts/build-assets.mjs
  scripts/cache-boundary.mjs
  tsconfig.json
].freeze

def configured_source(project_dir)
  config_path = File.join(project_dir, "_config.yml")
  config = YAML.safe_load_file(config_path, permitted_classes: [], aliases: false) || {}
  obsidian = config["obsidian"]
  source = obsidian.is_a?(Hash) ? obsidian["source"] : nil
  source.is_a?(String) && !source.empty? ? source : "vault"
rescue Psych::Exception, SystemCallError
  "vault"
end

def relative_path(project_dir, path)
  absolute = File.expand_path(path)
  prefix = "#{project_dir}/"
  return nil unless absolute.start_with?(prefix)

  absolute.delete_prefix(prefix)
end

def under_entry?(path, entry)
  path == entry || path.start_with?("#{entry}/")
end

def run_build(project_dir, options, destination, build_assets:)
  command = [
    File.join(project_dir, "bin/build"),
    "--url", "http://#{options.host}:#{options.port}",
    "--baseurl", options.baseurl,
    "--destination", destination
  ]
  command.concat(["--theme", options.theme]) if options.theme
  command << "--skip-assets" unless build_assets

  success = false
  Open3.popen2e({ "JEKYLL_ENV" => "development" }, *command, chdir: project_dir) do |stdin, output, wait|
    stdin.close
    output.each { |line| $stdout.write(line) }
    success = wait.value.success?
  end
  success
end

unless run_build(project_dir, options, destination, build_assets: true)
  warn "Initial build failed. The watcher will stay active so you can repair the source."
end

server_command = [
  "bundle", "exec", "jekyll", "serve",
  "--skip-initial-build",
  "--no-watch",
  "--destination", File.join(project_dir, destination),
  "--baseurl", options.baseurl,
  "--host", options.host,
  "--port", options.port.to_s
]
server_pid = Process.spawn({ "JEKYLL_ENV" => "development" }, *server_command, chdir: project_dir, pgroup: true)

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

puts "Watching vault and site sources. Serving http://#{options.host}:#{options.port}#{options.baseurl}/"

changes = Queue.new
listener = Listen.to(
  project_dir,
  ignore: WATCH_IGNORE_PATTERN
) do |modified, added, removed|
  watched_entries = (base_watch_entries + [configured_source(project_dir)]).uniq
  (modified + added + removed).each do |path|
    relative = relative_path(project_dir, path)
    changes << relative if relative && watched_entries.any? { |entry| under_entry?(relative, entry) }
  end
end
listener.start

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
    until changes.empty?
      batch << changes.pop(true)
    end

    build_assets = batch.any? do |path|
      asset_watch_entries.any? { |entry| under_entry?(path, entry) }
    end
    puts "Source changed. Rebuilding#{build_assets ? " assets and site" : " site"}..."
    run_build(project_dir, options, destination, build_assets: build_assets)
  end
ensure
  listener.stop
end

Process.wait(server_pid) unless exited_server
