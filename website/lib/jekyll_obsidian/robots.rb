# frozen_string_literal: true

module JekyllObsidian
  module Robots
    module_function

    def noindex?(directives)
      directives.to_s.downcase.split(/[\s,]+/).include?("noindex")
    end
  end
end
