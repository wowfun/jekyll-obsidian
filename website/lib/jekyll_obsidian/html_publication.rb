# frozen_string_literal: true

module JekyllObsidian
  # Resolves explicitly authorized, source-backed HTML documents without
  # exposing their routing and publication rules to themes or the Jekyll
  # adapter.
  module HtmlPublication
    MANIFEST_ROUTE = RawHtmlManifest::ROUTE
    Resolution = ImmutableRecord.define(
      :projected_files,
      :routes_by_source,
      :document_sources,
      :documents,
      :files,
      :diagnostics
    )

    module_function

    def resolve(snapshot:, mappings:, url_builder:)
      return empty_resolution if mappings.nil? || mappings == {}
      unless mappings.is_a?(Hash) && mappings.keys.all? { |key| key.is_a?(String) }
        return failure("invalid_html_config", "website.html must be a mapping from source paths to public routes")
      end

      entries = Array(snapshot.entries).to_h { |entry| [entry.path.to_s, entry] }
      projected_files = []
      routes_by_source = {}
      document_sources = []
      documents = []
      diagnostics = []
      claimed_sources = []

      mappings.sort_by { |source, _route| source.to_s.b }.each do |source, route|
        unless valid_source?(source)
          diagnostics << diagnostic("invalid_html_source", "HTML sources must be normalized vault-relative POSIX paths", source)
          next
        end
        overlapping_source = claimed_sources.find { |claimed| paths_overlap?(claimed, source) }
        if overlapping_source
            diagnostics << diagnostic(
              "overlapping_html_source",
              "HTML source overlaps the existing declaration #{overlapping_source.inspect} under NFC/case-folding",
              source
            )
          next
        end
        claimed_sources << source
        entry = entries[source]
        if entry
          unless entry.kind.to_sym == :attachment && source.end_with?(".html")
            diagnostics << diagnostic("missing_html_source", "standalone HTML source must be an existing .html file", source)
            next
          end
          normalized_route = normalize_file_route(route, url_builder)
          unless normalized_route
            diagnostics << diagnostic("invalid_html_route", "a standalone HTML file must map to a safe root-relative .html route", source)
            next
          end

          projected_files << projected_file(entry, normalized_route, "text/html")
          routes_by_source[source] = normalized_route
          document_sources << source
          documents << { "route" => normalized_route, "output" => normalized_route }
          next
        end

        prefix = "#{source}/"
        bundle_entries = entries.values.select { |candidate| candidate.path.to_s.start_with?(prefix) }
        index = entries["#{prefix}index.html"]
        unless index && index.kind.to_sym == :attachment
          diagnostics << diagnostic("missing_html_source", "HTML bundle source must contain an exact index.html", source)
          next
        end
        normalized_route = normalize_directory_route(route, url_builder)
        unless normalized_route
          diagnostics << diagnostic("invalid_html_route", "an HTML bundle must map to a safe root-relative directory route", source)
          next
        end

        bundle_entries.select { |candidate| candidate.kind.to_sym == :attachment }
          .sort_by { |candidate| candidate.path.to_s.b }
          .each do |candidate|
            relative = candidate.path.to_s.delete_prefix(prefix)
            output_route = join_route(normalized_route, relative, url_builder)
            unless output_route
              diagnostics << diagnostic(
                "invalid_html_source",
                "HTML bundle member path cannot be projected to a safe public route",
                candidate.path.to_s
              )
              next
            end
            media_type = relative.end_with?(".html") ? "text/html" : candidate.media_type
            projected_files << projected_file(candidate, output_route, media_type)
            routes_by_source[candidate.path.to_s] = document_route(output_route)
            if relative.end_with?(".html")
              document_sources << candidate.path.to_s
              documents << { "route" => document_route(output_route), "output" => output_route }
            end
          end
      end

      Resolution.new(
        projected_files: projected_files.sort_by(&:route),
        routes_by_source: routes_by_source.sort.to_h,
        document_sources: document_sources.sort,
        documents: documents.sort_by { |document| document.fetch("route") },
        files: projected_files.map(&:route).sort,
        diagnostics: diagnostics.freeze
      )
    end

    def manifest(resolution)
      return nil if resolution.documents.empty?

      GeneratedFile.new(
        route: MANIFEST_ROUTE,
        content: RawHtmlManifest.generate(documents: resolution.documents, files: resolution.files),
        media_type: "application/json"
      )
    end

    def empty_resolution
      Resolution.new(projected_files: [], routes_by_source: {}, document_sources: [], documents: [], files: [], diagnostics: [])
    end

    def failure(code, message)
      Resolution.new(
        projected_files: [],
        routes_by_source: {},
        document_sources: [],
        documents: [],
        files: [],
        diagnostics: [diagnostic(code, message)]
      )
    end

    def valid_source?(source)
      return false if source.empty? || source == "." || source.start_with?("/", "\\") || source.include?("\\")
      return false if source != source.unicode_normalize(:nfc)
      return false if source == "_translations" || source.start_with?("_translations/")

      source.split("/", -1).none? { |segment| segment.empty? || segment == "." || segment == ".." }
    rescue EncodingError
      false
    end

    def normalize_file_route(route, url_builder)
      normalized = url_builder.validate_file_route(route, extension: ".html")
      normalized if normalized && allowed_route?(normalized, url_builder)
    end

    def normalize_directory_route(route, url_builder)
      normalized = url_builder.validate_permalink(route)
      normalized if normalized && normalized != "/" && allowed_route?(normalized, url_builder)
    end

    def allowed_route?(route, url_builder)
      key = url_builder.collision_key(route)
      return false if key.start_with?("/assets/website/", "/assets/vault/")

      baseurl = url_builder.baseurl
      baseurl.empty? || !key.start_with?("#{url_builder.collision_key(baseurl)}")
    rescue ArgumentError, EncodingError
      false
    end

    def projected_file(entry, route, media_type)
      ProjectedFile.new(
        source_path: entry.path,
        route: route,
        media_type: media_type,
        size: entry.size,
        device: entry.device,
        inode: entry.inode,
        mtime_ns: entry.mtime_ns
      )
    end

    def paths_overlap?(first, second)
      left = first.unicode_normalize(:nfc).downcase(:fold)
      right = second.unicode_normalize(:nfc).downcase(:fold)
      left == right || left.start_with?("#{right}/") || right.start_with?("#{left}/")
    end

    def join_route(root, relative, url_builder)
      encoded = relative.unicode_normalize(:nfc).split("/").map { |segment| URI.encode_uri_component(segment) }
      route = "#{root}#{encoded.join('/')}"
      url_builder.collision_key(route)
      route
    rescue ArgumentError, EncodingError, URI::InvalidURIError
      nil
    end

    def document_route(output_route)
      return output_route unless output_route.end_with?("/index.html")

      output_route.delete_suffix("index.html")
    end

    def diagnostic(code, message, path = nil)
      Diagnostic.new(severity: :error, code: code, message: message, path: path, span: nil)
    end
  end
end
