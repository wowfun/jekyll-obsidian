# frozen_string_literal: true

require "test_helper"

class TestWarningFilterTest < Minitest::Test
  def test_only_known_test_runtime_warnings_are_suppressed
    liquid_warning = <<~WARNING
      /tmp/vendor/bundle/ruby/4.0.0/gems/liquid-4.0.4/lib/liquid/parser.rb:72: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
    WARNING
    kramdown_warning = <<~WARNING
      /tmp/vendor/bundle/ruby/4.0.0/gems/kramdown-2.5.2/lib/kramdown/parser/base.rb:60: warning: character class has duplicated range: /[\s\p{Z}]+/
    WARNING
    forwardable_warning = <<~WARNING
      /opt/ruby/4.0.0/lib/ruby/4.0.0/forwardable.rb:228: warning: method redefined; discarding old ext
    WARNING

    assert JekyllObsidianTestWarningFilter.suppress?(liquid_warning)
    assert JekyllObsidianTestWarningFilter.suppress?(kramdown_warning)
    assert JekyllObsidianTestWarningFilter.suppress?(forwardable_warning)
    refute JekyllObsidianTestWarningFilter.suppress?(liquid_warning.sub("liquid-4.0.4", "liquid-4.0.5"))
    refute JekyllObsidianTestWarningFilter.suppress?(liquid_warning.sub("/gems/liquid-4.0.4/", "/lib/"))
    refute JekyllObsidianTestWarningFilter.suppress?(forwardable_warning.sub("old ext", "old path"))
    refute JekyllObsidianTestWarningFilter.suppress?("project.rb:1: warning: unexpected behavior\n")
  end
end
