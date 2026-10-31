# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "fileutils"
require "jekyll_obsidian/git_history"

class GitHistoryTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("git-times")
    git("init", "--quiet")
    git("config", "user.name", "Test")
    git("config", "user.email", "test@example.test")
    FileUtils.mkdir_p(File.join(@root, "vault"))
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_descendant_cache_reuses_unchanged_paths_and_handles_renames_deletions_and_readds
    write("vault/中文.md", "first")
    write("vault/other.md", "second")
    commit("2020-01-01")
    original_head = git("rev-parse", "HEAD").strip
    first = read
    assert_equal({ "中文.md" => "2020-01-01T12:00:00Z", "other.md" => "2020-01-01T12:00:00Z" }, first)
    write("outside.txt", "unrelated")
    commit("2021-01-01")
    calls = []
    original_stream = JekyllObsidian::GitHistory.method(:stream)
    JekyllObsidian::GitHistory.define_singleton_method(:stream) do |root, *args, &block|
      calls << args
      original_stream.call(root, *args, &block)
    end
    assert_equal first, read(cached_head: original_head, cached_times: first)
    refute calls.any? { |args| args.first == "log" }, "unrelated commits must not rescan history"

    git("mv", "vault/中文.md", "vault/renamed.md")
    git("rm", "vault/other.md")
    commit("2022-01-01")
    calls.clear
    changed_head = git("rev-parse", "HEAD").strip
    changed = read(cached_head: original_head, cached_times: first)
    assert_equal({ "renamed.md" => "2022-01-01T12:00:00Z" }, changed)
    assert_equal ["vault/renamed.md"], calls.find { |args| args.first == "log" }.drop_while { |arg| arg != "--" }.drop(1)
    write("vault/other.md", "restored")
    commit("2023-01-01")
    restored = read(cached_head: changed_head, cached_times: changed)
    assert_equal "2020-01-01T12:00:00Z", restored.fetch("other.md")
    assert_equal read, restored

    git("checkout", "--quiet", "--detach", original_head)
    assert_equal first, read(cached_head: changed_head, cached_times: changed)
  ensure
    JekyllObsidian::GitHistory.define_singleton_method(:stream, original_stream) if original_stream
  end

  def test_merge_history_and_streaming_match_a_fresh_scan
    write("vault/a.md", "base")
    commit("2020-01-01")
    git("checkout", "--quiet", "-b", "topic")
    write("vault/branch.md", "branch")
    commit("2021-01-01")
    git("checkout", "--quiet", "-")
    write("vault/main.md", "main")
    commit("2022-01-01")
    cached_head = git("rev-parse", "HEAD").strip
    cached_times = read
    git("merge", "--quiet", "--no-ff", "topic", "-m", "Merge")
    assert_equal read, read(cached_head: cached_head, cached_times: cached_times)
    # History is never passed through capture3, including on a full scan.
    original_capture = Open3.method(:capture3)
    Open3.define_singleton_method(:capture3) do |*args, **options|
      raise "unbounded history capture" if args.include?("log")
      original_capture.call(*args, **options)
    end
    assert_equal 3, read.size
  ensure
    Open3.define_singleton_method(:capture3, original_capture) if original_capture
  end

  private

  def read(**cached)
    JekyllObsidian::GitHistory.read(root: @root, source: "vault", head: git("rev-parse", "HEAD").strip, **cached)
  end

  def write(path, text)
    File.write(File.join(@root, path), text)
  end

  def commit(day)
    git("add", ".")
    git("commit", "--quiet", "-m", day, environment: { "GIT_AUTHOR_DATE" => "#{day}T12:00:00Z", "GIT_COMMITTER_DATE" => "#{day}T12:00:00Z" })
  end

  def git(*args, environment: {})
    out, err, status = Open3.capture3(environment, "git", "-C", @root, *args)
    assert status.success?, err
    out
  end
end
