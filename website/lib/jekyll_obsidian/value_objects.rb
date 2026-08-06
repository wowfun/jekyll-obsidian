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

  module ImmutableRecord
    class << self
      def define(*members)
        Class.new(Data.define(*members)) do
          define_method(:initialize) do |**values|
            unknown = values.keys - members
            raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

            attributes = members.to_h { |member| [member, values.fetch(member, nil)] }
            attributes.each_value { |value| JekyllObsidian::DeepFreeze.call(value) }
            super(**attributes)
          end
        end
      end
    end
  end

  SnapshotEntry = ImmutableRecord.define(
    :path,
    :bytes,
    :kind,
    :media_type,
    :size,
    :device,
    :inode,
    :mtime_ns,
    :first_committed_at
  )

  Snapshot = ImmutableRecord.define(:entries)

  BuildConfig = ImmutableRecord.define(
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
    :features,
    :i18n,
    :comments,
    :contacts,
    :navigation
  )

  BuildRequest = ImmutableRecord.define(:snapshot, :config)
  SourceSpan = ImmutableRecord.define(:start_line, :start_column, :end_line, :end_column)
  Diagnostic = ImmutableRecord.define(:severity, :code, :message, :path, :span)
  Relation = ImmutableRecord.define(:source_id, :target_id, :kind, :fragment, :source_span)
  PageOutput = ImmutableRecord.define(:route, :content, :data)
  GeneratedFile = ImmutableRecord.define(:route, :content, :media_type)
  CopiedAsset = ImmutableRecord.define(:source_path, :route, :media_type, :size, :device, :inode, :mtime_ns)
  NoteOutput = ImmutableRecord.define(:id, :title, :route, :properties)
  ContentSecurityNeeds = ImmutableRecord.define(:media_sources, :frame_sources, :script_sources)

  # Internal, immutable hand-off between the OFM compiler and the built-in
  # theme presenters. Keeping rendered note content and all relation-derived
  # cards here prevents presentation code from reaching back into MutableNote
  # or repeating Markdown/relation work.
  PublishedNote = ImmutableRecord.define(
    :id,
    :title,
    :route,
    :content,
    :properties,
    :markdown_source,
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
    :content_security,
    :image_url,
    :source_links,
    :topics,
    :links,
    :backlinks,
    :embedded_by
  )

  PublishedSiteModel = ImmutableRecord.define(
    :notes,
    :notes_by_id,
    :relations,
    :graph_edges,
    :graph_degrees
  )

  CommentsConfig = ImmutableRecord.define(
    :enabled,
    :configured,
    :repository,
    :repository_id,
    :category,
    :category_id,
    :language,
    :load
  )

  EffectiveThemeConfig = ImmutableRecord.define(
    :theme,
    :features,
    :content,
    :comments,
    :contacts,
    :navigation,
    :site,
    :url_builder
  )

  ThemeOutput = ImmutableRecord.define(
    :pages,
    :artifacts,
    :shared_files,
    :site_data,
    :feed_note_ids,
    :reserved_namespaces
  )

  BuildSuccessBase = ImmutableRecord.define(
    :pages,
    :generated_files,
    :copied_assets,
    :diagnostics,
    :relations,
    :notes,
    :theme,
    :features,
    :site_data
  )

  class BuildSuccess < BuildSuccessBase
    def success?
      true
    end
  end

  BuildFailureBase = ImmutableRecord.define(:diagnostics)

  class BuildFailure < BuildFailureBase
    def success?
      false
    end
  end
end
