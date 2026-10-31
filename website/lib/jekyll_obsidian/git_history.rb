# frozen_string_literal: true

require "open3"
require "set"

module JekyllObsidian
  # First reachable commit for each current path, without following renames.
  # Only a linear descendant can reuse unchanged paths; merges and rewrites
  # may introduce older history even when the resulting source tree is equal.
  module GitHistory
    module_function

    def read(root:, source:, head:, cached_head: nil, cached_times: nil)
      prefix = "#{source}/"
      current = {}
      return unless stream(root, "ls-tree", "-r", "--name-only", "-z", head, "--", source) do |path|
        current[path.delete_prefix(prefix).unicode_normalize(:nfc)] = path if path.start_with?(prefix)
      end

      incremental = cached_times && cached_head&.match?(/\A[0-9a-f]{40,64}\z/) &&
        success?(root, "merge-base", "--is-ancestor", cached_head, head) &&
        output(root, "rev-list", "--count", "--merges", "#{cached_head}..#{head}") == "0"
      result = incremental ? cached_times.select { |path, _time| current.key?(path) } : {}
      if incremental
        changed = Set.new(current.keys - result.keys)
        return unless stream(root, "diff", "--name-only", "--no-renames", "-z", cached_head, head, "--", source) do |path|
          changed << path.delete_prefix(prefix).unicode_normalize(:nfc) if path.start_with?(prefix)
        end
        paths = changed.filter_map { |path| current[path] }
        return result if paths.empty?

        changed.each { |path| result.delete(path) }
        batches = paths.each_slice(32)
      else
        batches = [[source]]
      end
      batches.each do |paths|
        current_time = nil
        ok = stream(root, "log", "--full-history", "--no-renames", "--format=%x1e%aI", "--name-only", "-z", head, "--", *paths) do |record|
          # Git inserts one separator newline before the first path per commit.
          record = record.delete_prefix("\n")
          if record.start_with?("\x1e")
            current_time = record.delete_prefix("\x1e").sub(/\+00:00\z/, "Z")
          elsif current_time && record.start_with?(prefix)
            relative = record.delete_prefix(prefix).unicode_normalize(:nfc)
            result[relative] = current_time if current.key?(relative)
          end
        end
        return unless ok
      end
      result
    end

    def stream(root, *arguments)
      Open3.popen2("git", "-C", root, *arguments, err: File::NULL) do |input, output, wait|
        input.close
        output.set_encoding(Encoding::UTF_8)
        output.each_line("\0") { |record| yield record.delete_suffix("\0") }
        wait.value.success?
      end
    end

    def success?(root, *arguments)
      _stdout, _stderr, status = Open3.capture3("git", "-C", root, *arguments)
      status.success?
    end

    def output(root, *arguments)
      stdout, _stderr, status = Open3.capture3("git", "-C", root, *arguments)
      stdout.strip if status.success?
    end
  end
end
