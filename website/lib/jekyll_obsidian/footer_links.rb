# frozen_string_literal: true

require "uri"

module JekyllObsidian
  module FooterLinks
    class Invalid < ArgumentError; end
    MAX_LINKS = 12
    MAX_LABEL_LENGTH = 64
    MAX_URL_LENGTH = 2048
    module_function

    def resolve(raw)
      return [] if raw.nil?

      mapping!(raw, %w[links], "website.footer")
      links = raw.fetch("links", [])
      raise Invalid, "website.footer.links must be a list" unless links.is_a?(Array)
      raise Invalid, "website.footer.links must contain at most #{MAX_LINKS} links" if links.length > MAX_LINKS

      links.map.with_index do |link, index|
        key = "website.footer.links[#{index}]"
        mapping!(link, %w[label url locale_urls], key)
        label = text!(link["label"], "#{key}.label", MAX_LABEL_LENGTH)
        url = url!(link["url"], "#{key}.url")
        overrides = link.fetch("locale_urls", {})
        unless overrides.is_a?(Hash) && overrides.keys.all? { |locale| locale.is_a?(String) && locale.match?(FrontMatter::LANGUAGE_PATTERN) }
          raise Invalid, "#{key}.locale_urls must map language identifiers to HTTPS URLs"
        end
        normalized = {}
        overrides.each do |locale, target|
          folded = locale.downcase
          raise Invalid, "#{key}.locale_urls keys must be unique ignoring case" if normalized.key?(folded)

          normalized[folded] = url!(target, "#{key}.locale_urls.#{locale}")
        end
        { "label" => label, "url" => url, "locale_urls" => normalized }
      end
    end

    def present(links, locale)
      links.map { |link| { "label" => link.fetch("label"), "url" => link.fetch("locale_urls").fetch(locale.to_s.downcase, link.fetch("url")) } }
    end

    def mapping!(value, keys, key)
      unless value.is_a?(Hash) && value.keys.all? { |name| keys.include?(name) }
        raise Invalid, "#{key} must be a mapping containing only #{keys.join(', ')}"
      end
    end
    private_class_method :mapping!

    def text!(value, key, limit)
      text = OutputText.strip(value) if FrontMatter.valid_output_text?(value)
      unless text && !text.empty? && text.length <= limit && !value.match?(/[\t\r\n\u2028\u2029]/)
        raise Invalid, "#{key} must be a non-empty, single-line output-safe string of at most #{limit} characters"
      end
      text
    end
    private_class_method :text!

    def url!(value, key)
      text = text!(value, key, MAX_URL_LENGTH)
      uri = URI.parse(text)
      unless uri.scheme == "https" && !uri.host.to_s.empty? && uri.userinfo.nil?
        raise Invalid, "#{key} must be an absolute HTTPS URL without credentials"
      end
      text
    rescue URI::InvalidURIError
      raise Invalid, "#{key} must be an absolute HTTPS URL without credentials"
    end
    private_class_method :url!
  end
end
