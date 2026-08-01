# frozen_string_literal: true

require "minitest/autorun"
require "jekyll_obsidian"

class PublicIdentityTest < Minitest::Test
  def test_exposes_only_the_neutral_project_namespace
    assert defined?(JekyllObsidian::VaultCompiler)
    refute Object.const_defined?(:JekyllObsidianGarden)
  end
end
