# frozen_string_literal: true

require_relative "jekyll_obsidian/value_objects"
require_relative "jekyll_obsidian/url_builder"
require_relative "jekyll_obsidian/media_policy"
require_relative "jekyll_obsidian/front_matter"
require_relative "jekyll_obsidian/ofm_scanner"
require_relative "jekyll_obsidian/built_in_themes"
require_relative "jekyll_obsidian/vault_compiler"
require_relative "jekyll_obsidian/localized_compiler"

module JekyllObsidian
  VERSION = "1.0.0"
end
