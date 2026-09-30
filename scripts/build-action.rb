# frozen_string_literal: true

require "bundler"
require "fileutils"
require "rbconfig"
require_relative "../website/lib/jekyll_obsidian/version"

module JekyllObsidian
  # The Action owns the builder version; the host can lock its dependency graph.
  class ActionBuild
    class Failure < StandardError
      attr_reader :status

      def initialize(message, status = 1)
        @status = status
        super(message)
      end
    end

    def initialize(root: Dir.pwd, environment: ENV.to_h, runner: nil)
      @root = File.expand_path(root)
      @environment = environment.dup
      @runner = runner || method(:execute)
    end

    def run
      gemfile = File.join(@root, "Gemfile")
      lockfile = File.join(@root, "Gemfile.lock")
      present = [gemfile, lockfile].map { |path| File.exist?(path) }
      if present.any? && !present.all?
        raise Failure, "Commit both Gemfile and Gemfile.lock, or remove both to use the standalone builder."
      end

      command = if present.all?
        prepare_bundle(gemfile, lockfile)
      else
        @environment["BUNDLE_GEMFILE"] = nil
        @environment["BUNDLE_FROZEN"] = nil
        run_command("gem", "install", GEM_NAME, "--version", VERSION, "--no-document")
        ["jekyll-obsidian", "_#{VERSION}_"]
      end

      arguments = ["build", "--baseurl", @environment.fetch("SITE_BASEURL", "")]
      origin = @environment.fetch("SITE_ORIGIN", "")
      arguments += ["--url", origin] unless origin.empty?
      run_command(*command, *arguments)
      verify_bundle_files
      File.open(@environment.fetch("GITHUB_OUTPUT"), "a") do |file|
        file.puts "site-path=#{File.join(@root, '.jekyll-obsidian-cache', 'site')}"
      end
    end

    private

    def prepare_bundle(gemfile, lockfile)
      unless [gemfile, lockfile].all? { |path| File.file?(path) }
        raise Failure, "Gemfile and Gemfile.lock must be files."
      end
      @original_files = [gemfile, lockfile].to_h { |path| [path, File.binread(path)] }
      lock = Bundler::LockfileParser.new(File.read(lockfile))
      builders = lock.specs.select { |spec| spec.name == GEM_NAME }
      if builders.empty?
        raise Failure, "Gemfile.lock must include #{GEM_NAME} #{VERSION}."
      end
      unless builders.all? { |spec| spec.version.to_s == VERSION }
        raise Failure, "Action expects #{GEM_NAME} #{VERSION}; Gemfile.lock contains #{builders.map(&:version).uniq.join(', ')}. Upgrade the Action and bundle together."
      end
      bundler_version = lock.bundler_version&.to_s
      unless bundler_version
        raise Failure, "Gemfile.lock must include BUNDLED WITH. Regenerate it with Bundler and commit it."
      end
      @environment["BUNDLE_GEMFILE"] = gemfile
      @environment["BUNDLE_FROZEN"] = "true"
      @environment["BUNDLER_VERSION"] = bundler_version
      if Gem::Specification.find_all_by_name("bundler", bundler_version).empty?
        run_command("gem", "install", "bundler", "--version", bundler_version, "--no-document")
      end
      bundle = ["bundle", "_#{bundler_version}_"]
      run_command(*bundle, "install")
      verify_bundle_files
      check_version = "abort 'Installed builder does not match Action #{VERSION}' unless JekyllObsidian::VERSION == #{VERSION.inspect}"
      run_command(*bundle, "exec", RbConfig.ruby, "-rjekyll_obsidian/version", "-e", check_version)
      [*bundle, "exec", "jekyll-obsidian"]
    rescue Bundler::LockfileError => error
      raise Failure, "Invalid Gemfile.lock: #{error.message}"
    end

    def verify_bundle_files
      @original_files&.each do |path, bytes|
        unless File.file?(path) && File.binread(path) == bytes
          raise Failure, "The build changed #{File.basename(path)} despite frozen mode. Commit a consistent bundle before building."
        end
      end
    end

    def run_command(*arguments)
      @runner.call(@environment, arguments, @root)
    end

    def execute(environment, arguments, root)
      return if system(environment, *arguments, chdir: root)

      raise Failure.new("Command failed: #{arguments.first}", $?&.exitstatus || 1)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    JekyllObsidian::ActionBuild.new.run
  rescue JekyllObsidian::ActionBuild::Failure, KeyError => error
    warn error.message
    exit(error.respond_to?(:status) ? error.status : 1)
  end
end
