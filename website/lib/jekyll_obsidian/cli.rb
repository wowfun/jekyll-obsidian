# frozen_string_literal: true

require "optparse"
require_relative "runtime"
require_relative "initializer"

module JekyllObsidian
  class CLI
    def self.run(arguments = ARGV)
      new.run(arguments.dup)
    end

    def run(arguments)
      command = arguments.shift || "--help"
      if %w[--version -v].include?(command)
        puts "jekyll-obsidian #{VERSION} (#{GEM_NAME})"
        return 0
      end
      if %w[--help -h help].include?(command)
        puts "Usage: jekyll-obsidian <init|build|dev|clean> [options]"
        puts "Configuration: .github/jekyll-obsidian.yml"
        puts "Run jekyll-obsidian COMMAND --help for command options."
        return 0
      end
      raise ArgumentError, "unknown command: #{command}" unless %w[init build dev clean].include?(command)

      options = {}
      parser = OptionParser.new do |parser|
        parser.banner = "Usage: jekyll-obsidian #{command} [options]"
        if command == "init"
          parser.on("--source PATH", "Content directory relative to the repository (default: docs)") { |value| options[:source] = value }
        end
        if %w[init build dev].include?(command)
          parser.on("--theme minimal|docs", %w[minimal docs], "Site theme (default: configuration, or minimal)") { |value| options[:theme] = value }
        end
        if %w[build dev].include?(command)
          parser.on("--baseurl PATH", "Site path, such as /project") { |value| options[:baseurl] = value }
        end
        if command == "build"
          parser.on("--url ORIGIN", "Production origin, such as https://example.com") { |value| options[:url] = value }
        end
        if command == "dev"
          parser.on("--host HOST", "Preview host (default: 127.0.0.1)") { |value| options[:host] = value }
          parser.on("--port PORT", Integer, "Preview port (default: 58000)") do |value|
            raise ArgumentError, "port must be between 1 and 65535" unless (1..65_535).cover?(value)
            options[:port] = value
          end
          parser.separator "Watching is always enabled. Builds are complete and atomic."
          parser.separator "Jekyll --watch and --incremental are not supported."
        end
        parser.on("-h", "--help", "Show this help") { puts parser; return 0 }
      end
      parser.parse!(arguments)
      raise ArgumentError, "unexpected argument: #{arguments.first}" unless arguments.empty?

      if command == "init"
        created = Initializer.run(root: Dir.pwd, **options)
        puts(created.empty? ? "Site files already exist." : "Created #{created.join(", ")}")
        puts "Edit .github/jekyll-obsidian.yml, then push to GitHub or run jekyll-obsidian dev."
        puts "For GitHub Pages, select Settings > Pages > Source > GitHub Actions."
        return 0
      end

      runtime = Runtime.new(root: Runtime.discover_root)
      case command
      when "build"
        puts "Built #{runtime.build(**options)}"
      when "dev"
        require_relative "preview"
        Preview.new(runtime, **options).run
      when "clean"
        runtime.clean
        puts "Build output is clean."
      end
      0
    rescue OptionParser::ParseError, ArgumentError, Runtime::Error, WorkspaceLayout::Invalid,
        Jekyll::Errors::FatalException, SystemCallError => exception
      warn "Error: #{exception.message}"
      1
    rescue Interrupt
      130
    end
  end
end
