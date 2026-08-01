# frozen_string_literal: true

require "open3"
require "rbconfig"
require "test_helper"
require "tmpdir"
require "fileutils"

class BuildDestinationTest < Minitest::Test
  VALIDATOR = File.expand_path("../../scripts/validate-build-destination.rb", __dir__)

  def test_accepts_only_dedicated_top_level_site_directories
    Dir.mktmpdir("garden-build-destination") do |root|
      %w[_site _site-root _site-project-check-2].each do |destination|
        _output, error, status = validate(root, destination)
        assert status.success?, "expected #{destination.inspect} to pass: #{error}"
      end

      ["", "vault", "vault/out", ".git", "src", "_site/child", "_site-../vault", "../_site", "/tmp/site"].each do |destination|
        _output, error, status = validate(root, destination)
        refute status.success?, "expected #{destination.inspect} to fail"
        assert_includes error, "build destination:"
      end
    end
  end

  def test_rejects_an_existing_destination_symlink_or_file
    Dir.mktmpdir("garden-build-destination") do |root|
      outside = Dir.mktmpdir("garden-build-outside")
      File.symlink(outside, File.join(root, "_site-linked"))
      File.write(File.join(root, "_site-file"), "not a directory")

      _output, symlink_error, symlink_status = validate(root, "_site-linked")
      refute symlink_status.success?
      assert_includes symlink_error, "must not be a symbolic link"

      _output, file_error, file_status = validate(root, "_site-file")
      refute file_status.success?
      assert_includes file_error, "must be a directory"
    ensure
      FileUtils.remove_entry(outside) if outside && File.exist?(outside)
    end
  end

  private

  def validate(root, destination)
    Open3.capture3(RbConfig.ruby, VALIDATOR, root, destination)
  end
end
