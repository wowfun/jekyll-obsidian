# frozen_string_literal: true

require "psych"
require "test_helper"

class ConfigOwnershipTest < Minitest::Test
  WEBSITE_ROOT = File.expand_path("..", __dir__)

  def test_raw_html_example_is_owned_by_the_example_overlay_not_distributed_defaults
    defaults = yaml(File.join(WEBSITE_ROOT, "_config.yml"))
    example = yaml(File.join(WEBSITE_ROOT, "scripts", "example-config.yml"))

    refute defaults.fetch("website").key?("html")
    assert_equal(
      { "slides/jekyll-obsidian" => "/slides/jekyll-obsidian/" },
      example.dig("website", "html")
    )
  end

  private

  def yaml(path)
    Psych.safe_load(File.read(path), permitted_classes: [], aliases: true)
  end
end
