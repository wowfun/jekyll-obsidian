# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "jekyll_obsidian/adapter"

class OpenedFileIdentityTest < Minitest::Test
  def test_matches_path_to_open_handle_on_windows_and_posix
    Dir.mktmpdir do |root|
      path = File.join(root, "note.md")
      other = File.join(root, "other.md")
      File.write(path, "same bytes")
      File.write(other, "same bytes")
      before = File.lstat(path)
      File.open(path, "rb") { |file| assert JekyllObsidian::Adapter.send(:opened_file_matches?, path, file, before) }
      File.open(other, "rb") { |file| refute JekyllObsidian::Adapter.send(:opened_file_matches?, path, file, before) }
      File.rename(path, File.join(root, "old.md"))
      File.write(path, "same bytes")
      File.open(path, "rb") { |file| refute JekyllObsidian::Adapter.send(:opened_file_matches?, path, file, before) }
    end
  end
end
