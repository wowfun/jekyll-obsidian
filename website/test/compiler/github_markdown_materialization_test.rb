# frozen_string_literal: true

require "fileutils"
require "base64"
require "tmpdir"
require "test_helper"
require_relative "../../lib/jekyll_obsidian/github_markdown"

class GitHubMarkdownMaterializationTest < Minitest::Test
  COMMIT = "0123456789abcdef0123456789abcdef01234567"
  NEXT_COMMIT = "89abcdef0123456789abcdef0123456789abcdef"

  class MemoryRequester
    attr_reader :calls

    def initialize(responses)
      @responses = responses.dup
      @calls = []
    end

    def get(uri:, headers:, open_timeout:, read_timeout:)
      @calls << {
        uri: uri.to_s,
        headers: headers,
        open_timeout: open_timeout,
        read_timeout: read_timeout
      }
      @responses.shift || raise("unexpected HTTP request")
    end
  end

  def setup
    @temporary_root = Dir.mktmpdir("github-markdown-materialization")
    @cache_root = File.join(@temporary_root, "cache")
    Dir.mkdir(@cache_root)
  end

  def teardown
    FileUtils.remove_entry(@temporary_root) if File.exist?(@temporary_root)
  end

  def test_materializes_a_github_blob_url_at_one_resolved_commit
    transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT },
      files: { ["acme/widget", COMMIT, "README.md"] => "# Widget\n" }
    )

    documents = JekyllObsidian::GitHubMarkdown.materialize(
      ["https://github.com/Acme/Widget/blob/main/README.md"],
      transport: transport,
      cache_root: @cache_root
    )

    assert_equal 1, documents.length
    document = documents.fetch(0)
    assert_equal "acme/widget", document.repository
    assert_equal "main", document.requested_ref
    assert_equal "README.md", document.path
    assert_equal COMMIT, document.resolved_commit
    assert_equal "https://github.com/acme/widget",
      JekyllObsidian::GitHubMarkdown.repository_url(document.repository)
    assert_equal "https://github.com/acme/widget/blob/#{COMMIT}/README.md", document.source_url
    assert_equal "# Widget\n", document.markdown
    assert documents.frozen?
    assert document.frozen?
    assert document.markdown.frozen?
    assert_equal [["acme/widget", "main"]], transport.resolve_calls
    assert_equal [["acme/widget", COMMIT, "README.md"]], transport.fetch_calls
  end

  def test_mapping_supports_slash_refs_and_resolves_each_repository_ref_once
    transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "release/v2"] => COMMIT },
      files: {
        ["acme/widget", COMMIT, "docs/README.md"] => "# Guide\n",
        ["acme/widget", COMMIT, "CHANGELOG.markdown"] => "# Changes\n"
      }
    )

    documents = JekyllObsidian::GitHubMarkdown.materialize(
      [
        { "repository" => "Acme/Widget", "ref" => "release/v2", "path" => "docs/README.md" },
        { "repository" => "acme/widget", "ref" => "release/v2", "path" => "CHANGELOG.markdown" }
      ],
      transport: transport,
      cache_root: @cache_root
    )

    assert_equal %w[docs/README.md CHANGELOG.markdown], documents.map(&:path)
    assert_equal [["acme/widget", "release/v2"]], transport.resolve_calls
    assert_equal 2, transport.fetch_calls.length
  end

  def test_url_shorthand_rejects_an_encoded_slash_ref
    error = assert_raises(JekyllObsidian::GitHubMarkdown::Invalid) do
      JekyllObsidian::GitHubMarkdown.normalize(
        "https://github.com/acme/widget/blob/release%2Fv2/README.md"
      )
    end

    assert_includes error.message, "single-segment ref"
  end

  def test_reuses_an_exact_commit_cache_after_resolving_the_moving_ref_again
    reference = { "repository" => "acme/widget", "ref" => "main", "path" => "README.md" }
    first_transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT },
      files: { ["acme/widget", COMMIT, "README.md"] => "# Cached\n" }
    )
    JekyllObsidian::GitHubMarkdown.materialize(
      [reference], transport: first_transport, cache_root: @cache_root
    )
    cached_transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT }, files: {}
    )

    documents = JekyllObsidian::GitHubMarkdown.materialize(
      [reference], transport: cached_transport, cache_root: @cache_root
    )

    assert_equal "# Cached\n", documents.fetch(0).markdown
    assert_equal [["acme/widget", "main"]], cached_transport.resolve_calls
    assert_empty cached_transport.fetch_calls
  end

  def test_a_full_commit_reference_can_reuse_its_exact_cache_offline
    reference = { "repository" => "acme/widget", "ref" => COMMIT, "path" => "README.md" }
    first_transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: {},
      files: { ["acme/widget", COMMIT, "README.md"] => "# Immutable\n" }
    )
    JekyllObsidian::GitHubMarkdown.materialize(
      [reference], transport: first_transport, cache_root: @cache_root
    )
    offline_transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(commits: {}, files: {})

    document = JekyllObsidian::GitHubMarkdown.materialize(
      [reference], transport: offline_transport, cache_root: @cache_root
    ).fetch(0)

    assert_equal "# Immutable\n", document.markdown
    assert_empty first_transport.resolve_calls
    assert_empty offline_transport.resolve_calls
    assert_empty offline_transport.fetch_calls
  end

  def test_rejects_a_remote_file_larger_than_one_mebibyte_before_caching_it
    oversized = "a" * (JekyllObsidian::GitHubMarkdown::MAX_FILE_BYTES + 1)
    transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT },
      files: { ["acme/widget", COMMIT, "README.md"] => oversized }
    )

    error = assert_raises(JekyllObsidian::GitHubMarkdown::FetchError) do
      JekyllObsidian::GitHubMarkdown.materialize(
        [{ "repository" => "acme/widget", "ref" => "main", "path" => "README.md" }],
        transport: transport,
        cache_root: @cache_root
      )
    end

    assert_includes error.message, "1 MiB"
    assert_empty Dir.children(@cache_root)
  end

  def test_rejects_materialized_content_larger_than_eight_mebibytes_in_total
    reference = { "repository" => "acme/widget", "ref" => "main", "path" => "README.md" }
    transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT },
      files: { ["acme/widget", COMMIT, "README.md"] => ("a" * JekyllObsidian::GitHubMarkdown::MAX_FILE_BYTES) }
    )

    error = assert_raises(JekyllObsidian::GitHubMarkdown::FetchError) do
      JekyllObsidian::GitHubMarkdown.materialize(
        Array.new(9, reference), transport: transport, cache_root: @cache_root
      )
    end

    assert_includes error.message, "8 MiB"
    assert_equal 1, transport.fetch_calls.length
  end

  def test_http_transport_reads_public_github_rest_responses_without_network_access
    requester = MemoryRequester.new([
      JekyllObsidian::GitHubMarkdown::HttpResponse.new(
        status: 200, headers: {}, body: JSON.generate("sha" => COMMIT)
      ),
      JekyllObsidian::GitHubMarkdown::HttpResponse.new(
        status: 200,
        headers: {},
        body: JSON.generate(
          "type" => "file",
          "encoding" => "base64",
          "content" => Base64.strict_encode64("# From GitHub\n")
        )
      )
    ])
    transport = JekyllObsidian::GitHubMarkdown::HttpTransport.new(requester: requester)

    document = JekyllObsidian::GitHubMarkdown.materialize(
      [{ "repository" => "acme/widget", "ref" => "release/v2", "path" => "docs/README.md" }],
      transport: transport,
      cache_root: @cache_root
    ).fetch(0)

    assert_equal "# From GitHub\n", document.markdown
    assert_equal(
      "https://api.github.com/repos/acme/widget/commits/release%2Fv2",
      requester.calls.fetch(0).fetch(:uri)
    )
    assert_equal(
      "https://api.github.com/repos/acme/widget/contents/docs/README.md?ref=#{COMMIT}",
      requester.calls.fetch(1).fetch(:uri)
    )
    requester.calls.each do |call|
      refute call.fetch(:headers).key?("Authorization")
      assert_equal "2026-03-10", call.dig(:headers, "X-GitHub-Api-Version")
      assert_equal 5, call.fetch(:open_timeout)
      assert_equal 15, call.fetch(:read_timeout)
    end
    assert_raises(ArgumentError) do
      JekyllObsidian::GitHubMarkdown::HttpTransport.new(token: "must-not-be-accepted")
    end
  end

  def test_http_transport_retries_one_transient_response_after_the_full_short_delay
    requester = MemoryRequester.new([
      JekyllObsidian::GitHubMarkdown::HttpResponse.new(
        status: 503, headers: { "retry-after" => "2" }, body: "{}"
      ),
      JekyllObsidian::GitHubMarkdown::HttpResponse.new(
        status: 200, headers: {}, body: JSON.generate("sha" => COMMIT)
      ),
      JekyllObsidian::GitHubMarkdown::HttpResponse.new(
        status: 200,
        headers: {},
        body: JSON.generate(
          "type" => "file",
          "encoding" => "base64",
          "content" => Base64.strict_encode64("# Retried\n")
        )
      )
    ])
    delays = []
    transport = JekyllObsidian::GitHubMarkdown::HttpTransport.new(
      requester: requester,
      sleeper: ->(seconds) { delays << seconds }
    )

    document = JekyllObsidian::GitHubMarkdown.materialize(
      [{ "repository" => "acme/widget", "ref" => "main", "path" => "README.md" }],
      transport: transport,
      cache_root: @cache_root
    ).fetch(0)

    assert_equal "# Retried\n", document.markdown
    assert_equal [2], delays
    assert_equal 3, requester.calls.length
  end

  def test_http_transport_does_not_retry_before_a_long_rate_limit_window
    requester = MemoryRequester.new([
      JekyllObsidian::GitHubMarkdown::HttpResponse.new(
        status: 429, headers: { "retry-after" => "30" }, body: "{}"
      ),
      JekyllObsidian::GitHubMarkdown::HttpResponse.new(
        status: 200, headers: {}, body: JSON.generate("sha" => COMMIT)
      )
    ])
    delays = []
    transport = JekyllObsidian::GitHubMarkdown::HttpTransport.new(
      requester: requester,
      sleeper: ->(seconds) { delays << seconds }
    )

    error = assert_raises(JekyllObsidian::GitHubMarkdown::FetchError) do
      transport.resolve_commit(repository: "acme/widget", ref: "main")
    end

    assert_includes error.message, "retry after 30 seconds"
    assert_empty delays
    assert_equal 1, requester.calls.length
  end

  def test_rejects_a_cache_entry_reached_through_a_symlinked_directory
    reference = { "repository" => "acme/widget", "ref" => "main", "path" => "README.md" }
    initial_transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT },
      files: { ["acme/widget", COMMIT, "README.md"] => "# Cached\n" }
    )
    JekyllObsidian::GitHubMarkdown.materialize(
      [reference], transport: initial_transport, cache_root: @cache_root
    )
    external = File.join(@temporary_root, "external")
    namespace = File.join(@cache_root, "github-markdown")
    File.rename(namespace, external)
    File.symlink(external, namespace)
    transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT },
      files: {}
    )

    error = assert_raises(JekyllObsidian::GitHubMarkdown::CacheError) do
      JekyllObsidian::GitHubMarkdown.materialize(
        [reference],
        transport: transport,
        cache_root: @cache_root
      )
    end

    assert_includes error.message, "non-symlink directory"
    assert_empty transport.fetch_calls
  end

  def test_concurrent_writers_publish_one_identical_regular_cache_entry
    ready = Queue.new
    start = Queue.new
    threads = Array.new(16) do
      Thread.new do
        cache = JekyllObsidian::GitHubMarkdown::Cache.new(@cache_root)
        ready << true
        start.pop
        cache.write(
          repository: "acme/widget",
          commit: COMMIT,
          path: "README.md",
          markdown: "# Shared\n"
        )
      rescue StandardError => exception
        exception
      end
    end
    threads.length.times { ready.pop }
    threads.length.times { start << true }

    results = threads.map(&:value)

    assert_equal Array.new(threads.length, "# Shared\n"), results
    cache_files = Dir.glob(File.join(@cache_root, "github-markdown", "**", "*.md"))
    assert_equal 1, cache_files.length
    stat = File.lstat(cache_files.fetch(0))
    assert stat.file?
    refute stat.symlink?
  end

  def test_late_identical_writer_does_not_replace_the_published_cache_inode
    first = JekyllObsidian::GitHubMarkdown::Cache.new(@cache_root)
    first.write(
      repository: "acme/widget",
      commit: COMMIT,
      path: "README.md",
      markdown: "# Shared\n"
    )
    target = Dir.glob(File.join(@cache_root, "github-markdown", "**", "*.md")).fetch(0)
    before = File.lstat(target)
    late = JekyllObsidian::GitHubMarkdown::Cache.new(@cache_root)
    initial_read = true
    late.define_singleton_method(:read) do |**arguments|
      if initial_read
        initial_read = false
        nil
      else
        super(**arguments)
      end
    end

    result = late.write(
      repository: "acme/widget",
      commit: COMMIT,
      path: "README.md",
      markdown: "# Shared\n"
    )
    after = File.lstat(target)

    assert_equal "# Shared\n", result
    assert_equal [before.dev, before.ino], [after.dev, after.ino]
  end

  def test_does_not_fall_back_to_a_cached_commit_when_a_branch_moves
    reference = { "repository" => "acme/widget", "ref" => "main", "path" => "README.md" }
    first_transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT },
      files: { ["acme/widget", COMMIT, "README.md"] => "# Old\n" }
    )
    JekyllObsidian::GitHubMarkdown.materialize(
      [reference], transport: first_transport, cache_root: @cache_root
    )
    moved_transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => NEXT_COMMIT }, files: {}
    )

    error = assert_raises(JekyllObsidian::GitHubMarkdown::FetchError) do
      JekyllObsidian::GitHubMarkdown.materialize(
        [reference], transport: moved_transport, cache_root: @cache_root
      )
    end

    assert_includes error.message, NEXT_COMMIT
    assert_equal [["acme/widget", NEXT_COMMIT, "README.md"]], moved_transport.fetch_calls
  end

  def test_rejects_more_than_twenty_eight_references_before_transport_access
    reference = { "repository" => "acme/widget", "ref" => "main", "path" => "README.md" }
    transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(commits: {}, files: {})

    error = assert_raises(JekyllObsidian::GitHubMarkdown::Invalid) do
      JekyllObsidian::GitHubMarkdown.materialize(
        Array.new(29, reference), transport: transport, cache_root: @cache_root
      )
    end

    assert_includes error.message, "28"
    assert_empty transport.resolve_calls
    assert_empty transport.fetch_calls
  end

  def test_twenty_eight_distinct_moving_references_fit_the_public_cold_build_budget
    references = []
    commits = {}
    files = {}
    28.times do |index|
      repository = "acme/widget-#{index}"
      ref = "branch-#{index}"
      path = "README.md"
      references << { "repository" => repository, "ref" => ref, "path" => path }
      commits[[repository, ref]] = COMMIT
      files[[repository, COMMIT, path]] = "# Widget #{index}\n"
    end
    transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(commits:, files:)

    documents = JekyllObsidian::GitHubMarkdown.materialize(
      references, transport: transport, cache_root: @cache_root
    )

    assert_equal 28, documents.length
    assert_equal 28, transport.resolve_calls.length
    assert_equal 28, transport.fetch_calls.length
    assert_equal 56, transport.resolve_calls.length + transport.fetch_calls.length
  end

  def test_rejects_unsafe_or_unsupported_reference_forms
    invalid_references = [
      "http://github.com/acme/widget/blob/main/README.md",
      "https://raw.githubusercontent.com/acme/widget/main/README.md",
      "https://github.com/acme/widget/blob/main/README.md?plain=1",
      { "repository" => "acme/widget", "ref" => "main", "path" => "../README.md" },
      { "repository" => "acme/widget", "ref" => "main", "path" => "README.txt" },
      { "repository" => "acme/widget", "ref" => "main", "path" => "README.md", "token" => "secret" }
    ]

    invalid_references.each do |reference|
      assert_raises(JekyllObsidian::GitHubMarkdown::Invalid, reference.inspect) do
        JekyllObsidian::GitHubMarkdown.normalize(reference)
      end
    end
  end

  def test_rejects_non_utf8_remote_markdown
    transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT },
      files: { ["acme/widget", COMMIT, "README.md"] => "\xff".b }
    )

    error = assert_raises(JekyllObsidian::GitHubMarkdown::FetchError) do
      JekyllObsidian::GitHubMarkdown.materialize(
        [{ "repository" => "acme/widget", "ref" => "main", "path" => "README.md" }],
        transport: transport,
        cache_root: @cache_root
      )
    end

    assert_includes error.message, "UTF-8"
  end

  def test_rejects_xml_forbidden_characters_from_transport_and_manifest_replay
    reference = { "repository" => "acme/widget", "ref" => "main", "path" => "README.md" }
    markdown = "# Unsafe\n\0bad\n"
    transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT },
      files: { ["acme/widget", COMMIT, "README.md"] => markdown }
    )

    fetch_error = assert_raises(JekyllObsidian::GitHubMarkdown::FetchError) do
      JekyllObsidian::GitHubMarkdown.materialize(
        [reference], transport: transport, cache_root: @cache_root
      )
    end
    assert_includes fetch_error.message, "XML 1.0"

    manifest = {
      "version" => 1,
      "documents" => [
        {
          "repository" => "acme/widget",
          "requested_ref" => "main",
          "path" => "README.md",
          "resolved_commit" => COMMIT,
          "digest" => Digest::SHA256.hexdigest(markdown),
          "markdown" => markdown
        }
      ]
    }
    manifest_error = assert_raises(JekyllObsidian::GitHubMarkdown::ManifestError) do
      JekyllObsidian::GitHubMarkdown.materialize([reference], manifest: manifest)
    end
    assert_includes manifest_error.message, "XML 1.0"
  end

  def test_source_url_percent_encodes_each_markdown_path_segment
    path = "docs/Product Guide.md"
    transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT },
      files: { ["acme/widget", COMMIT, path] => "# Guide\n" }
    )

    document = JekyllObsidian::GitHubMarkdown.materialize(
      [{ "repository" => "acme/widget", "ref" => "main", "path" => path }],
      transport: transport,
      cache_root: @cache_root
    ).fetch(0)

    assert_equal "https://github.com/acme/widget/blob/#{COMMIT}/docs/Product%20Guide.md", document.source_url
  end

  def test_manifest_round_trip_replays_the_exact_documents_without_transport_access
    reference = { "repository" => "acme/widget", "ref" => "main", "path" => "README.md" }
    online_transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT },
      files: { ["acme/widget", COMMIT, "README.md"] => "# Widget\n" }
    )
    online = JekyllObsidian::GitHubMarkdown.materialize(
      [reference], transport: online_transport, cache_root: @cache_root
    )

    manifest = JekyllObsidian::GitHubMarkdown.dump_manifest(online)
    parsed = JSON.parse(manifest)
    assert_equal 1, parsed["version"]
    assert_equal({
      "repository" => "acme/widget",
      "requested_ref" => "main",
      "path" => "README.md",
      "resolved_commit" => COMMIT,
      "digest" => "563b5e3ff9edbef5781f1a064d25fb5f478d6a986462d0561f5f68d1c3969ba6",
      "markdown" => "# Widget\n"
    }, parsed.fetch("documents").fetch(0))
    offline_transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(commits: {}, files: {})

    offline = JekyllObsidian::GitHubMarkdown.materialize(
      [reference], transport: offline_transport, manifest: manifest
    )

    assert_equal online, offline
    assert_empty offline_transport.resolve_calls
    assert_empty offline_transport.fetch_calls
  end

  def test_manifest_rejects_tampered_markdown_unknown_fields_and_reference_mismatches
    reference = { "repository" => "acme/widget", "ref" => "main", "path" => "README.md" }
    transport = JekyllObsidian::GitHubMarkdown::MemoryTransport.new(
      commits: { ["acme/widget", "main"] => COMMIT },
      files: { ["acme/widget", COMMIT, "README.md"] => "# Widget\n" }
    )
    documents = JekyllObsidian::GitHubMarkdown.materialize(
      [reference], transport: transport, cache_root: @cache_root
    )
    original = JSON.parse(JekyllObsidian::GitHubMarkdown.dump_manifest(documents))
    tampered = Marshal.load(Marshal.dump(original))
    tampered["documents"][0]["markdown"] = "# Replaced\n"
    unknown = Marshal.load(Marshal.dump(original))
    unknown["documents"][0]["source_url"] = "https://attacker.example/"
    mismatched = Marshal.load(Marshal.dump(original))
    mismatched["documents"][0]["requested_ref"] = "other"

    [tampered, unknown, mismatched].each do |manifest|
      assert_raises(JekyllObsidian::GitHubMarkdown::ManifestError) do
        JekyllObsidian::GitHubMarkdown.materialize([reference], manifest: manifest)
      end
    end
  end
end
