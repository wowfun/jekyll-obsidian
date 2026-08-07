# frozen_string_literal: true

require "set"

module JekyllObsidian
  # Owns the impure boundary for remote build inputs. VaultCompiler remains a
  # deterministic projection over one immutable snapshot.
  class SiteCompilation
    TRANSLATION_PREFIX = "_translations/"

    PlannedReference = ImmutableRecord.define(:physical_path, :logical_path, :reference)

    def self.compile(request, transport: nil, cache_root: nil, manifest: nil)
      new(request, transport:, cache_root:, manifest:).compile
    end

    def initialize(request, transport:, cache_root:, manifest:)
      @request = request
      @transport = transport
      @cache_root = cache_root
      @manifest = manifest
    end

    def compile
      baseline = VaultCompiler.compile(@request)
      return baseline unless baseline.success?

      plan, diagnostics = build_plan(baseline)
      return failure(baseline.diagnostics + diagnostics) unless diagnostics.empty?
      if plan.empty?
        GitHubMarkdown.materialize([], manifest: @manifest) unless @manifest.nil?
        return baseline
      end

      documents = GitHubMarkdown.materialize(
        plan.map(&:reference),
        transport: @transport,
        cache_root: @cache_root,
        manifest: @manifest
      )
      documents_by_path = plan.each_with_index.to_h do |item, index|
        [item.physical_path, documents.fetch(index)]
      end
      snapshot = Snapshot.new(entries: @request.snapshot.entries.map do |entry|
        document = documents_by_path[entry.path.to_s]
        document ? SnapshotEntry.new(**entry.to_h.merge(external_document: document)) : entry
      end)
      final_request = BuildRequest.new(snapshot: snapshot, config: @request.config)
      result = VaultCompiler.compile(final_request)
      return result unless result.success?

      BuildSuccess.new(**result.to_h.merge(
        github_markdown_manifest: GitHubMarkdown.dump_manifest(documents)
      ))
    rescue GitHubMarkdown::ManifestError => exception
      failure([diagnostic("github_markdown_manifest_invalid", exception.message)])
    rescue GitHubMarkdown::Error => exception
      failure([diagnostic("github_markdown_fetch_failed", exception.message)])
    end

    private

    def build_plan(result)
      published = result.notes.map(&:id).to_set
      portfolio_path = configured_portfolio_path
      locales = Array(result.site_data.dig("website_i18n", "locales")).map { |item| item.fetch("code") }
      default_locale = @request.config.lang.to_s
      plan = []
      diagnostics = []

      @request.snapshot.entries.sort_by { |entry| entry.path.to_s.b }.each do |entry|
        next unless entry.kind.to_sym == :note

        physical_path = entry.path.to_s
        locale, logical_path = translated_path(physical_path, locales, default_locale)
        next if physical_path.start_with?(TRANSLATION_PREFIX) && locale.nil?

        parsed = FrontMatter.parse(physical_path, entry.bytes.to_s)
        reference = parsed.properties["github_markdown"]
        next unless reference
        next if parsed.properties["publish"] == false
        next unless published_note?(published, logical_path, locale)

        unless logical_path.start_with?("#{portfolio_path}/") && logical_path != "#{portfolio_path}/index.md"
          diagnostics << diagnostic(
            "github_markdown_scope",
            "github_markdown is only supported by project wrappers below the configured portfolio path",
            physical_path
          )
          next
        end
        unless parsed.body.strip.empty?
          diagnostics << diagnostic(
            "github_markdown_body_conflict",
            "a github_markdown project wrapper must have an empty local body",
            physical_path
          )
          next
        end

        plan << PlannedReference.new(
          physical_path: physical_path,
          logical_path: logical_path,
          reference: reference
        )
      end
      [plan.freeze, diagnostics.freeze]
    end

    def configured_portfolio_path
      navigation = @request.config.navigation
      value = navigation.is_a?(Hash) ? navigation.dig("portfolio", "path") : nil
      (value || "portfolio").to_s.unicode_normalize(:nfc)
    end

    def translated_path(path, locales, default_locale)
      return [nil, path] unless path.start_with?(TRANSLATION_PREFIX)

      suffix = path.delete_prefix(TRANSLATION_PREFIX)
      locale, logical = suffix.split("/", 2)
      return [nil, nil] unless logical && locale != default_locale && locales.include?(locale)

      [locale, logical]
    end

    def published_note?(published, logical_path, locale)
      return published.include?(logical_path) unless locale

      published.include?(logical_path) && published.include?("#{locale}:#{logical_path}")
    end

    def diagnostic(code, message, path = nil)
      Diagnostic.new(severity: :error, code: code, message: message, path: path, span: nil)
    end

    def failure(diagnostics)
      BuildFailure.new(diagnostics: diagnostics.sort_by do |item|
        [item.path.to_s, item.code.to_s, item.message.to_s]
      end.freeze)
    end
  end
end
