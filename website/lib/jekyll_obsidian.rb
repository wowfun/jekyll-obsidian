# frozen_string_literal: true

require_relative "jekyll_obsidian/value_objects"
require_relative "jekyll_obsidian/url_builder"
require_relative "jekyll_obsidian/destination_registry"
require_relative "jekyll_obsidian/media_policy"
require_relative "jekyll_obsidian/external_media"
require_relative "jekyll_obsidian/front_matter"
require_relative "jekyll_obsidian/content_policy"
require_relative "jekyll_obsidian/ofm_scanner"
require_relative "jekyll_obsidian/published_markdown"
require_relative "jekyll_obsidian/site_navigation"
require_relative "jekyll_obsidian/built_in_themes"
require_relative "jekyll_obsidian/vault_compiler"
require_relative "jekyll_obsidian/localized_compiler"

module JekyllObsidian
  VERSION = "2026.8.6"
end
