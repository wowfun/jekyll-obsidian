# frozen_string_literal: true

require "fileutils"
require "net/http"
require "open3"
require "socket"
require "timeout"
require "tmpdir"
require "test_helper"
require "jekyll_obsidian/initializer"

class CliPreviewTest < Minitest::Test
  EXECUTABLE = File.expand_path("../../exe/jekyll-obsidian", __dir__)

  def test_help_and_invalid_options_do_not_start_a_server_or_require_host_configuration
    Dir.mktmpdir("jekyll-obsidian-cli") do |root|
      %w[init build dev clean].each do |command|
        stdout, stderr, status = Open3.capture3(RbConfig.ruby, EXECUTABLE, command, "--help", chdir: root)
        assert status.success?, stderr
        assert_includes stdout, "Usage: jekyll-obsidian #{command}"
      end
      ["--watch", "--incremental", "--unknown"].each do |option|
        _stdout, stderr, status = Open3.capture3(RbConfig.ruby, EXECUTABLE, "dev", option, chdir: root)
        refute status.success?
        assert_includes stderr, "invalid option"
        refute_includes stderr, ".rb:"
      end
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, EXECUTABLE, "build", chdir: root)
      refute status.success?
      assert_includes stderr, "jekyll-obsidian init"
      assert_empty Dir.children(root)
    end
  end

  def test_preview_rebuilds_content_switches_source_and_keeps_last_successful_output
    Dir.mktmpdir("jekyll-obsidian-preview") do |root|
      JekyllObsidian::Initializer.run(root:)
      config_path = File.join(root, ".github", "jekyll-obsidian.yml")
      probe = TCPServer.new("127.0.0.1", 0)
      port = probe.addr[1]
      probe.close
      log_path = File.join(root, "preview.log")
      log = File.open(log_path, "w")
      pid = Process.spawn(RbConfig.ruby, EXECUTABLE, "dev", "--port", port.to_s, "--baseurl", "/preview",
        chdir: root, out: log, err: log)
      uri = URI("http://127.0.0.1:#{port}/preview/")
      wait_for(log_path) { http_body(uri)&.include?("Welcome") }
      note = File.join(root, "docs", "index.md")
      File.write(note, "---\npublish: true\ntitle: Changed\n---\n# First edit\n")
      wait_for(log_path) { http_body(uri)&.include?("First edit") }

      FileUtils.mkdir_p(File.join(root, "website", "docs"))
      File.write(File.join(root, "website", "docs", "index.md"), "---\npublish: true\n---\n# New content root\n")
      config = YAML.safe_load_file(config_path)
      config["website"]["source"] = "website/docs"
      config["website"]["theme"] = "docs"
      File.write(config_path, YAML.dump(config))
      wait_for(log_path) { http_body(uri)&.include?("New content root") }
      assert_includes http_body(uri), 'class="theme-docs"'

      File.write(config_path, "website: [invalid\n")
      wait_for(log_path) { File.read(log_path).include?("Continuing to serve the last successful site") }
      assert_includes http_body(uri), "New content root"
      File.write(config_path, YAML.dump(config))
      File.write(File.join(root, "website", "docs", "index.md"), "---\npublish: true\n---\n# Recovered content\n")
      wait_for(log_path) { http_body(uri)&.include?("Recovered content") }
    ensure
      if pid
        Process.kill("INT", pid) rescue Errno::ESRCH
        begin
          Timeout.timeout(5) { Process.wait(pid) }
        rescue Timeout::Error
          Process.kill("KILL", pid) rescue Errno::ESRCH
          Process.wait(pid) rescue Errno::ECHILD
        end
      end
      log&.close
    end
  end

  private

  def http_body(uri)
    response = Net::HTTP.start(uri.hostname, uri.port, nil, open_timeout: 0.3, read_timeout: 0.3) { |http| http.get(uri.request_uri) }
    response.body if response.is_a?(Net::HTTPSuccess)
  rescue SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout
    nil
  end

  def wait_for(log_path)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 12
    until yield
      flunk "Preview did not reach the expected state:\n#{File.read(log_path)}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.05
    end
  end
end
