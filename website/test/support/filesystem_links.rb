# frozen_string_literal: true

module TestFilesystemLinks
  # Junctions exercise directory reparse-point guards without requiring the
  # Windows symbolic-link privilege. File symlinks still need that privilege.
  def create_test_symlink(source, destination)
    File.symlink(source, destination)
  rescue Errno::EACCES, Errno::EPERM => exception
    raise exception unless Gem.win_platform?
    unless File.directory?(source)
      skip "File symbolic links require Windows Developer Mode or the symbolic-link privilege"
    end
    output, status = Open3.capture2e(ENV.fetch("COMSPEC", "cmd.exe"), "/d", "/c", "mklink", "/J", destination.tr("/", "\\"), source.tr("/", "\\"))
    assert status.success?, "Could not create a test directory junction: #{output}"
    assert File.lstat(destination).symlink?, "Ruby must identify the test junction as a reparse point"
    0
  end
end
