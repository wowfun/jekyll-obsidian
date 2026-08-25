# frozen_string_literal: true

require "jekyll"
require_relative "workspace_layout"

module JekyllObsidian
  module DevWatch
    MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

    module_function

    def configured_source(site_dir:, configuration_paths:)
      config = Jekyll.configuration(
        "source" => site_dir,
        "config" => configuration_paths,
        "quiet" => true
      )
      website = config["website"]
      return WorkspaceLayout::DEFAULT_SOURCE unless website.is_a?(Hash) && website.key?("source")

      website["source"]
    rescue LoadError, Psych::Exception, SystemCallError
      WorkspaceLayout::DEFAULT_SOURCE
    end

    def build_with_status(
      initial:, build_assets:, build_runner:, output: $stdout, warnings: $stderr, clock: MONOTONIC_CLOCK
    )
      scope = build_assets ? "assets and site" : "site"
      output.puts(initial ? "Building #{scope}..." : "Source changed. Rebuilding #{scope}...")
      started_at = clock.call
      succeeded = build_runner.call(build_assets)
      elapsed = clock.call - started_at
      if succeeded
        output.puts(format("%s %s in %.2fs.", initial ? "Built" : "Rebuilt", scope, elapsed))
      elsif initial
        warnings.puts(format(
          "Initial build failed after %.2fs. The watcher will stay active so you can repair the source.",
          elapsed
        ))
      else
        warnings.puts(format(
          "Build failed after %.2fs. Continuing to serve the last successful site.",
          elapsed
        ))
      end
      succeeded
    end

    def rebuild_and_refresh(
      batch:, build_assets:, site_dir:, destination:, layout:, content_listener:, changes:,
      build_runner:, layout_resolver:, listener_starter:, output: $stdout, warnings: $stderr,
      clock: MONOTONIC_CLOCK
    )
      build_with_status(
        initial: false,
        build_assets:,
        build_runner:,
        output:,
        warnings:,
        clock:
      )
      config_changed = batch.include?([:site, "_config.yml"]) ||
        batch.any? { |kind, _path| kind == :host_config }
      return [layout, content_listener] unless config_changed

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
