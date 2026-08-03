# frozen_string_literal: true

module JekyllObsidianTestWarningFilter
  KNOWN_TEST_RUNTIME_WARNINGS = [
    [
      "/gems/liquid-4.0.4/lib/liquid/",
      "warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)"
    ],
    [
      "/gems/kramdown-2.5.2/lib/kramdown/parser/base.rb:60:",
      "warning: character class has duplicated range:"
    ],
    [
      "/lib/ruby/4.0.0/forwardable.rb:228:",
      "warning: method redefined; discarding old ext"
    ]
  ].freeze

  module WarningHook
    def warn(message, ...)
      return if JekyllObsidianTestWarningFilter.suppress?(message)

      super
    end
  end

  module_function

  def suppress?(message)
    text = message.to_s
    KNOWN_TEST_RUNTIME_WARNINGS.any? do |path, warning|
      text.include?(path) && text.include?(warning)
    end
  end

  def install!
    Warning.singleton_class.prepend(WarningHook) unless Warning.singleton_class < WarningHook
  end
end

JekyllObsidianTestWarningFilter.install!
