# frozen_string_literal: true

require "uri"
require "nokogiri"

require_relative "media_policy"
require_relative "value_objects"

module JekyllObsidian
  # Closed, deterministic policy for author-selected remote media. Provider
  # URLs are parsed and rebuilt instead of being copied into active markup.
  # No network lookup is performed during compilation.
  module ExternalMedia
    Descriptor = ImmutableRecord.define(
      :kind,
      :provider,
      :source_url,
      :fallback_url,
      :origin,
      :media_type,
      :iframe_allow,
      :iframe_sandbox,
      :title,
      :width,
      :height,
      :identifier
    )

    class Invalid < ArgumentError; end

    YOUTUBE_HOSTS = %w[
      youtube.com
      www.youtube.com
      m.youtube.com
      music.youtube.com
      www.youtube-nocookie.com
      youtu.be
    ].freeze
    BILIBILI_HOSTS = %w[bilibili.com www.bilibili.com m.bilibili.com player.bilibili.com].freeze
    VIMEO_HOSTS = %w[vimeo.com www.vimeo.com player.vimeo.com].freeze
    SHORTENER_HOSTS = %w[b23.tv www.b23.tv].freeze
    X_HOSTS = %w[x.com www.x.com twitter.com www.twitter.com mobile.twitter.com].freeze
    PROVIDER_HOSTS = (YOUTUBE_HOSTS + BILIBILI_HOSTS + VIMEO_HOSTS + SHORTENER_HOSTS).freeze

    YOUTUBE_ID = /\A[A-Za-z0-9_-]{11}\z/
    BILIBILI_BVID = /\ABV1[A-Za-z0-9]{9}\z/
    POSITIVE_INTEGER = /\A[1-9]\d*\z/
    NON_NEGATIVE_INTEGER = /\A(?:0|[1-9]\d*)\z/
    VIMEO_HASH = /\A[0-9A-Fa-f]{10}\z/
    CONTROL_OR_BACKSLASH = /[\x00-\x20\x7f\\]/
    ENCODED_SEPARATOR = /%(?:2f|5c)/i
    X_HANDLE = /\A[A-Za-z0-9_]{1,15}\z/
    X_STATUS_ID = /\A[1-9]\d*\z/
    IFRAME_SANDBOX = "allow-scripts allow-forms allow-popups allow-popups-to-escape-sandbox allow-presentation"

    module_function

    # Resolves Markdown image syntax. Ordinary HTTPS images are represented as
    # :image so the compiler can apply Obsidian-compatible dimensions and its
    # normal lazy-loading attributes.
    def resolve(raw_url)
      uri = parse(raw_url)
      return nil unless uri&.scheme&.casecmp("https")&.zero?

      validate_https!(uri, allow_fragment: true)

      host = uri.host.to_s.downcase
      if X_HOSTS.include?(host) && (tweet = x_tweet(uri))
        return tweet
      end
      if PROVIDER_HOSTS.include?(host)
        validate_https!(uri, provider: true)
        raise Invalid, "shortened provider URLs are not supported; use the expanded video URL" if SHORTENER_HOSTS.include?(host)

        return youtube(uri) if YOUTUBE_HOSTS.include?(host)
        return bilibili(uri) if BILIBILI_HOSTS.include?(host)
        return vimeo(uri) if VIMEO_HOSTS.include?(host)
      end

      if MediaPolicy.kind(uri.path.to_s) == :video
        validate_https!(uri)
        return Descriptor.new(
          kind: :direct_video,
          source_url: uri.to_s,
          fallback_url: uri.to_s,
          origin: origin(uri),
          media_type: MediaPolicy.media_type(uri.path)
        )
      end

      Descriptor.new(kind: :image, source_url: uri.to_s, fallback_url: uri.to_s, origin: origin(uri))
    rescue URI::InvalidURIError
      raise Invalid, "external media URL is invalid"
    end

    # Resolves raw iframe embeds into compiler-owned markup. Known players are
    # canonicalized through their provider policy; other HTTPS pages receive a
    # fixed sandbox and never retain authored active attributes.
    def resolve_frame(raw_url, title: nil, width: nil, height: nil)
      descriptor = resolve(raw_url)
      if descriptor&.kind == :player
        return Descriptor.new(**descriptor.to_h.merge(
          title: safe_title(title),
          width: dimension(width),
          height: dimension(height)
        ))
      end

      uri = parse(raw_url)
      validate_https!(uri, allow_fragment: true)
      canonical = canonical_https_url(uri)
      Descriptor.new(
        kind: :web_frame,
        provider: :web,
        source_url: canonical,
        fallback_url: canonical,
        origin: origin(uri),
        iframe_sandbox: IFRAME_SANDBOX,
        title: safe_title(title) || "Embedded page from #{uri.host.downcase}",
        width: dimension(width),
        height: dimension(height) || 480
      )
    rescue URI::InvalidURIError
      raise Invalid, "iframe URL is invalid"
    end

    def resolve_iframe(raw_html, closed: true)
      raise Invalid, "iframe element is missing its closing tag" unless closed

      fragment = Nokogiri::HTML5.fragment(raw_html.to_s)
      elements = fragment.element_children
      frame = elements.first
      unless elements.length == 1 && frame&.name == "iframe" && fragment.css("iframe").length == 1
        raise Invalid, "iframe embed must contain exactly one iframe element"
      end
      source = frame["src"].to_s.strip
      raise Invalid, "iframe embed requires src" if source.empty?

      resolve_frame(
        source,
        title: frame["title"],
        width: frame["width"],
        height: frame["height"]
      )
    rescue Nokogiri::XML::SyntaxError
      raise Invalid, "iframe element is invalid"
    end

    def https_origin(raw_url)
      uri = parse(raw_url)
      return nil unless uri&.scheme&.casecmp("https")&.zero? && uri.host && uri.userinfo.nil?

      origin(uri)
    rescue URI::InvalidURIError
      nil
    end

    def youtube(uri)
      pairs = query_pairs(uri)
      host = uri.host.downcase
      identifier = if host == "youtu.be"
        single_path_segment(uri.path)
      elsif uri.path == "/watch"
        single_query_value(pairs, "v")
      elsif (match = uri.path.match(%r{\A/(?:shorts|live|embed)/([^/]+)/?\z}))
        match[1]
      end
      raise Invalid, "YouTube URL must identify one video" unless identifier&.match?(YOUTUBE_ID)

      start = youtube_start(pairs)
      query = start ? "?start=#{start}" : ""
      Descriptor.new(
        kind: :player,
        provider: :youtube,
        source_url: "https://www.youtube-nocookie.com/embed/#{identifier}#{query}",
        fallback_url: "https://www.youtube.com/watch?v=#{identifier}",
        origin: "https://www.youtube-nocookie.com",
        iframe_allow: "autoplay; encrypted-media; picture-in-picture"
      )
    end

    def bilibili(uri)
      pairs = query_pairs(uri)
      identifier = nil
      key = nil
      if uri.host.downcase == "player.bilibili.com" && uri.path == "/player.html"
        candidates = {
          "bvid" => single_query_value(pairs, "bvid"),
          "aid" => single_query_value(pairs, "aid"),
          "episodeId" => single_query_value(pairs, "episodeId")
        }.compact
        raise Invalid, "Bilibili player URL must contain exactly one video identifier" unless candidates.length == 1

        key, identifier = candidates.first
      elsif (match = uri.path.match(%r{\A/video/(BV1[A-Za-z0-9]{9}|av[1-9]\d*)/?\z}))
        raw = match[1]
        key, identifier = raw.start_with?("BV") ? ["bvid", raw] : ["aid", raw.delete_prefix("av")]
      elsif (match = uri.path.match(%r{\A/bangumi/play/ep([1-9]\d*)/?\z}))
        key, identifier = ["episodeId", match[1]]
      end

      valid = case key
      when "bvid" then identifier&.match?(BILIBILI_BVID)
      when "aid", "episodeId" then identifier&.match?(POSITIVE_INTEGER)
      end
      raise Invalid, "Bilibili URL must identify one video or episode" unless valid

      output = [[key, identifier]]
      page = single_query_value(pairs, "p")
      time = single_query_value(pairs, "t")
      raise Invalid, "Bilibili page must be a positive integer" if page && !page.match?(POSITIVE_INTEGER)
      raise Invalid, "Bilibili start time must be a non-negative integer" if time && !time.match?(NON_NEGATIVE_INTEGER)
      output << ["p", page] if page
      output << ["t", time] if time
      fallback = key == "episodeId" ? "https://www.bilibili.com/bangumi/play/ep#{identifier}" :
        "https://www.bilibili.com/video/#{key == "bvid" ? identifier : "av#{identifier}"}"

      Descriptor.new(
        kind: :player,
        provider: :bilibili,
        source_url: "https://player.bilibili.com/player.html?#{URI.encode_www_form(output)}",
        fallback_url: fallback,
        origin: "https://player.bilibili.com"
      )
    end

    def vimeo(uri)
      path = uri.path
      identifier = nil
      privacy_hash = nil
      patterns = [
        %r{\A/([1-9]\d*)/?\z},
        %r{\A/album/[1-9]\d*/video/([1-9]\d*)/?\z},
        %r{\A/channels/[^/]+/([1-9]\d*)/?\z},
        %r{\A/groups/[^/]+/videos/([1-9]\d*)/?\z},
        %r{\A/ondemand/[^/]+/([1-9]\d*)/?\z},
        %r{\A/video/([1-9]\d*)/?\z}
      ]
      patterns.each do |pattern|
        match = path.match(pattern)
        if match
          identifier = match[1]
          break
        end
      end
      if (match = path.match(%r{\A/([1-9]\d*)/([0-9A-Fa-f]{10})/?\z}))
        identifier = match[1]
        privacy_hash = match[2]
      end
      pairs = query_pairs(uri)
      query_hash = single_query_value(pairs, "h")
      privacy_hash ||= query_hash
      raise Invalid, "Vimeo URL must identify one numeric video" unless identifier&.match?(POSITIVE_INTEGER)
      raise Invalid, "Vimeo privacy hash is invalid" if privacy_hash && !privacy_hash.match?(VIMEO_HASH)

      output = []
      output << ["h", privacy_hash] if privacy_hash
      output << ["dnt", "1"]
      Descriptor.new(
        kind: :player,
        provider: :vimeo,
        source_url: "https://player.vimeo.com/video/#{identifier}?#{URI.encode_www_form(output)}",
        fallback_url: "https://vimeo.com/#{identifier}",
        origin: "https://player.vimeo.com",
        iframe_allow: "autoplay; fullscreen; picture-in-picture; clipboard-write"
      )
    end

    def parse(raw_url)
      text = raw_url.to_s.strip
      raise Invalid, "external media URL contains unsafe characters" if text.empty? || text.match?(CONTROL_OR_BACKSLASH)

      URI.parse(text)
    end

    def validate_https!(uri, provider: false, allow_fragment: false)
      unless uri&.scheme&.casecmp("https")&.zero? && uri.host && uri.userinfo.nil? && uri.port == 443
        raise Invalid, "external embeds require an HTTPS URL without credentials or a custom port"
      end
      raise Invalid, "external embed URLs cannot contain a fragment" if uri.fragment && !allow_fragment
      if provider && (uri.path.to_s.match?(ENCODED_SEPARATOR) || uri.path.to_s.split("/").include?(".."))
        raise Invalid, "provider URL path is not allowed"
      end
    end

    def origin(uri)
      port = uri.port == 443 ? "" : ":#{uri.port}"
      "https://#{uri.host.downcase}#{port}"
    end

    def canonical_https_url(uri)
      URI::HTTPS.build(
        host: uri.host.downcase,
        path: uri.path.to_s.empty? ? "/" : uri.path,
        query: uri.query,
        fragment: uri.fragment
      ).to_s
    rescue URI::InvalidComponentError
      raise Invalid, "iframe URL is invalid"
    end

    def x_tweet(uri)
      validate_https!(uri, provider: true, allow_fragment: true)
      match = uri.path.to_s.match(%r{\A/([^/]+)/status/([^/]+)/?\z})
      system_match = uri.path.to_s.match(%r{\A/i/web/status/([^/]+)/?\z}) unless match
      return nil unless match || system_match

      handle = match&.[](1)
      identifier = match ? match[2] : system_match[1]
      unless identifier.match?(X_STATUS_ID) && (!handle || handle.match?(X_HANDLE))
        raise Invalid, "X URL must contain a valid account and post ID"
      end

      canonical = handle ? "https://x.com/#{handle}/status/#{identifier}" : "https://x.com/i/web/status/#{identifier}"
      Descriptor.new(
        kind: :tweet,
        provider: :x,
        source_url: canonical,
        fallback_url: canonical,
        origin: "https://platform.twitter.com",
        identifier: identifier,
        title: handle ? "Post by @#{handle} on X" : "Post on X"
      )
    end

    def dimension(value)
      text = value.to_s.strip
      return nil if text.empty? || !text.match?(POSITIVE_INTEGER)

      number = text.to_i
      number if number.between?(64, 4096)
    end

    def safe_title(value)
      title = value.to_s.strip
      return nil if title.empty? || !title.valid_encoding? || title.length > 240
      return nil if title.match?(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/)

      title
    end

    def query_pairs(uri)
      URI.decode_www_form(uri.query.to_s)
    rescue ArgumentError
      raise Invalid, "external media query is invalid"
    end

    def single_query_value(pairs, name)
      values = pairs.filter_map { |key, value| value if key == name }
      raise Invalid, "external media query parameter #{name} must occur at most once" if values.length > 1

      values.first
    end

    def single_path_segment(path)
      match = path.match(%r{\A/([^/]+)/?\z})
      match && match[1]
    end

    def youtube_start(pairs)
      raw = single_query_value(pairs, "start") || single_query_value(pairs, "t")
      return nil if raw.nil?
      return raw.to_i if raw.match?(NON_NEGATIVE_INTEGER)

      match = raw.match(/\A(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?\z/)
      raise Invalid, "YouTube start time is invalid" unless match && match.captures.compact.any?

      match[1].to_i * 3600 + match[2].to_i * 60 + match[3].to_i
    end
  end
end
