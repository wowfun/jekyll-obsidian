#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "nokogiri"
require "pathname"
require "set"
require "uri"

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
    "media-src" => ["'self'", "https:"],
    "object-src" => ["'self'"],
    "font-src" => ["'self'"],
    "connect-src" => ["'self'"],
    "frame-src" => ["'self'"]
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
    if relative == "assets/obsidian/docs-navigation.html"
      document.css("a[href]").each { |node| verify_reference(node["href"], "/", relative) }
      return
    end
    csp_node = document.css("meta[http-equiv]").find do |node|
      node["http-equiv"].to_s.casecmp("Content-Security-Policy").zero?
    end
    csp = csp_node&.[]("content").to_s
    add_error("#{relative}: missing production meta CSP") if csp.empty?
    verify_csp(csp, relative) unless csp.empty?

    canonical = document.at_css("link[rel~='canonical']")&.[]("href")
    expected_canonical = "#{@origin}#{public_path(route)}"
    decoded_canonical = canonical && URI.decode_uri_component(canonical)
    if !@origin.empty? && decoded_canonical != expected_canonical
      add_error("#{relative}: canonical #{canonical.inspect} != #{expected_canonical.inspect}")
    end

    og_url = document.at_css("meta[property='og:url']")&.[]("content")
    decoded_og_url = og_url && URI.decode_uri_component(og_url)
    if !@origin.empty? && decoded_og_url != expected_canonical
      add_error("#{relative}: og:url #{og_url.inspect} != #{expected_canonical.inspect}")
    end

    URL_ATTRIBUTES.each do |element, attribute|
      document.css("#{element}[#{attribute}]").each do |node|
        verify_reference(node[attribute], route, relative)
      end
    end
    document.css("img[srcset], source[srcset]").each do |node|
      srcset_urls(node["srcset"]).each { |value| verify_reference(value, route, relative) }
    end
    document.css("meta[name^='obsidian:'][content]").each do |node|
      verify_reference(node["content"], route, relative)
    end
  rescue StandardError => exception
    add_error("#{relative || path}: could not inspect HTML: #{exception.class}: #{exception.message}")
  end

  def verify_reference(value, current_route, source)
    return if value.nil? || value.empty?
    return if value.start_with?("mailto:", "tel:")

    scheme = value[/\A([a-z][a-z0-9+.-]*):/i, 1]&.downcase
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

  def verify_csp(value, source)
    directives = value.split(";").filter_map do |part|
      name, *tokens = part.strip.split(/\s+/)
      [name, tokens] unless name.to_s.empty?
    end.to_h
    CSP_DIRECTIVES.each do |name, expected|
      actual = directives[name]
      next if actual && actual.sort == expected.sort

      add_error("#{source}: CSP directive #{name} must be exactly #{expected.join(" ")}")
    end
  end

  def srcset_urls(value)
    value.to_s.split(",").filter_map do |candidate|
      url = candidate.strip.split(/\s+/, 2).first
      url unless url.to_s.empty?
    end
  end

  def verify_json_indexes
    paths = %w[catalog.v1.json graph.v1.json search.v1.json]
      .map { |name| File.join(@site_dir, "assets", "obsidian", name) }
      .select { |path| File.file?(path) }
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
    %w[feed.xml sitemap.xml].each do |name|
      path = File.join(@site_dir, name)
      next unless File.file?(path)
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
