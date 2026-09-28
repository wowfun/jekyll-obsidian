# frozen_string_literal: true

require "test_helper"
require "rubygems/package"
require "jekyll_obsidian/initializer"

class VersionContractTest < Minitest::Test
  def test_ruby_node_and_gem_use_one_release_version
    root = File.expand_path("../../..", __dir__)
    spec = Gem::Specification.load(File.join(root, "jekyll-obsidian-site.gemspec"))
    package = JSON.parse(File.read(File.join(root, "website", "package.json")))
    lock = JSON.parse(File.read(File.join(root, "website", "package-lock.json")))
    assert_equal JekyllObsidian::VERSION, spec.version.to_s
    assert_equal JekyllObsidian::VERSION, package.fetch("version")
    assert_equal JekyllObsidian::VERSION, lock.fetch("version")
    assert_equal JekyllObsidian::VERSION, lock.fetch("packages").fetch("").fetch("version")
    assert_equal "jekyll-obsidian-site", spec.name
    assert_equal ["jekyll-obsidian"], spec.executables
  end

  def test_browser_install_examples_match_the_initialized_host
    root = File.expand_path("../../..", __dir__)
    Dir.mktmpdir("jekyll-obsidian-examples") do |host|
      JekyllObsidian::Initializer.run(root: host)
      %w[jekyll-obsidian.yml pages.yml].each do |name|
        generated = name == "pages.yml" ? ".github/workflows/#{name}" : ".github/#{name}"
        assert_equal File.read(File.join(root, "examples", name)), File.read(File.join(host, generated))
      end
    end
  end
end
