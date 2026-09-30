# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../../scripts/build-action"

class ActionBuildTest < Minitest::Test
  def setup
    @host = Dir.mktmpdir("host with spaces ")
    @commands = []
    @output = File.join(@host, "action-output")
    @environment = {"GITHUB_OUTPUT" => @output, "SITE_ORIGIN" => "https://example.test", "SITE_BASEURL" => "/book"}
    @runner = ->(environment, arguments, root) { @commands << [environment.dup, arguments, root] }
  end

  def teardown
    FileUtils.remove_entry(@host)
  end

  def test_standalone_installs_exact_version_and_preserves_arguments_and_output
    @environment["BUNDLE_GEMFILE"] = "/another/project/Gemfile"
    build
    assert_equal ["gem", "install", JekyllObsidian::GEM_NAME, "--version", JekyllObsidian::VERSION, "--no-document"], @commands.first[1]
    assert_nil @commands.first[0]["BUNDLE_GEMFILE"]
    assert_equal ["jekyll-obsidian", "_#{JekyllObsidian::VERSION}_", "build", "--baseurl", "/book", "--url", "https://example.test"], @commands.last[1]
    assert_output_path
  end

  def test_bundle_uses_host_lock_and_frozen_environment_without_rewriting_files
    write_bundle
    before = %w[Gemfile Gemfile.lock].to_h { |name| [name, File.binread(File.join(@host, name))] }
    @environment["SITE_BASEURL"] = ""
    @environment["SITE_ORIGIN"] = ""
    build
    assert_equal ["bundle", "_#{Bundler::VERSION}_", "install"], @commands.first[1]
    assert_equal ["bundle", "_#{Bundler::VERSION}_", "exec", "jekyll-obsidian", "build", "--baseurl", ""], @commands.last[1]
    @commands.each do |environment, _arguments, root|
      assert_equal File.join(@host, "Gemfile"), environment["BUNDLE_GEMFILE"]
      assert_equal "true", environment["BUNDLE_FROZEN"]
      assert_equal @host, root
    end
    before.each { |name, bytes| assert_equal bytes, File.binread(File.join(@host, name)) }
    assert_output_path
  end

  def test_partial_bundle_fails_before_installation
    %w[Gemfile Gemfile.lock].each do |name|
      path = File.join(@host, name)
      File.write(path, "")
      assert_match(/both Gemfile/, assert_raises(JekyllObsidian::ActionBuild::Failure) { build }.message)
      File.delete(path)
    end
    assert_empty @commands
  end

  def test_missing_or_mismatched_builder_does_not_fall_back
    write_bundle(name: "another-gem")
    assert_match(/must include/, assert_raises(JekyllObsidian::ActionBuild::Failure) { build }.message)
    write_bundle(version: "0.0.1")
    assert_match(/contains 0.0.1/, assert_raises(JekyllObsidian::ActionBuild::Failure) { build }.message)
    assert_empty @commands
  end

  def test_frozen_install_failure_preserves_exit_status_and_never_runs_build
    write_bundle
    @runner = lambda do |_environment, arguments, _root|
      @commands << arguments
      raise JekyllObsidian::ActionBuild::Failure.new("frozen bundle failed", 17)
    end
    error = assert_raises(JekyllObsidian::ActionBuild::Failure) { build }
    assert_equal 17, error.status
    assert_equal 1, @commands.length
    refute File.exist?(@output)
  end

  def test_audit_failure_does_not_publish_an_output_path
    @runner = lambda do |_environment, arguments, _root|
      raise JekyllObsidian::ActionBuild::Failure.new("URL audit failed", 23) if arguments.include?("build")
    end
    assert_equal 23, assert_raises(JekyllObsidian::ActionBuild::Failure) { build }.status
    refute File.exist?(@output)
  end

  def test_detects_unexpected_lockfile_mutation
    write_bundle
    @runner = ->(_environment, _arguments, _root) { File.write(File.join(@host, "Gemfile.lock"), "changed") }
    assert_match(/changed Gemfile.lock/, assert_raises(JekyllObsidian::ActionBuild::Failure) { build }.message)
    refute File.exist?(@output)
  end

  private

  def build
    JekyllObsidian::ActionBuild.new(root: @host, environment: @environment, runner: @runner).run
  end

  def assert_output_path
    assert_equal "site-path=#{@host}/.jekyll-obsidian-cache/site\n", File.read(@output)
  end

  def write_bundle(name: JekyllObsidian::GEM_NAME, version: JekyllObsidian::VERSION)
    File.write(File.join(@host, "Gemfile"), "source 'https://rubygems.org'\ngem '#{name}', '#{version}'\n")
    File.write(File.join(@host, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          #{name} (#{version})

      PLATFORMS
        ruby

      DEPENDENCIES
        #{name} (= #{version})

      BUNDLED WITH
         #{Bundler::VERSION}
    LOCK
  end
end
