# frozen_string_literal: true

require "json"

module JekyllObsidian
  # Owns the serialized contract shared by the compiler, production audit, and
  # URL verifier. Filesystem safety remains the responsibility of each
  # consumer after this structural validation succeeds.
  module RawHtmlManifest
    PATH = "assets/website/raw-html.v1.json"
    ROUTE = "/#{PATH}"
    SCHEMA_VERSION = 1
    KEYS = %w[documents files schema_version].freeze
    DOCUMENT_KEYS = %w[output route].freeze

    class Invalid < StandardError; end

    module_function

    def generate(documents:, files:)
      # Destination preflight owns duplicate-route diagnostics and runs after
      # the manifest object is assembled. Keep generation total so collisions
      # remain structured compiler failures; readers still validate strictly.
      payload = {
        "schema_version" => SCHEMA_VERSION,
        "documents" => documents,
        "files" => files
      }
      "#{JSON.generate(payload)}\n"
    end

    def parse(content)
      payload = JSON.parse(content)
      validate!(payload)
      payload
    rescue JSON::ParserError => exception
      raise Invalid, "invalid JSON: #{exception.message}"
    end

    def validate!(payload)
      unless payload.is_a?(Hash) && payload.keys.sort == KEYS && payload["schema_version"] == SCHEMA_VERSION
        raise Invalid, "expected the exact v#{SCHEMA_VERSION} object"
      end

      documents = payload["documents"]
      files = payload["files"]
      unless documents.is_a?(Array) && files.is_a?(Array) &&
          documents.uniq == documents && files.uniq == files && files.all? { |route| route.is_a?(String) }
        raise Invalid, "documents and files must be unique arrays"
      end

      documents.each do |document|
        unless document.is_a?(Hash) && document.keys.sort == DOCUMENT_KEYS &&
            document.values.all? { |value| value.is_a?(String) }
          raise Invalid, "document entries must contain string route and output values"
        end
        unless files.include?(document.fetch("output"))
          raise Invalid, "document output is not listed as a file: #{document.fetch('output').inspect}"
        end
      end

      payload
    end
    private_class_method :validate!
  end
end
