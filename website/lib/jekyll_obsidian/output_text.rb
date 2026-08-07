# frozen_string_literal: true

module JekyllObsidian
  module OutputText
    INVALID_CHARACTER = /[^\u{9}\u{A}\u{D}\u{20}-\u{D7FF}\u{E000}-\u{FFFD}\u{10000}-\u{10FFFF}]/u

    module_function

    def valid?(value)
      value.is_a?(String) && value.valid_encoding? && !value.match?(INVALID_CHARACTER)
    end
  end
end
