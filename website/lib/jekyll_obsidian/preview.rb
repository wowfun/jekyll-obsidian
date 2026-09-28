# frozen_string_literal: true

require "listen"
require "webrick"
require_relative "runtime"

module JekyllObsidian
  class Preview
    CONTENT_IGNORE = %r{\A(?:\.obsidian|\.trash)(?:/|\z)}

    def initialize(runtime, host: "127.0.0.1", port: 58_000, baseurl: "", theme: nil, output: $stdout, warnings: $stderr)
      @runtime = runtime
      @host, @port, @baseurl, @theme = host, port, baseurl.delete_suffix("/"), theme
      @output, @warnings = output, warnings
      @events = Queue.new
      @stopping = false
    end

    def run
      origin = "http://#{@host.include?(":") ? "[#{@host}]" : @host}:#{@port}"
      server = WEBrick::HTTPServer.new(
        BindAddress: @host, Port: @port,
        AccessLog: [], Logger: WEBrick::Log.new(@warnings, WEBrick::Log::WARN),
        MimeTypes: WEBrick::HTTPUtils::DefaultMimeTypes.merge("md" => "text/markdown", "js" => "text/javascript")
      )
      server.mount(@baseurl.empty? ? "/" : @baseurl, WEBrick::HTTPServlet::FileHandler,
        @runtime.destination, FancyIndexing: false)
      previous_signals = %w[INT TERM].to_h { |signal| [signal, Signal.trap(signal) { @stopping = true }] }
      config_listener = Listen.to(File.dirname(@runtime.config_path)) do |modified, added, removed|
        if (modified + added + removed).include?(@runtime.config_path)
          @events << :config
        end
      end.tap(&:start)
      rebuild(origin, initial: true)
      refresh_content_listener
      server_thread = Thread.new { server.start }
      @output.puts "Serving #{origin}#{@baseurl}/"
      @output.flush
      until @stopping
        raise Runtime::Error, "preview server stopped" unless server_thread.alive?
        event = @events.pop(timeout: 0.25)
        unless @content_listener
          refresh_content_listener
          event ||= :content if @content_listener
        end
        next unless event

        # Coalesce editor writes without allowing a steady event stream to starve a build.
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.25
        while (remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)).positive?
          break unless @events.pop(timeout: remaining)
        end
        refresh_content_listener
        rebuild(origin, initial: false)
      end
    ensure
      config_listener&.stop
      @content_listener&.stop
      server&.shutdown
      server_thread&.join
      previous_signals&.each { |signal, handler| Signal.trap(signal, handler) }
    end

    private

    def refresh_content_listener
      source_root = @runtime.source_root
      return if source_root == @watched_root

      next_listener = Listen.to(source_root, ignore: CONTENT_IGNORE) { @events << :content }.tap(&:start)
      @content_listener&.stop
      @content_listener = next_listener
      @watched_root = source_root
      @output.puts "Watching #{Pathname.new(source_root).relative_path_from(Pathname.new(@runtime.root))}/"
    rescue Runtime::Error, WorkspaceLayout::Invalid, SystemCallError
      # Keep the previous valid listener while the configuration is being repaired.
    end

    def rebuild(origin, initial:)
      @output.puts(initial ? "Building site..." : "Source changed. Rebuilding site...")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @runtime.build(url: origin, baseurl: @baseurl, theme: @theme, environment: "development", quiet: true)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      @output.puts format("Built site in %.2fs.", elapsed)
    rescue Runtime::Error, WorkspaceLayout::Invalid, Jekyll::Errors::FatalException, SystemCallError => exception
      @warnings.puts exception.message
      @warnings.puts(initial ? "Initial build failed. Watching for repairs." : "Build failed. Continuing to serve the last successful site.")
    ensure
      @output.flush
      @warnings.flush
    end
  end
end
