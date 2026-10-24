# frozen_string_literal: true

module JekyllObsidian
  # Owns the impure boundary for remote build inputs. VaultCompiler remains a
  # deterministic projection over one immutable snapshot.
  class SiteCompilation
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
      compiler = VaultCompiler.prepare(@request)
      diagnostics = compiler.preparation_diagnostics
      return failure(diagnostics) if diagnostics.any? { |item| item.severity == :error }

      references = compiler.remote_references.sort_by { |path, _| path.b }.to_h
      if references.empty?
        GitHubMarkdown.materialize([], manifest: @manifest) unless @manifest.nil?
        return compiler.compile
      end

      documents = GitHubMarkdown.materialize(
        references.values,
        transport: @transport,
        cache_root: @cache_root,
        manifest: @manifest
      )
      compiler.load_external_documents(references.keys.zip(documents).to_h)
      result = compiler.compile
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

    def diagnostic(code, message, path = nil)
      Diagnostic.new(severity: :error, code: code, message: message, path: path, span: nil)
    end

    def failure(diagnostics)
      BuildFailure.new(diagnostics: Diagnostics.normalize(diagnostics))
    end
  end
end
