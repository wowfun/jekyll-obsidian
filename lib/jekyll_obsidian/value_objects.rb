# frozen_string_literal: true

module JekyllObsidian
  module DeepFreeze
    module_function

    def call(value, seen = {})
      return value if value.nil? || value == true || value == false || value.is_a?(Numeric) || value.is_a?(Symbol)
      return value if seen[value.object_id]

      seen[value.object_id] = true
      case value
      when String
        value.freeze
      when Array
        value.each { |item| call(item, seen) }
        value.freeze
      when Hash
        value.each { |key, item| call(key, seen); call(item, seen) }
        value.freeze
      when Struct
        value.each { |item| call(item, seen) }
        value.freeze
      else
        value.freeze
      end
      value
    end
  end

  class ImmutableStruct < Struct
    class << self
      def define(*members)
        Class.new(Struct.new(*members, keyword_init: true)) do
          define_method(:initialize) do |**values|
            super(**values)
            JekyllObsidian::DeepFreeze.call(self)
          end
        end
      end
    end
  end

  SnapshotEntry = ImmutableStruct.define(
    :path,
    :bytes,
    :kind,
    :media_type,
    :size,
    :first_committed_at,
    :last_committed_at
  )

  Snapshot = ImmutableStruct.define(:entries)

  BuildConfig = ImmutableStruct.define(
    :title,
    :description,
    :lang,
    :url,
    :baseurl,
    :source,
    :syntax_profile,
    :repository,
    :edit_branch,
    :environment,
    :theme,
    :content,
    :features
  )

  BuildRequest = ImmutableStruct.define(:snapshot, :config)
  SourceSpan = ImmutableStruct.define(:start_line, :start_column, :end_line, :end_column)
  Diagnostic = ImmutableStruct.define(:severity, :code, :message, :path, :span)
  Relation = ImmutableStruct.define(:source_id, :target_id, :kind, :fragment, :source_span)
  PageOutput = ImmutableStruct.define(:route, :content, :data)
  GeneratedFile = ImmutableStruct.define(:route, :content, :media_type)
  CopiedAsset = ImmutableStruct.define(:source_path, :route, :media_type, :size)
  NoteOutput = ImmutableStruct.define(:id, :title, :route, :properties)

  # Internal, immutable hand-off between the OFM compiler and the built-in
  # theme presenters. Keeping rendered note content and all relation-derived
  # cards here prevents presentation code from reaching back into MutableNote
  # or repeating Markdown/relation work.
  PublishedNote = ImmutableStruct.define(
    :id,
    :title,
    :route,
    :content,
    :properties,
    :authored_text,
    :preview,
    :outline,
    :updated,
    :created,
    :content_type,
    :published_at,
    :nav_order,
    :nav_exclude,
    :has_h1,
    :feature_flags,
    :base_data,
    :links,
    :backlinks,
    :embedded_by
  )

  PublishedSiteModel = ImmutableStruct.define(
    :notes,
    :notes_by_id,
    :relations,
    :graph_edges
  )

  EffectiveThemeConfig = ImmutableStruct.define(
    :theme,
    :features,
    :content,
    :site,
    :url_builder
  )

  ThemeOutput = ImmutableStruct.define(
    :pages,
    :artifacts,
    :feed_note_ids,
    :reserved_namespaces
  )

  BuildResultBase = ImmutableStruct.define(
    :pages,
    :generated_files,
    :copied_assets,
    :diagnostics,
    :relations,
    :notes,
    :theme,
    :features
  )

  class BuildResult < BuildResultBase
    def success?
      diagnostics.none? { |diagnostic| diagnostic.severity == :error }
    end
  end
end
