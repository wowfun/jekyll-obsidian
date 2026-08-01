#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "find"
require "open3"
require "optparse"
require "yaml"

Options = Struct.new(:host, :port, :baseurl, :theme, keyword_init: true)

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
  assets
  _config.yml
  Gemfile
  Gemfile.lock
  package.json
  package-lock.json
  scripts/build-assets.mjs
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

def watch_entries(project_dir, base_entries)
  (base_entries + [configured_source(project_dir)]).uniq
end

def snapshot(project_dir, entries)
  digest = Digest::SHA256.new

  entries.sort.each do |entry|
    path = File.join(project_dir, entry)
    unless File.exist?(path) || File.symlink?(path)
      digest << "missing\0#{entry}\0"
      next
    end

    paths = File.directory?(path) && !File.symlink?(path) ? Find.find(path).to_a.sort : [path]
    paths.each do |candidate|
      stat = File.lstat(candidate)
      relative = candidate.delete_prefix("#{project_dir}/")
      digest << relative << "\0"
      digest << stat.mode.to_s << "\0"
      digest << stat.size.to_s << "\0"
      digest << stat.mtime.to_r.to_s << "\0"
    end
  end

  digest.hexdigest
end

def run_build(project_dir, options, destination)
  command = [
    File.join(project_dir, "bin/build"),
    "--url", "http://#{options.host}:#{options.port}",
    "--baseurl", options.baseurl,
    "--destination", destination
  ]
  command.concat(["--theme", options.theme]) if options.theme

  success = false
  Open3.popen2e({ "JEKYLL_ENV" => "development" }, *command, chdir: project_dir) do |stdin, output, wait|
    stdin.close
    output.each { |line| $stdout.write(line) }
    success = wait.value.success?
  end
  success
end

unless run_build(project_dir, options, destination)
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

known_snapshot = snapshot(project_dir, watch_entries(project_dir, base_watch_entries))
pending_since = nil
debounce_seconds = 0.25
poll_seconds = 0.20

until stopping
  sleep poll_seconds

  exited_server = Process.waitpid(server_pid, Process::WNOHANG)
  if exited_server
    warn "Jekyll server exited. Stop the watcher and inspect the server output."
    stopping = true
    next
  end

  current_snapshot = snapshot(project_dir, watch_entries(project_dir, base_watch_entries))
  if current_snapshot != known_snapshot
    known_snapshot = current_snapshot
    pending_since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    next
  end

  next unless pending_since
  next if Process.clock_gettime(Process::CLOCK_MONOTONIC) - pending_since < debounce_seconds

  pending_since = nil
  puts "Source changed. Rebuilding..."
  run_build(project_dir, options, destination)

  after_build = snapshot(project_dir, watch_entries(project_dir, base_watch_entries))
  if after_build != known_snapshot
    known_snapshot = after_build
    pending_since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

Process.wait(server_pid) unless exited_server
