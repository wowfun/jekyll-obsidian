# frozen_string_literal: true

require "uri"

module JekyllObsidian
  class UrlBuilder
    INVALID_PERMALINK = %r{(?:\A(?!/)|://|[?#]|(?:\A|/)\.\.(?:/|\z)|:[a-z_]+)}i
    ENCODED_SEPARATOR = /%(?:2f|5c)/i
    CONTROL_CHARACTER = /[[:cntrl:]]/

    attr_reader :origin, :baseurl

    def initialize(origin:, baseurl:)
      @origin = normalize_origin(origin)
      @baseurl = normalize_baseurl(baseurl)
      freeze
    end

    def route_for_note(path)
      normalized = path.unicode_normalize(:nfc)
      segments = normalized.split("/")
      filename = segments.pop
      stem = filename.delete_suffix(".md")
      segments << stem unless stem.casecmp("index").zero?
      encoded = segments.reject(&:empty?).map { |segment| encode_segment(segment) }
      encoded.empty? ? "/" : "/#{encoded.join("/")}/"
    end

    def validate_permalink(value)
      return nil unless value.is_a?(String)
      return nil unless value.start_with?("/") && value.end_with?("/")

      normalized = decode_safe_path(value).unicode_normalize(:nfc)
      return nil if normalized.match?(INVALID_PERMALINK)
      return nil if normalized.include?("//")

      segments = normalized.split("/").reject(&:empty?)
      return "/" if segments.empty?

      "/#{segments.map { |segment| encode_segment(segment) }.join("/")}/"
    rescue ArgumentError, EncodingError, URI::InvalidURIError
      nil
    end

    def href(route)
      return route if baseurl.empty?
      return "#{baseurl}/" if route == "/"

      "#{baseurl}#{route}"
    end

    def absolute_url(route)
      return nil if origin.empty?

      "#{origin}#{href(route)}"
    end

    def attachment_route(path)
      encoded = path.unicode_normalize(:nfc).split("/").map { |segment| encode_segment(segment) }
      "/assets/vault/#{encoded.join("/")}"
    end

    def fragment(value)
      return "" if value.nil? || value.empty?

      anchor = value.start_with?("^") ? value.delete_prefix("^") : slug(value)
      "##{encode_fragment(anchor)}"
    end

    def slug(value)
      slug = value.to_s.unicode_normalize(:nfc).downcase
        .gsub(/<[^>]+>/, "")
        .gsub(/[^\p{L}\p{N}\-_ ]+/u, "")
        .strip
        .gsub(/[ _]+/, "-")
      slug.empty? ? "section" : slug
    end

    def collision_key(route)
      raw = route.to_s
      raise ArgumentError, "route cannot contain a query or fragment" if raw.match?(/[?#]/)

      decoded = decode_safe_path(raw).unicode_normalize(:nfc)
      raise ArgumentError, "route must be a root-relative path" unless decoded.start_with?("/")
      raise ArgumentError, "route cannot contain an empty path segment" if decoded.include?("//")

      decoded = decoded.downcase(:fold)
      decoded = "#{decoded}/" unless decoded.end_with?("/") || File.extname(decoded) != ""
      decoded
    end

    private

    def normalize_origin(value)
      text = value.to_s.strip.sub(%r{/+\z}, "")
      return "" if text.empty?

      uri = URI.parse(text)
      raise ArgumentError, "url must be an http(s) origin" unless %w[http https].include?(uri.scheme) && uri.host
      raise ArgumentError, "url must not include a path, query, or fragment" unless [nil, "", "/"].include?(uri.path) && uri.query.nil? && uri.fragment.nil?

      default_port = (uri.scheme == "http" && uri.port == 80) || (uri.scheme == "https" && uri.port == 443)
      "#{uri.scheme}://#{uri.host}#{default_port ? "" : ":#{uri.port}"}"
    end

    def normalize_baseurl(value)
      text = value.to_s
      return "" if text.empty? || text == "/"
      raise ArgumentError, "baseurl must start with one slash" unless text.start_with?("/")
      raise ArgumentError, "baseurl cannot have a trailing slash" if text.end_with?("/")

      decoded = decode_safe_path(text).unicode_normalize(:nfc)
      if decoded.include?("//") || decoded.match?(/[?#]/)
        raise ArgumentError, "baseurl cannot contain query, fragment, traversal, or empty path segments"
      end

      "/#{decoded.split("/").reject(&:empty?).map { |segment| encode_segment(segment) }.join("/")}"
    end

    def encode_segment(segment)
      URI.encode_uri_component(segment.unicode_normalize(:nfc))
    end

    def encode_fragment(fragment)
      URI.encode_uri_component(fragment).gsub("%2F", "/")
    end

    def percent_decode(value)
      URI.decode_uri_component(value)
    end

    def decode_safe_path(value)
      text = value.to_s
      raise ArgumentError, "path must be valid UTF-8" unless text.valid_encoding?
      raise ArgumentError, "encoded path separators are not allowed" if text.match?(ENCODED_SEPARATOR)

      decoded = percent_decode(text)
      raise ArgumentError, "path must be valid UTF-8" unless decoded.valid_encoding?
      raise ArgumentError, "control characters are not allowed in paths" if decoded.match?(CONTROL_CHARACTER)
      raise ArgumentError, "backslashes are not allowed in paths" if decoded.include?("\\")
      raise ArgumentError, "dot segments are not allowed in paths" if decoded.split("/", -1).any? { |segment| segment == "." || segment == ".." }

      decoded
    end
  end
end
