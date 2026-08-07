#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "nokogiri"
require "pathname"
require "set"
require "uri"

require_relative "../lib/jekyll_obsidian/external_media"

class SiteUrlVerifier
  URL_ATTRIBUTES = [
    %w[a href],
    %w[link href],
    %w[script src],
    %w[iframe src],
    %w[img src],
    %w[source src],
    %w[video src],
    %w[video poster],
    %w[audio src],
    %w[object data]
  ].freeze
  CSP_DIRECTIVES = {
    "default-src" => ["'self'"],
    "base-uri" => ["'self'"],
    "form-action" => ["'self'"],
    "script-src" => ["'self'"],
    "style-src" => ["'self'", "'unsafe-inline'"],
    "img-src" => ["'self'", "https:"],
    "media-src" => ["'self'"],
    "object-src" => ["'self'"],
    "font-src" => ["'self'"],
    "connect-src" => ["'self'"],
    "frame-src" => ["'self'"]
  }.freeze
  COMMENTS_CSP_DIRECTIVES = CSP_DIRECTIVES.merge(
    "script-src" => ["'self'", "https://giscus.app"],
    "style-src" => ["'self'", "'unsafe-inline'", "https://giscus.app"],
    "frame-src" => ["'self'", "https://giscus.app"]
  ).freeze
  GISCUS_ORIGIN = "https://giscus.app"
  X_WIDGET_ORIGIN = "https://platform.twitter.com"
  ANALYTICS_CSP = {
    "cloudflare" => {
      "script-src" => ["https://static.cloudflareinsights.com"],
      "connect-src" => ["https://cloudflareinsights.com"]
    },
    "google" => {
      "script-src" => ["https://www.googletagmanager.com"],
      "connect-src" => [
        "https://*.analytics.google.com",
        "https://*.google-analytics.com",
        "https://www.googletagmanager.com"
      ]
    }
  }.freeze

  def initialize(site_dir, origin, baseurl)
    @site_dir = File.realpath(site_dir)
    @origin = origin.to_s.delete_suffix("/")
    @baseurl = normalize_baseurl(baseurl)
    @errors = []
    @html_ids = {}
  end

  def verify
    html_files = Dir.glob(File.join(@site_dir, "**", "*.html")).sort
    add_error("site contains no HTML") if html_files.empty?
    html_files.each { |path| verify_html(path) }
    verify_json_indexes
    verify_xml_urls
    verify_css_assets

    unless @errors.empty?
      warn @errors.map { |message| "site URL verification: #{message}" }.join("\n")
      return false
    end

    puts "site URL verification: ok (#{html_files.length} HTML pages, baseurl #{@baseurl.inspect})"
    true
  end

  private

  def normalize_baseurl(value)
    text = value.to_s
    return "" if text.empty? || text == "/"

    text.start_with?("/") ? text.delete_suffix("/") : "/#{text.delete_suffix("/")}"
  end

  def verify_html(path)
    relative = relative_path(path)
    route = route_for_output(relative)
    document = Nokogiri::HTML5.parse(File.read(path, encoding: "UTF-8"))
    @html_ids[path] = document.css("[id]").map { |node| node["id"] }.to_set
    csp_node = document.css("meta[http-equiv]").find do |node|
      node["http-equiv"].to_s.casecmp("Content-Security-Policy").zero?
    end
    csp = csp_node&.[]("content").to_s
    add_error("#{relative}: missing production meta CSP") if csp.empty?
    comments = !document.at_css("[data-website-comments-load]").nil?
    analytics = verify_analytics(document, relative)
    verify_csp(csp, relative, comments:, analytics:, document:) unless csp.empty?

    canonical = document.at_css("link[rel~='canonical']")&.[]("href")
    expected_canonical = "#{@origin}#{public_path(route)}"
    decoded_canonical = canonical && URI.decode_uri_component(canonical)
    noindex = document.at_css("meta[name='robots']")&.[]("content").to_s.split(/[\s,]+/).include?("noindex")
    unless @origin.empty?
      if noindex
        verify_noindex_canonical(canonical, relative)
      elsif decoded_canonical != expected_canonical
        add_error("#{relative}: canonical #{canonical.inspect} != #{expected_canonical.inspect}")
      end
    end

    og_url = document.at_css("meta[property='og:url']")&.[]("content")
    decoded_og_url = og_url && URI.decode_uri_component(og_url)
    if !@origin.empty? && decoded_og_url != expected_canonical
      add_error("#{relative}: og:url #{og_url.inspect} != #{expected_canonical.inspect}")
    end

    if comments
      backlink = document.at_css("meta[name='giscus:backlink']")&.[]("content")
      decoded_backlink = backlink && URI.decode_uri_component(backlink)
      if !@origin.empty? && decoded_backlink != expected_canonical
        add_error("#{relative}: giscus:backlink #{backlink.inspect} != #{expected_canonical.inspect}")
      end
    end

    verify_external_embeds(document, relative, comments:)
    verify_external_media(document, relative)

    URL_ATTRIBUTES.each do |element, attribute|
      document.css("#{element}[#{attribute}]").each do |node|
        image = element == "img" || (element == "source" && node.ancestors.any? { |ancestor| ancestor.name == "picture" })
        verify_reference(node[attribute], route, relative, image:)
      end
    end
    document.css("img[srcset], source[srcset]").each do |node|
      image = node.name == "img" || node.ancestors.any? { |ancestor| ancestor.name == "picture" }
      srcset_urls(node["srcset"]).each { |value| verify_reference(value, route, relative, image:) }
    end
    document.css("meta[name^='website:'][content]:not([name='website:analytics'])").each do |node|
      verify_reference(node["content"], route, relative)
    end
  rescue StandardError => exception
    add_error("#{relative || path}: could not inspect HTML: #{exception.class}: #{exception.message}")
  end

  def verify_reference(value, current_route, source, image: false)
    return if value.nil? || value.empty?
    return if value.start_with?("mailto:", "tel:")

    scheme = value[/\A([a-z][a-z0-9+.-]*):/i, 1]&.downcase
    if image && scheme == "http" && !same_origin_url?(value)
      add_error("#{source}: image URL must use HTTPS: #{value.inspect}")
      return
    end
    return if %w[http https].include?(scheme)
    if scheme || value.start_with?("//")
      add_error("#{source}: unsupported URL #{value.inspect}")
      return
    end

    path_and_query, fragment = value.split("#", 2)
    path = path_and_query.split("?", 2).first.to_s
    if path.empty?
      verify_fragment(source, fragment) if fragment
      return
    end

    path = resolve_path(path, current_route)
    unless baseurl_once?(path)
      add_error("#{source}: baseurl is missing or repeated in #{value.inspect}")
      return
    end

    route = strip_baseurl(path)
    output = output_path_for_route(route)
    if File.file?(output)
      verify_fragment_in_file(output, fragment, source) if fragment && !fragment.empty? && File.extname(output).downcase == ".html"
    else
      add_error("#{source}: local target does not exist for #{value.inspect}")
    end
  rescue ArgumentError => exception
    add_error("#{source}: invalid URL #{value.inspect}: #{exception.message}")
  end

  def same_origin_url?(value)
    return false if @origin.empty?

    reference = URI.parse(value)
    origin = URI.parse(@origin)
    reference.scheme == origin.scheme && reference.host == origin.host && reference.port == origin.port
  rescue URI::InvalidURIError
    false
  end

  def verify_noindex_canonical(value, source)
    if value.nil? || value.empty?
      add_error("#{source}: noindex page is missing canonical")
      return
    end

    canonical = URI.parse(value)
    origin = URI.parse(@origin)
    same_origin = canonical.scheme == origin.scheme && canonical.host == origin.host &&
      canonical.port == origin.port && canonical.userinfo.nil?
    unless same_origin && canonical.query.nil? && canonical.fragment.nil?
      add_error("#{source}: noindex canonical must use the configured origin without query or fragment")
      return
    end

    path = URI.decode_uri_component(canonical.path.to_s)
    path = "/" if path.empty?
    unless baseurl_once?(path)
      add_error("#{source}: noindex canonical has a missing or repeated baseurl")
      return
    end

    target = output_path_for_route(strip_baseurl(path))
    unless File.file?(target) && File.extname(target).casecmp(".html").zero?
      add_error("#{source}: canonical target does not exist: #{value.inspect}")
      return
    end

    target_document = Nokogiri::HTML5.parse(File.read(target, encoding: "UTF-8"))
    target_robots = target_document.at_css("meta[name='robots']")&.[]("content").to_s.split(/[\s,]+/)
    add_error("#{source}: canonical target must be indexable: #{value.inspect}") if target_robots.include?("noindex")
  rescue URI::InvalidURIError, ArgumentError => exception
    add_error("#{source}: invalid noindex canonical #{value.inspect}: #{exception.message}")
  end

  def verify_fragment(source, fragment)
    return if fragment.nil? || fragment.empty?
    path = File.join(@site_dir, source)
    verify_fragment_in_file(path, fragment, source)
  end

  def verify_fragment_in_file(path, fragment, source)
    decoded = URI.decode_uri_component(fragment)
    ids = @html_ids[path] ||= Nokogiri::HTML5.parse(File.read(path, encoding: "UTF-8"))
      .css("[id]").map { |node| node["id"] }.to_set
    add_error("#{source}: missing fragment ##{fragment}") unless ids.include?(decoded)
  rescue ArgumentError, Nokogiri::XML::SyntaxError
    add_error("#{source}: invalid fragment ##{fragment}")
  end

  def verify_csp(value, source, comments:, analytics:, document:)
    pairs = value.split(";").filter_map do |part|
      name, *tokens = part.strip.split(/\s+/)
      [name, tokens] unless name.to_s.empty?
    end
    duplicates = pairs.group_by(&:first).select { |_name, items| items.length > 1 }.keys
    duplicates.each { |name| add_error("#{source}: CSP directive #{name} must appear exactly once") }
    directives = pairs.to_h
    expected_directives = (comments ? COMMENTS_CSP_DIRECTIVES : CSP_DIRECTIVES).transform_values(&:dup)
    ANALYTICS_CSP.fetch(analytics, {}).each do |name, tokens|
      expected_directives[name] += tokens
    end
    tweet = !document.at_css("[data-website-tweet]").nil?
    expected_directives["script-src"] << X_WIDGET_ORIGIN if tweet
    expected_directives["media-src"] += external_origins(document, "video[src], audio[src], video source[src], audio source[src]")
    expected_directives["frame-src"] += external_origins(document, "iframe[src]")
    expected_directives["frame-src"] << X_WIDGET_ORIGIN if tweet
    expected_directives.transform_values! { |tokens| tokens.uniq.sort }
    (directives.keys - expected_directives.keys).sort.each do |name|
      add_error("#{source}: unsupported CSP directive #{name}")
    end
    expected_directives.each do |name, expected|
      actual = directives[name]
      next if actual && actual.sort == expected.sort

      add_error("#{source}: CSP directive #{name} must be exactly #{expected.join(" ")}")
    end
  end

  def verify_analytics(document, source)
    nodes = document.css("meta[name='website:analytics']")
    if nodes.length > 1
      add_error("#{source}: website analytics meta must appear at most once")
      return nil
    end
    return nil if nodes.empty?

    node = nodes.first
    provider = node["data-provider"].to_s
    identifier = node["content"].to_s
    unless ANALYTICS_CSP.key?(provider)
      add_error("#{source}: unsupported website analytics provider #{provider.inspect}")
      return nil
    end
    valid_identifier = if provider == "google"
      identifier.match?(/\AG-[A-Z0-9]+\z/)
    else
      !identifier.empty? && identifier.length <= 256 && !identifier.match?(/[\s<>"']/)
    end
    add_error("#{source}: invalid #{provider} analytics identifier") unless valid_identifier
    provider
  end

  def verify_external_embeds(document, source, comments:)
    document.css("script[src], iframe[src]").each do |node|
      value = node["src"].to_s
      uri = URI.parse(value)
      next unless %w[http https].include?(uri.scheme)

      default_port = uri.scheme == "https" ? 443 : 80
      port = uri.port == default_port ? "" : ":#{uri.port}"
      source_origin = "#{uri.scheme}://#{uri.host}#{port}"
      if comments && source_origin == GISCUS_ORIGIN && (node.name == "iframe" || uri.path == "/client.js")
        next
      end
      if node.name == "iframe"
        if node["data-website-external-player"]
          verify_player_frame(node, value, source)
        elsif node["data-website-external-frame"] == "web"
          verify_web_frame(node, value, source)
        else
          add_error("#{source}: external iframe is missing a compiler-owned marker: #{value.inspect}")
        end
      else
        add_error("#{source}: external script source is not allowed: #{value.inspect}")
      end
    rescue URI::InvalidURIError, JekyllObsidian::ExternalMedia::Invalid
      add_error("#{source}: invalid external #{node.name} source #{value.inspect}")
    end
    verify_tweets(document, source)
  end

  def verify_player_frame(node, value, source)
    descriptor = JekyllObsidian::ExternalMedia.resolve_frame(value)
    expected_class = "website-external-player--#{descriptor.provider}"
    checks = {
      "canonical src" => value == descriptor.source_url,
      "compiler marker" => node["data-website-external-player"] == descriptor.provider.to_s,
      "player class" => node["class"].to_s.split.include?("website-external-player") &&
        node["class"].to_s.split.include?(expected_class),
      "title" => !node["title"].to_s.strip.empty?,
      "lazy loading" => node["loading"] == "lazy",
      "referrer policy" => node["referrerpolicy"] == "strict-origin-when-cross-origin",
      "permissions" => node["allow"].to_s == descriptor.iframe_allow.to_s,
      "fullscreen" => node.key?("allowfullscreen")
    }
    checks.each do |label, valid|
      add_error("#{source}: external iframe has invalid #{label}: #{value.inspect}") unless valid
    end
  end

  def verify_web_frame(node, value, source)
    descriptor = JekyllObsidian::ExternalMedia.resolve_frame(value)
    checks = {
      "canonical src" => descriptor.kind == :web_frame && value == descriptor.source_url,
      "web frame class" => node["class"].to_s.split.include?("website-external-frame__viewport"),
      "title" => !node["title"].to_s.strip.empty?,
      "lazy loading" => node["loading"] == "lazy",
      "referrer policy" => node["referrerpolicy"] == "strict-origin-when-cross-origin",
      "sandbox" => node["sandbox"] == JekyllObsidian::ExternalMedia::IFRAME_SANDBOX,
      "height" => node["height"].to_s.match?(/\A[1-9]\d*\z/),
      "permissions" => !node.key?("allow"),
      "fullscreen" => node.key?("allowfullscreen")
    }
    checks.each do |label, valid|
      add_error("#{source}: external iframe has invalid #{label}: #{value.inspect}") unless valid
    end
    dangerous = node.attribute_nodes.map(&:name).grep(/\Aon/i) + %w[srcdoc style].select { |name| node.key?(name) }
    add_error("#{source}: external iframe retained unsafe attributes: #{dangerous.join(', ')}") unless dangerous.empty?
    wrapper = node.ancestors("figure").find { |candidate| candidate["class"].to_s.split.include?("website-external-frame") }
    fallback = wrapper&.at_css("a.website-external-frame__fallback")
    unless fallback && fallback["href"] == descriptor.fallback_url && fallback["target"] == "_blank" &&
        fallback["rel"].to_s.split.sort == %w[noopener noreferrer]
      add_error("#{source}: external iframe is missing its canonical fallback link: #{value.inspect}")
    end
  end

  def verify_tweets(document, source)
    document.css("[data-website-tweet]").each do |node|
      identifier = node["data-website-tweet"].to_s
      mount = node.at_css("[data-website-tweet-mount]")
      fallback = node.at_css("a[data-website-tweet-fallback]")
      begin
        descriptor = JekyllObsidian::ExternalMedia.resolve(fallback&.[]("href"))
        valid = identifier.match?(/\A[1-9]\d*\z/) && descriptor&.kind == :tweet &&
          descriptor.identifier == identifier && mount && node.css("script, iframe").empty?
        add_error("#{source}: Tweet embed is not canonical or contains active authored content") unless valid
      rescue JekyllObsidian::ExternalMedia::Invalid
        add_error("#{source}: Tweet embed has an invalid fallback URL")
      end
    end
  end

  def verify_external_media(document, source)
    document.css("video[src], audio[src], video source[src], audio source[src]").each do |node|
      value = node["src"].to_s
      uri = URI.parse(value)
      next unless uri.scheme
      unless uri.scheme == "https"
        add_error("#{source}: external media must use HTTPS: #{value.inspect}")
        next
      end

      descriptor = JekyllObsidian::ExternalMedia.resolve(value)
      unless descriptor&.kind == :direct_video && node.name != "audio" && node.ancestors("audio").empty?
        add_error("#{source}: external media source is not a supported direct video: #{value.inspect}")
      end
    rescue URI::InvalidURIError, JekyllObsidian::ExternalMedia::Invalid
      add_error("#{source}: invalid external media source #{value.inspect}")
    end
  end

  def external_origins(document, selector)
    document.css(selector).filter_map do |node|
      JekyllObsidian::ExternalMedia.https_origin(node["src"])
    end.uniq.sort
  end

  def srcset_urls(value)
    value.to_s.split(",").filter_map do |candidate|
      url = candidate.strip.split(/\s+/, 2).first
      url unless url.to_s.empty?
    end
  end

  def verify_json_indexes
    paths = Dir.glob(File.join(@site_dir, "assets", "website", "{,i18n/*/}{catalog,graph,search}.v1.json")).sort
    paths.each do |path|
      payload = JSON.parse(File.read(path, encoding: "UTF-8"))
      add_error("#{relative_path(path)}: schema_version is not 1") unless payload["schema_version"] == 1
      collections = [payload["notes"], payload["nodes"], payload["documents"]].compact
      collections.flatten.each do |item|
        next unless item.is_a?(Hash) && item["url"]
        unless baseurl_once?(item["url"])
          add_error("#{relative_path(path)}: bad indexed URL #{item["url"].inspect}")
          next
        end
        route = strip_baseurl(item["url"])
        add_error("#{relative_path(path)}: indexed target is missing for #{item["url"].inspect}") unless File.file?(output_path_for_route(route))
      end
    rescue JSON::ParserError => exception
      add_error("#{relative_path(path)}: invalid JSON: #{exception.message}")
    end
  end

  def verify_xml_urls
    paths = [File.join(@site_dir, "sitemap.xml"), *Dir.glob(File.join(@site_dir, "{,*/}feed.xml"))].uniq.sort
    paths.each do |path|
      next unless File.file?(path)
      name = relative_path(path)
      document = Nokogiri::XML(File.read(path, encoding: "UTF-8")) { |config| config.strict.nonet }
      document.remove_namespaces!
      values = document.xpath("//loc/text() | //id/text() | //link/@href").map(&:text)
      values.each do |value|
        next if value.empty?
        expected_prefix = "#{@origin}#{@baseurl}"
        valid_prefix = !@origin.empty? && (value == expected_prefix || value.start_with?("#{expected_prefix}/"))
        repeated = !@baseurl.empty? && value.start_with?("#{@origin}#{@baseurl}#{@baseurl}/")
        unless valid_prefix && !repeated
          add_error("#{name}: origin/baseurl is missing or repeated in #{value.inspect}")
        end
      end
    rescue Nokogiri::XML::SyntaxError => exception
      add_error("#{name}: invalid XML: #{exception.message}")
    end
  end

  def verify_css_assets
    Dir.glob(File.join(@site_dir, "**", "*.css")).sort.each do |path|
      css = File.read(path, encoding: "UTF-8")
      css.scan(/url\((?:"|')?([^"')]+)(?:"|')?\)/).flatten.each do |reference|
        next if reference.start_with?("#", "data:", "http:", "https:")
        reference_path = URI.decode_uri_component(reference.split(/[?#]/, 2).first)
        target = if reference_path.start_with?("/")
          unless baseurl_once?(reference_path)
            add_error("#{relative_path(path)}: baseurl is missing or repeated in CSS asset #{reference.inspect}")
            next
          end
          output_path_for_route(strip_baseurl(reference_path))
        else
          File.expand_path(reference_path, File.dirname(path))
        end
        unless (target == @site_dir || target.start_with?("#{@site_dir}#{File::SEPARATOR}")) && File.file?(target)
          add_error("#{relative_path(path)}: missing CSS asset #{reference.inspect}")
        end
      rescue ArgumentError
        add_error("#{relative_path(path)}: invalid CSS asset #{reference.inspect}")
      end
    end
  end

  def resolve_path(path, current_route)
    return path if path.start_with?("/")
    base = current_route.end_with?("/") ? current_route : File.dirname(current_route)
    File.join(public_path(base), path)
  end

  def baseurl_once?(path)
    return path.start_with?("/") if @baseurl.empty?
    return false unless path == @baseurl || path.start_with?("#{@baseurl}/")
    !path.start_with?("#{@baseurl}#{@baseurl}/")
  end

  def strip_baseurl(path)
    stripped = @baseurl.empty? ? path : path.delete_prefix(@baseurl)
    stripped.empty? ? "/" : stripped
  end

  def public_path(route)
    return route if @baseurl.empty?
    return "#{@baseurl}/" if route == "/"
    "#{@baseurl}#{route}"
  end

  def output_path_for_route(route)
    decoded = URI.decode_uri_component(route.split(/[?#]/, 2).first)
    relative = decoded.delete_prefix("/")
    relative = if relative.empty?
      "index.html"
    elsif decoded.end_with?("/")
      File.join(relative, "index.html")
    else
      relative
    end
    target = File.expand_path(relative, @site_dir)
    raise ArgumentError, "target escapes site" unless target.start_with?("#{@site_dir}#{File::SEPARATOR}")
    target
  end

  def route_for_output(relative)
    return "/" if relative == "index.html"
    return "/#{relative.delete_suffix("index.html")}" if relative.end_with?("/index.html")
    "/#{relative}"
  end

  def relative_path(path)
    Pathname.new(path).relative_path_from(Pathname.new(@site_dir)).to_s
  end

  def add_error(message)
    @errors << message
  end
end

unless ARGV.length == 3
  warn "Usage: <site-dir>/scripts/verify-site-urls.rb SITE_DIR ORIGIN BASEURL"
  exit 64
end

exit(SiteUrlVerifier.new(*ARGV).verify ? 0 : 1)
