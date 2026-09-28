---
publish: true
title: Host Integration
nav_order: 60
tags:
  - guide/integration
  - github-pages
description: Install the site builder through RubyGems or GitHub Actions while keeping content and configuration in your repository.
created: 2026-08-02
updated: 2026-08-22
---

# Host integration

A host repository needs content, `.github/jekyll-obsidian.yml`, and a Pages workflow. The `jekyll-obsidian-site` gem supplies the compiler, themes, and prebuilt frontend assets. Its executable is `jekyll-obsidian`.

## Deploy without installing a toolchain

Copy [the configuration example](https://github.com/wowfun/jekyll-obsidian/blob/v0.2.0/examples/jekyll-obsidian.yml) to `.github/jekyll-obsidian.yml` and [the Pages workflow](https://github.com/wowfun/jekyll-obsidian/blob/v0.2.0/examples/pages.yml) to `.github/workflows/pages.yml`.

```yaml
title: My Site
website:
  source: docs
  theme: minimal
```

Add a Markdown note with `publish: true` in `docs/`. Select **Settings > Pages > Build and deployment > Source > GitHub Actions**, then commit and push. Actions installs Ruby and the matching gem version; your computer does not need Ruby or Node.js.

`website.source` is relative to your repository root. `docs/`, `website/docs/`, and nested directories with spaces or Unicode names are supported. The project's own documentation lives in `website/jekyll-obsidian-docs/` and is excluded from the gem.

## Initialize locally

Install Ruby 4.0.x on macOS, Linux, or WSL, then run these commands from your repository root:

```sh
gem install jekyll-obsidian-site
jekyll-obsidian init --source website/docs --theme docs
jekyll-obsidian dev
```

`init` creates the configuration and Pages workflow. It creates a public welcome note only if the content directory is missing or empty. Repeating the same initialization leaves matching files unchanged; a conflict is reported before any files are written. For an existing configuration or workflow, edit the files directly using the examples above.

All configuration entries are editable, including `source` and `theme`. Changes take effect on the next build. See [[Customization|Customization]] for publication defaults and features.

## Use Bundler

For a project with a Gemfile:

```ruby
source "https://rubygems.org"
gem "jekyll-obsidian-site", "~> 0.2.0"
```

```sh
bundle install
bundle exec jekyll-obsidian init --source docs
bundle exec jekyll-obsidian dev
```

Commit `Gemfile` and `Gemfile.lock` to pin local dependencies. The Action selects its matching gem version independently, so keep its release reference aligned with your local gem version. An existing Jekyll `_config.yml` and its plugins are not loaded by this tool.

## Update

Change `uses: wowfun/jekyll-obsidian@v0.2.0` in the workflow to the desired release tag. The Action installs that release's exact gem version.

For a direct installation, use `gem update jekyll-obsidian-site`. For Bundler, adjust the version constraint when necessary, run `bundle update jekyll-obsidian-site`, and commit the lockfile. Package updates do not rewrite host content or configuration.

The earlier copied-workspace installation is not supported by this release. Preserve your content and `.github/jekyll-obsidian.yml`, remove its managed-marker comments, replace the old workflow, and remove the old implementation files. Keep any user-authored files under `website/`.

## Preview and build

`jekyll-obsidian dev` serves `http://127.0.0.1:58000/` and watches content and configuration. Failed rebuilds preserve the last successful output.

```sh
jekyll-obsidian build --url https://example.com --baseurl /project
jekyll-obsidian clean
```

The built site is `.jekyll-obsidian-cache/site/`. `clean` removes the tool's cached state and output while retaining notes, configuration, installed dependencies, and unrelated `_site/` directories. The installed gem is read-only during use.

## Troubleshooting

- Missing configuration: run `init` in the repository root, or add the two example files.
- No public notes: add YAML boolean `publish: true`, or explicitly configure `website.content.publish_by_default`.
- Existing files conflict with `init`: edit those files directly; the command does not overwrite them.
- Installation selects a different project: the gem name is **jekyll-obsidian-site**, while the command name is **jekyll-obsidian**.
- Source or cache path contains a symbolic link: select a real directory inside the repository.
