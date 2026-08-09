# frozen_string_literal: true

require "test_helper"

class VersionContractTest < Minitest::Test
  def test_runtime_and_npm_metadata_share_a_stable_semver
    project_root = File.expand_path("../..", __dir__)
    package = JSON.parse(File.read(File.join(project_root, "package.json")))
    lockfile = JSON.parse(File.read(File.join(project_root, "package-lock.json")))
    release = File.read(File.join(project_root, ".jekyll-obsidian-release"))
    version = JekyllObsidian::VERSION

    assert_equal version, package.fetch("version")
    assert_equal version, lockfile.fetch("version")
    assert_equal version, lockfile.dig("packages", "", "version")
    assert_equal "format=1\nversion=#{version}\nupdater_protocol=1\n", release
    assert_match(/\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/, version)
  end
end
