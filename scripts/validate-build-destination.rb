#!/usr/bin/env ruby
# frozen_string_literal: true

def reject(message)
  warn "build destination: #{message}"
  exit 64
end

project_root = File.realpath(ARGV.fetch(0))
destination = ARGV.fetch(1)

# Jekyll's cleaner removes files below `destination`. Keep that destructive
# boundary deliberately narrow: builds may only target a dedicated top-level
# _site directory, optionally carrying a test/deployment suffix.
unless destination.match?(/\A_site(?:-[A-Za-z0-9][A-Za-z0-9._-]*)?\z/)
  reject("must be _site or a top-level _site-NAME directory")
end

target = File.join(project_root, destination)
begin
  stat = File.lstat(target)
  reject("must not be a symbolic link") if stat.symlink?
  reject("must be a directory when it already exists") unless stat.directory?
  resolved = File.realpath(target)
  reject("resolves outside the repository") unless File.dirname(resolved) == project_root
rescue Errno::ENOENT
  # A missing dedicated destination is safe for Jekyll to create.
end
