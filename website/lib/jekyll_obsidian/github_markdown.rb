# frozen_string_literal: true

require "uri"
require "tempfile"
require "base64"
require "digest"
require "json"
require "net/http"
require "timeout"

require_relative "value_objects"
require_relative "output_text"

module JekyllObsidian
  module GitHubMarkdown
    REPOSITORY_COMPONENT = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
    COMMIT = /\A[0-9a-f]{40}\z/i
    INVALID_REF_CHARACTER = /[\x00-\x20\x7f~^:?*\[\\]/
    ENCODED_SEPARATOR = /%(?:2f|5c)/i
    MARKDOWN_EXTENSIONS = %w[.md .markdown].freeze
    MAX_FILE_BYTES = 1024 * 1024
    # A distinct moving reference costs one resolve and one contents request.
    # Twenty-eight leaves four requests inside GitHub's 60-request anonymous hourly budget.
    MAX_REFERENCES = 28
    MAX_TOTAL_BYTES = 8 * 1024 * 1024
    MAX_HTTP_RESPONSE_BYTES = 2 * 1024 * 1024
    MAX_MANIFEST_BYTES = 64 * 1024 * 1024
    MAX_RETRY_WAIT_SECONDS = 2
    MANIFEST_VERSION = 1

    Reference = ImmutableRecord.define(:repository, :ref, :path)
    Document = ImmutableRecord.define(
      :repository,
      :requested_ref,
      :path,
      :resolved_commit,
      :source_url,
      :digest,
      :markdown
    )
    HttpResponse = ImmutableRecord.define(:status, :headers, :body)

    class Error < StandardError; end
    class Invalid < Error; end
    class FetchError < Error; end
    class CacheError < Error; end
    class ManifestError < Error; end

    # The adapter owns this runtime directory. These checks reject pre-existing
    # links and non-regular entries and support cooperating concurrent builds;
    # like the other application caches, it is not a capability boundary
    # against a same-user process replacing directories during a system call.
    class Cache
      def initialize(root)
        expanded = File.expand_path(root)
        stat = File.lstat(expanded)
        unless stat.directory? && !stat.symlink?
          raise CacheError, "GitHub Markdown cache root must be a non-symlink directory"
        end
        @root = File.realpath(expanded)
        validate_directory!(@root, "GitHub Markdown cache root")
      rescue TypeError
        raise CacheError, "GitHub Markdown cache root must be a directory path"
      rescue Errno::ENOENT
        raise CacheError, "GitHub Markdown cache root does not exist"
      rescue SystemCallError => exception
        raise CacheError, "cannot validate GitHub Markdown cache root: #{exception.message}"
      end

      def read(repository:, commit:, path:)
        target = target_path(repository, commit, path)
        return nil unless File.exist?(target) || File.symlink?(target)

        ensure_tree!(File.dirname(target))
        before = File.lstat(target)
        unless before.file? && !before.symlink?
          raise CacheError, "GitHub Markdown cache entry must be a non-symlink regular file"
        end
        flags = File::RDONLY | File::BINARY |
          (File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0) |
          (File.const_defined?(:SHARE_DELETE) ? File::SHARE_DELETE : 0)
        File.open(target, flags) do |file|
          opened = file.stat
          unless opened.file? && opened.dev == before.dev && opened.ino == before.ino
            raise CacheError, "GitHub Markdown cache entry changed while opening"
          end
          file.read
        end
      rescue SystemCallError => exception
        raise CacheError, "cannot read GitHub Markdown cache: #{exception.message}"
      end

      def write(repository:, commit:, path:, markdown:)
        target = target_path(repository, commit, path)
        parent = ensure_tree!(File.dirname(target))
        existing = read(repository: repository, commit: commit, path: path)
        return existing if existing

        temporary = Tempfile.create(["github-markdown.", ".tmp"], parent)
        temporary_path = temporary.path
        temporary.binmode
        temporary.write(markdown)
        temporary.flush
        temporary.fsync
        temporary.close
        begin
          # Publish the complete inode without replacing an entry another
          # writer installed after the initial cache read.
          File.link(temporary_path, target)
        rescue Errno::EEXIST, Errno::EACCES => exception
          concurrent = read(repository: repository, commit: commit, path: path)
          return concurrent if concurrent == markdown
          raise exception
        end
        markdown
      rescue SystemCallError => exception
        raise CacheError, "cannot write GitHub Markdown cache: #{exception.message}"
      ensure
        temporary.close if defined?(temporary) && temporary && !temporary.closed?
        File.unlink(temporary_path) if defined?(temporary_path) && temporary_path && File.exist?(temporary_path)
      end

      private

      def target_path(repository, commit, path)
        digest = Digest::SHA256.hexdigest([repository, commit, path].join("\0"))
        File.join(@root, "github-markdown", "v1", commit, digest[0, 2], "#{digest}.md")
      end

      def ensure_tree!(target)
        prefix = "#{@root}#{File::SEPARATOR}"
        relative = target.delete_prefix(prefix)
        if relative == target || relative.split(File::SEPARATOR).any? { |part| part.empty? || part == "." || part == ".." }
          raise CacheError, "GitHub Markdown cache entry escapes its cache root"
        end

        cursor = @root
        relative.split(File::SEPARATOR).each do |part|
          cursor = File.join(cursor, part)
          unless File.exist?(cursor) || File.symlink?(cursor)
            begin
              Dir.mkdir(cursor)
            rescue Errno::EEXIST
              # Another materializer installed this component. Revalidate it
              # through the same non-symlink policy before continuing.
            end
          end
          validate_directory!(cursor, "GitHub Markdown cache directory")
        end
        cursor
      end

      def validate_directory!(path, label)
        stat = File.lstat(path)
        unless stat.directory? && !stat.symlink? && File.realpath(path) == path
          raise CacheError, "#{label} must be a non-symlink directory"
        end
      rescue Errno::ENOENT
        raise CacheError, "#{label} does not exist"
      rescue SystemCallError => exception
        raise CacheError, "cannot validate #{label}: #{exception.message}"
      end
    end

    class MemoryTransport
      attr_reader :resolve_calls, :fetch_calls

      def initialize(commits:, files:)
        @commits = commits
        @files = files
        @resolve_calls = []
        @fetch_calls = []
      end

      def resolve_commit(repository:, ref:)
        key = [repository, ref]
        @resolve_calls << key
        @commits.fetch(key) { raise FetchError, "GitHub ref not found: #{repository}@#{ref}" }
      end

      def fetch_markdown(repository:, commit:, path:)
        key = [repository, commit, path]
        @fetch_calls << key
        @files.fetch(key) { raise FetchError, "GitHub file not found: #{repository}/#{path}@#{commit}" }
      end
    end

    class NetworkError < FetchError; end

    class NetHttpRequester
      def get(uri:, headers:, open_timeout:, read_timeout:)
        unless uri.is_a?(URI::HTTPS) && uri.host == "api.github.com" && uri.port == 443 && uri.userinfo.nil?
          raise FetchError, "GitHub HTTP transport only connects to https://api.github.com"
        end

        request = Net::HTTP::Get.new(uri)
        headers.each { |name, value| request[name] = value }
        body = +""
        response_headers = nil
        status = nil
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout
        http.write_timeout = read_timeout
        http.request(request) do |response|
          status = response.code.to_i
          response_headers = response.each_header.to_h
          response.read_body do |chunk|
            body << chunk
            if body.bytesize > MAX_HTTP_RESPONSE_BYTES
              raise FetchError, "GitHub API response exceeds the 2 MiB transport limit"
            end
          end
        end
        HttpResponse.new(status: status, headers: response_headers, body: body)
      rescue Timeout::Error, IOError, EOFError, SocketError, SystemCallError, OpenSSL::SSL::SSLError => exception
        raise NetworkError, "GitHub API request failed: #{exception.class}"
      end
    end

    class HttpTransport
      API_ROOT = "https://api.github.com"
      DEFAULT_OPEN_TIMEOUT = 5
      DEFAULT_READ_TIMEOUT = 15

      def initialize(
        requester: NetHttpRequester.new,
        open_timeout: DEFAULT_OPEN_TIMEOUT,
        read_timeout: DEFAULT_READ_TIMEOUT,
        sleeper: ->(seconds) { sleep(seconds) }
      )
        unless open_timeout.is_a?(Numeric) && open_timeout.positive? &&
            read_timeout.is_a?(Numeric) && read_timeout.positive?
          raise Invalid, "GitHub HTTP timeouts must be positive numbers"
        end

        @requester = requester
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @sleeper = sleeper
        @headers = {
          "Accept" => "application/vnd.github+json",
          "X-GitHub-Api-Version" => "2026-03-10",
          "User-Agent" => "jekyll-obsidian"
        }
        @headers.freeze
      end

      def resolve_commit(repository:, ref:)
        encoded_ref = URI.encode_uri_component(ref)
        response = request_json("#{API_ROOT}/repos/#{repository}/commits/#{encoded_ref}")
        sha = response["sha"]
        raise FetchError, "GitHub commit response is missing sha" unless sha.is_a?(String)

        sha
      end

      def fetch_markdown(repository:, commit:, path:)
        encoded_path = path.split("/").map { |part| URI.encode_uri_component(part) }.join("/")
        query = URI.encode_www_form("ref" => commit)
        response = request_json("#{API_ROOT}/repos/#{repository}/contents/#{encoded_path}?#{query}")
        unless response["type"] == "file" && response["encoding"] == "base64" && response["content"].is_a?(String)
          raise FetchError, "GitHub contents response is not a Base64 file"
        end

        Base64.strict_decode64(response["content"].gsub(/[\t\r\n ]/, ""))
      rescue ArgumentError
        raise FetchError, "GitHub contents response contains invalid Base64"
      end

      private

      def request_json(raw_uri)
        attempts = 0
        loop do
          attempts += 1
          begin
            response = @requester.get(
              uri: URI.parse(raw_uri),
              headers: @headers,
              open_timeout: @open_timeout,
              read_timeout: @read_timeout
            )
          rescue NetworkError
            raise if attempts > 1
            next
          end
          unless response.is_a?(HttpResponse) && response.status.is_a?(Integer) &&
              response.headers.is_a?(Hash) && response.body.is_a?(String)
            raise FetchError, "GitHub HTTP requester returned an invalid response"
          end

          if response.status == 200
            begin
              parsed = JSON.parse(response.body)
            rescue JSON::ParserError
              raise FetchError, "GitHub API returned invalid JSON"
            end
            raise FetchError, "GitHub API response must be a JSON object" unless parsed.is_a?(Hash)

            return parsed
          end
          retry_after = response.headers["retry-after"].to_s.to_i
          rate_limited = response.status == 429 ||
            (response.status == 403 && (retry_after.positive? || response.headers["x-ratelimit-remaining"].to_s == "0"))
          if rate_limited
            if attempts == 1 && retry_after.between?(1, MAX_RETRY_WAIT_SECONDS)
              @sleeper.call(retry_after)
              next
            end
            suffix = if retry_after.positive?
              "; retry after #{retry_after} seconds"
            elsif !response.headers["x-ratelimit-reset"].to_s.empty?
              "; rate limit resets at #{response.headers["x-ratelimit-reset"]} UTC epoch seconds"
            else
              ""
            end
            raise FetchError, "GitHub API returned HTTP #{response.status}#{suffix}"
          end
          if attempts == 1 && response.status.between?(500, 599)
            if retry_after > MAX_RETRY_WAIT_SECONDS
              raise FetchError, "GitHub API returned HTTP #{response.status}; retry after #{retry_after} seconds"
            end
            @sleeper.call(retry_after) if retry_after.positive?
            next
          end
          raise FetchError, "GitHub API returned HTTP #{response.status}"
        end
      end
    end

    module_function

    def materialize(references, transport: nil, cache_root: nil, manifest: nil)
      normalized_references = normalize_references(references)
      return materialize_manifest(normalized_references, manifest) unless manifest.nil?
      return [].freeze if normalized_references.empty?

      raise Invalid, "GitHub Markdown transport is required" unless transport
      raise Invalid, "GitHub Markdown cache root is required" unless cache_root

      cache = Cache.new(cache_root)
      resolved = {}
      content = {}
      total_bytes = 0
      normalized_references.map do |reference|
        commit = if reference.ref.match?(COMMIT)
          reference.ref
        else
          resolved.fetch([reference.repository, reference.ref]) do |key|
            resolved[key] = transport.resolve_commit(repository: reference.repository, ref: reference.ref)
          end
        end
        unless commit.is_a?(String) && commit.match?(COMMIT)
          raise FetchError, "GitHub returned an invalid commit for #{reference.repository}@#{reference.ref}"
        end
        commit = commit.downcase
        content_key = [reference.repository, commit, reference.path]
        markdown = content.fetch(content_key) do
          cached = cache.read(repository: reference.repository, commit: commit, path: reference.path)
          if cached
            content[content_key] = normalize_markdown(cached, reference)
          else
            fetched = transport.fetch_markdown(
              repository: reference.repository,
              commit: commit,
              path: reference.path
            )
            normalized = normalize_markdown(fetched, reference)
            content[content_key] = cache.write(
              repository: reference.repository,
              commit: commit,
              path: reference.path,
              markdown: normalized
            )
          end
        end
        total_bytes += markdown.bytesize
        if total_bytes > MAX_TOTAL_BYTES
          raise FetchError, "GitHub Markdown content exceeds the 8 MiB total limit"
        end
        Document.new(
          repository: reference.repository,
          requested_ref: reference.ref,
          path: reference.path,
          resolved_commit: commit,
          source_url: source_url(reference.repository, commit, reference.path),
          digest: Digest::SHA256.hexdigest(markdown.b),
          markdown: markdown
        )
      end.freeze
    end

    def dump_manifest(documents)
      unless documents.is_a?(Array) && documents.length <= MAX_REFERENCES
        raise ManifestError, "GitHub Markdown manifest documents must be an array with at most #{MAX_REFERENCES} entries"
      end

      total_bytes = 0
      serialized = documents.map.with_index do |document, index|
        unless document.is_a?(Document)
          raise ManifestError, "GitHub Markdown manifest document #{index} is invalid"
        end
        values = %i[repository requested_ref path resolved_commit digest markdown].to_h do |field|
          [field, document.public_send(field)]
        end
        unless values.values.all? { |value| value.is_a?(String) }
          raise ManifestError, "GitHub Markdown manifest document #{index} fields must be strings"
        end
        raw_document = {
          "repository" => document.repository,
          "requested_ref" => document.requested_ref,
          "path" => document.path,
          "resolved_commit" => document.resolved_commit,
          "digest" => document.digest,
          "markdown" => document.markdown
        }
        begin
          reference = Reference.new(
            repository: normalize_repository(document.repository),
            ref: normalize_ref(document.requested_ref, single_segment: false),
            path: normalize_path(document.path)
          )
          validate_manifest_document(raw_document, reference, index)
        rescue Invalid => exception
          raise ManifestError, "GitHub Markdown manifest document #{index} is invalid: #{exception.message}"
        end
        total_bytes += document.markdown.bytesize
        raise ManifestError, "GitHub Markdown manifest exceeds the 8 MiB total limit" if total_bytes > MAX_TOTAL_BYTES

        raw_document
      end
      output = JSON.generate("version" => MANIFEST_VERSION, "documents" => serialized)
      if output.bytesize > MAX_MANIFEST_BYTES
        raise ManifestError, "GitHub Markdown manifest exceeds the 64 MiB serialized limit"
      end
      output.freeze
    end

    def normalize_references(references)
      unless references.is_a?(Array)
        raise Invalid, "GitHub Markdown references must be an array"
      end
      if references.length > MAX_REFERENCES
        raise Invalid, "GitHub Markdown supports at most #{MAX_REFERENCES} references per site"
      end

      references.map { |reference| normalize(reference) }.freeze
    end

    def materialize_manifest(references, raw_manifest)
      manifest = parse_manifest(raw_manifest)
      unless manifest.keys.all? { |key| key.is_a?(String) } &&
          manifest.keys.sort == %w[documents version] && manifest["version"] == MANIFEST_VERSION &&
          manifest["documents"].is_a?(Array)
        raise ManifestError, "GitHub Markdown manifest must be a version 1 document list"
      end
      unless manifest["documents"].length == references.length
        raise ManifestError, "GitHub Markdown manifest does not match the configured references"
      end

      total_bytes = 0
      manifest["documents"].each_with_index.map do |raw_document, index|
        document = validate_manifest_document(raw_document, references.fetch(index), index)
        total_bytes += document.markdown.bytesize
        if total_bytes > MAX_TOTAL_BYTES
          raise ManifestError, "GitHub Markdown manifest exceeds the 8 MiB total limit"
        end
        document
      end.freeze
    end

    def parse_manifest(raw_manifest)
      case raw_manifest
      when String
        unless raw_manifest.valid_encoding? && raw_manifest.bytesize <= MAX_MANIFEST_BYTES
          raise ManifestError, "GitHub Markdown manifest must be valid UTF-8 and at most 64 MiB"
        end
        parsed = JSON.parse(raw_manifest)
        raise ManifestError, "GitHub Markdown manifest must be a JSON object" unless parsed.is_a?(Hash)

        parsed
      when Hash
        raw_manifest
      else
        raise ManifestError, "GitHub Markdown manifest must be JSON or a mapping"
      end
    rescue JSON::ParserError
      raise ManifestError, "GitHub Markdown manifest is invalid JSON"
    end

    def validate_manifest_document(raw_document, reference, index)
      keys = %w[digest markdown path repository requested_ref resolved_commit]
      unless raw_document.is_a?(Hash) && raw_document.keys.all? { |key| key.is_a?(String) } &&
          raw_document.keys.sort == keys
        raise ManifestError, "GitHub Markdown manifest document #{index} has an invalid shape"
      end
      unless keys.all? { |key| raw_document[key].is_a?(String) }
        raise ManifestError, "GitHub Markdown manifest document #{index} fields must be strings"
      end

      begin
        manifest_reference = Reference.new(
          repository: normalize_repository(raw_document["repository"]),
          ref: normalize_ref(raw_document["requested_ref"], single_segment: false),
          path: normalize_path(raw_document["path"])
        )
      rescue Invalid => exception
        raise ManifestError, "GitHub Markdown manifest document #{index} is invalid: #{exception.message}"
      end
      unless manifest_reference == reference && manifest_reference.repository == raw_document["repository"] &&
          manifest_reference.ref == raw_document["requested_ref"] && manifest_reference.path == raw_document["path"]
        raise ManifestError, "GitHub Markdown manifest document #{index} does not match its configured reference"
      end

      commit = raw_document["resolved_commit"].dup
      unless commit.match?(COMMIT) && commit == commit.downcase
        raise ManifestError, "GitHub Markdown manifest document #{index} has an invalid commit"
      end
      digest = raw_document["digest"].dup
      unless digest.match?(/\A[0-9a-f]{64}\z/)
        raise ManifestError, "GitHub Markdown manifest document #{index} has an invalid digest"
      end
      begin
        markdown = normalize_markdown(raw_document["markdown"], reference)
      rescue FetchError => exception
        raise ManifestError, "GitHub Markdown manifest document #{index} is invalid: #{exception.message}"
      end
      unless Digest::SHA256.hexdigest(markdown.b) == digest
        raise ManifestError, "GitHub Markdown manifest document #{index} digest does not match its Markdown"
      end

      Document.new(
        repository: reference.repository,
        requested_ref: reference.ref,
        path: reference.path,
        resolved_commit: commit,
        source_url: source_url(reference.repository, commit, reference.path),
        digest: digest,
        markdown: markdown
      )
    end

    def normalize(raw)
      if raw.is_a?(Reference)
        return normalize_mapping(
          "repository" => raw.repository,
          "ref" => raw.ref,
          "path" => raw.path
        )
      end
      return normalize_mapping(raw) if raw.is_a?(Hash)
      normalize_url(raw)
    end

    def normalize_mapping(raw)
      unless raw.keys.all? { |key| key.is_a?(String) }
        raise Invalid, "github_markdown mapping keys must be strings"
      end
      unknown = raw.keys - %w[repository ref path]
      raise Invalid, "unknown github_markdown setting #{unknown.sort.first.inspect}" unless unknown.empty?
      missing = %w[repository ref path].reject { |key| raw.key?(key) }
      raise Invalid, "github_markdown requires #{missing.join(', ')}" unless missing.empty?

      Reference.new(
        repository: normalize_repository(raw["repository"]),
        ref: normalize_ref(raw["ref"], single_segment: false),
        path: normalize_path(raw["path"])
      )
    end

    def normalize_url(raw)
      unless raw.is_a?(String) && raw.valid_encoding? && !raw.match?(ENCODED_SEPARATOR)
        raise Invalid, "github_markdown URL shorthand requires a single-segment ref"
      end
      uri = URI.parse(raw)
      parts = uri.path.split("/", -1)
      unless uri.scheme&.casecmp("https")&.zero? && uri.host&.casecmp("github.com")&.zero? &&
          uri.port == 443 && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? &&
          parts.shift == "" && parts.length >= 5 && parts[2] == "blob"
        raise Invalid, "github_markdown must be a public github.com blob URL"
      end

      Reference.new(
        repository: normalize_repository(parts[0, 2].map { |part| URI.decode_uri_component(part) }.join("/")),
        ref: normalize_ref(URI.decode_uri_component(parts[3]), single_segment: true),
        path: normalize_path(parts[4..].map { |part| URI.decode_uri_component(part) }.join("/"))
      )
    rescue URI::InvalidURIError, URI::InvalidComponentError, TypeError
      raise Invalid, "github_markdown must be a public github.com blob URL"
    end

    def normalize_repository(raw)
      unless raw.is_a?(String) && raw.valid_encoding?
        raise Invalid, "github_markdown.repository must be owner/repository"
      end
      parts = raw.unicode_normalize(:nfc).split("/", -1)
      unless parts.length == 2 && parts.all? { |part| part.match?(REPOSITORY_COMPONENT) }
        raise Invalid, "github_markdown.repository must be owner/repository"
      end
      parts.join("/").downcase
    end

    def normalize_ref(raw, single_segment:)
      unless raw.is_a?(String) && raw.valid_encoding?
        raise Invalid, "github_markdown.ref must be a safe Git ref"
      end
      ref = raw.unicode_normalize(:nfc)
      components = ref.split("/", -1)
      invalid = ref.empty? || ref.bytesize > 255 || ref.match?(INVALID_REF_CHARACTER) ||
        ref == "@" || ref.include?("..") || ref.include?("@{") ||
        components.any? { |part| part.empty? || part.start_with?(".") || part.end_with?(".", ".lock") } ||
        (single_segment && components.length != 1)
      if invalid
        suffix = single_segment ? " containing a single-segment ref" : " containing a safe Git ref"
        raise Invalid, "github_markdown requires#{suffix}"
      end
      ref
    end

    def normalize_path(raw)
      unless raw.is_a?(String) && raw.valid_encoding?
        raise Invalid, "github_markdown.path must be a safe relative Markdown path"
      end
      path = raw.unicode_normalize(:nfc)
      parts = path.split("/", -1)
      invalid = path.empty? || path.bytesize > 1024 || path.start_with?("/") || path.include?("\\") ||
        parts.any? { |part| part.empty? || part == "." || part == ".." || part.match?(/[\x00-\x1f\x7f]/) }
      extension = File.extname(path).downcase
      unless !invalid && MARKDOWN_EXTENSIONS.include?(extension)
        raise Invalid, "github_markdown.path must be a safe relative .md or .markdown path"
      end
      path
    end

    def source_url(repository, commit, path)
      encoded_path = path.split("/").map { |part| URI.encode_uri_component(part) }.join("/")
      "https://github.com/#{repository}/blob/#{commit}/#{encoded_path}"
    end

    def normalize_markdown(raw, reference)
      unless raw.is_a?(String)
        raise FetchError, "GitHub Markdown content is not a byte string for #{reference.repository}/#{reference.path}"
      end
      if raw.bytesize > MAX_FILE_BYTES
        raise FetchError, "GitHub Markdown file exceeds the 1 MiB limit: #{reference.repository}/#{reference.path}"
      end

      markdown = raw.dup.force_encoding(Encoding::UTF_8)
      unless markdown.valid_encoding?
        raise FetchError, "GitHub Markdown file is not valid UTF-8: #{reference.repository}/#{reference.path}"
      end
      unless OutputText.valid?(markdown)
        raise FetchError, "GitHub Markdown file contains a character forbidden by XML 1.0: #{reference.repository}/#{reference.path}"
      end
      markdown
    end
  end
end
