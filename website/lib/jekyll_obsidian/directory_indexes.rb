# frozen_string_literal: true

module JekyllObsidian
  # Selects the one physical note path that may act as each directory's index.
  # Publication is deliberately applied later: a private index.md still owns
  # the physical slot and therefore prevents README.md from taking it over.
  module DirectoryIndexes
    PRIMARY_BASENAME = "index.md"
    FALLBACK_BASENAME = "README.md"

    module_function

    def resolve(note_paths)
      paths = Array(note_paths).map(&:to_s)
      selected = {}

      paths.each do |path|
        selected[File.dirname(path)] = path if File.basename(path) == PRIMARY_BASENAME
      end
      paths.each do |path|
        directory = File.dirname(path)
        if File.basename(path) == FALLBACK_BASENAME && !selected.key?(directory)
          selected[directory] = path
        end
      end

      DeepFreeze.call(selected)
    end
  end
end
