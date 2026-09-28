# frozen_string_literal: true

require "fileutils"
require "open3"
require_relative "../lib/jekyll_obsidian/github_markdown"

root = File.expand_path("../..", __dir__)
commit, status = Open3.capture2("git", "-C", root, "rev-parse", "HEAD")
abort "Cannot resolve the documentation commit" unless status.success?
commit = commit.strip
repository = "wowfun/jekyll-obsidian"
# Locale overlays precede default-language notes in the compiler snapshot.
references = %w[README.zh-CN.md README.md].map do |path|
  JekyllObsidian::GitHubMarkdown::Reference.new(repository:, ref: "main", path:)
end
files = references.to_h do |reference|
  markdown, status = Open3.capture2("git", "-C", root, "show", "#{commit}:#{reference.path}")
  abort "Cannot read #{reference.path} at #{commit}" unless status.success?
  [[repository, commit, reference.path], markdown]
end
transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
  commits: { [repository, "main"] => commit }, files:
)
cache_root = File.join(root, ".jekyll-obsidian-cache")
FileUtils.mkdir_p(cache_root)
documents = JekyllObsidian::GitHubMarkdown.materialize(references, transport:, cache_root:)
destination = File.join(cache_root, "github-markdown-project.json")
File.write(destination, JekyllObsidian::GitHubMarkdown.dump_manifest(documents))
