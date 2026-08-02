# frozen_string_literal: true

require_relative "workspace_layout"

module JekyllObsidian
  module DevWatch
    module_function

    def rebuild_and_refresh(
      batch:, build_assets:, site_dir:, destination:, layout:, content_listener:, changes:,
      build_runner:, layout_resolver:, listener_starter:, output: $stdout, warnings: $stderr
    )
      output.puts("Source changed. Rebuilding#{build_assets ? " assets and site" : " site"}...")
      build_runner.call(build_assets)
      return [layout, content_listener] unless batch.include?([:site, "_config.yml"])

      begin
        next_layout = layout_resolver.call(site_dir, destination)
      rescue WorkspaceLayout::Invalid => exception
        warnings.puts("Cannot watch configured content: #{exception.message}")
        return [layout, content_listener]
      end
      return [layout, content_listener] if next_layout.source_root == layout.source_root

      next_listener = listener_starter.call(next_layout.source_root, changes)
      content_listener.stop
      output.puts("Now watching #{next_layout.source}/ for published content.")
      [next_layout, next_listener]
    end
  end
end
