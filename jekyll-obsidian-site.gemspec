# frozen_string_literal: true

require_relative "website/lib/jekyll_obsidian/version"

Gem::Specification.new do |spec|
  spec.name = JekyllObsidian::GEM_NAME
  spec.version = JekyllObsidian::VERSION
  spec.authors = ["wowfun"]
  spec.summary = "Publish Markdown and Obsidian folders as Jekyll websites."
  spec.description = "A Markdown compiler, two site themes, and a CLI with prebuilt frontend assets."
  spec.homepage = "https://github.com/wowfun/jekyll-obsidian"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0", "< 4.1"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "documentation_uri" => "https://sinputer.top/jekyll-obsidian/",
    "allowed_push_host" => "https://rubygems.org"
  }
  spec.require_paths = ["website/lib"]
  spec.bindir = "website/exe"
  spec.executables = ["jekyll-obsidian"]
  spec.files = Dir.chdir(__dir__) do
    Dir.glob("{LICENSE,README.md,website/{lib,exe,_layouts,_includes,assets}/**/*,website/_config.yml,website/scripts/{audit-site.rb,verify-site-urls.rb,templates/pages.yml}}")
      .select { |path| File.file?(path) }.sort
  end
  spec.add_runtime_dependency "jekyll", "4.4.1"
  spec.add_runtime_dependency "commonmarker", "2.9.0"
  spec.add_runtime_dependency "cgi", "~> 0.5"
  spec.add_runtime_dependency "nokogiri", "~> 1.18"
  spec.add_runtime_dependency "listen", "~> 3.10"
  spec.add_runtime_dependency "webrick", "~> 1.9"
end
