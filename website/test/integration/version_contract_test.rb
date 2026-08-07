# frozen_string_literal: true

require "date"
require "test_helper"

class VersionContractTest < Minitest::Test
  def test_runtime_and_npm_metadata_share_a_valid_calver
    project_root = File.expand_path("../..", __dir__)
    package = JSON.parse(File.read(File.join(project_root, "package.json")))
    lockfile = JSON.parse(File.read(File.join(project_root, "package-lock.json")))
    release = File.read(File.join(project_root, ".jekyll-obsidian-release"))
    version = JekyllObsidian::VERSION

    assert_equal version, package.fetch("version")
    assert_equal version, lockfile.fetch("version")
    assert_equal version, lockfile.dig("packages", "", "version")
    assert_equal "format=1\nversion=#{version}\nupdater_protocol=1\n", release
    assert_match(/\A\d{4}\.(?:[1-9]|1[0-2])\.(?:[1-9]|[12]\d|3[01])\z/, version)

    year, month, day = version.split(".").map { |part| Integer(part, 10) }
    date = Date.new(year, month, day)
    assert_equal "#{date.year}.#{date.month}.#{date.day}", version
  rescue Date::Error
    flunk "#{version.inspect} is not a calendar date"
  end
end
