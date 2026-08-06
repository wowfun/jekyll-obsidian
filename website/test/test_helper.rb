# frozen_string_literal: true

require "json"
require "minitest/autorun"
require_relative "support/warning_filter"
require "jekyll_obsidian"

module CompilerTestHelpers
  DEFAULT_CONFIG = {
    title: "Test Garden",
    description: "A deterministic fixture",
    lang: "en",
    url: "https://example.test",
    baseurl: "",
    source: "vault",
    syntax_profile: "ofm@1",
    repository: "example/garden",
    edit_branch: "main",
    environment: "production",
    i18n: nil,
    comments: nil
  }.freeze

  def note(path, body, first_committed_at: nil)
    JekyllObsidian::SnapshotEntry.new(
      path: path,
      bytes: body,
      kind: :note,
      media_type: "text/markdown",
      size: body.bytesize,
      first_committed_at: first_committed_at
    )
  end

  def attachment(path, bytes = "binary", media_type: "application/octet-stream")
    JekyllObsidian::SnapshotEntry.new(
      path: path,
      bytes: bytes,
      kind: :attachment,
      media_type: media_type,
      size: bytes.bytesize
    )
  end

  def locale_manifest(path, body)
    JekyllObsidian::SnapshotEntry.new(
      path: path,
      bytes: body,
      kind: :locale_manifest,
      media_type: "application/yaml",
      size: body.bytesize
    )
  end

  def compile(*entries, **overrides)
    snapshot = JekyllObsidian::Snapshot.new(entries: entries)
    config = JekyllObsidian::BuildConfig.new(**DEFAULT_CONFIG.merge(overrides))
    request = JekyllObsidian::BuildRequest.new(snapshot: snapshot, config: config)
    JekyllObsidian::VaultCompiler.compile(request)
  end

  def page(result, route)
    result.pages.find { |candidate| candidate.route == route }
  end

  def generated_json(result, route)
    output = result.generated_files.find { |candidate| candidate.route == route }
    refute_nil output, "expected generated file #{route}"
    JSON.parse(output.content)
  end
end

class Minitest::Test
  include CompilerTestHelpers
end
