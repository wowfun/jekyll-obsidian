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

If your repository already has a `Gemfile` or `Gemfile.lock`, complete [[Integration#Use Bundler|Use Bundler]] first. The Action requires both files and a locked builder version matching its release.

Copy [the configuration example](https://github.com/wowfun/jekyll-obsidian/blob/v0.3.2/examples/jekyll-obsidian.yml) to `.github/jekyll-obsidian.yml` and [the Pages workflow](https://github.com/wowfun/jekyll-obsidian/blob/v0.3.2/examples/pages.yml) to `.github/workflows/pages.yml`.

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

All configuration entries are editable, including `source` and `theme`. Changes take effect on the next build. See [[Publishing|Publishing content]] for publication rules and [[Customization|Customization]] for theme and feature settings.

## Use Bundler

For a project with a Gemfile:

```ruby
source "https://rubygems.org"
gem "jekyll-obsidian-site", "0.3.2"
```

```sh
bundle install
bundle exec jekyll-obsidian init --source docs
bundle exec jekyll-obsidian dev
```

Commit `Gemfile` and `Gemfile.lock` to pin dependencies for both local builds and the Action. When both files exist at the repository root, the Action installs the locked bundle in frozen mode and runs the CLI through `bundle exec`. It never generates or updates your lockfile. The locked `jekyll-obsidian-site` version must match the Action release.

With neither file, the Action installs its exact builder gem version directly. Indirect dependencies then follow the gem's version constraints. Having only one of the two files, omitting the builder from the lockfile, or locking a different builder version is an error. Keep the Action reference, Gemfile, and lockfile aligned when upgrading.

An existing Jekyll `_config.yml` and its plugins are not loaded by this tool.

## Update

**Upgrading to 0.3.2:** `source`, `published`, and `lang` now have defined frontmatter types instead of accepting arbitrary custom-property values. `source` must be an absolute HTTP(S) URL without credentials; rename free-text source descriptions to another property, such as `source_name`. `published` is a publication date; use `publish: true` or `publish: false` to control visibility. `lang` must be a BCP 47-style language tag, such as `en` or `zh-CN`. Invalid legacy values now stop the build with `invalid_property`; upgrades do not rewrite your notes. These changes take effect in 0.3.2.

`source_title` is also a defined string property. Quote numeric labels (`source_title: "123"`) and replace array or mapping values with the intended plain-text label; otherwise the build reports `invalid_property`.

Move Markdown image dimensions out of the destination: change `![Diagram](image.png|640x360)` to `![Diagram|640x360](image.png)`. A pipe in a Markdown destination is now part of the filename, so the old form can fail with `missing_embed` or select a literal matching filename. Wiki embeds such as `![[image.png|640x360]]` retain their size syntax. No compatibility fallback or automatic source rewrite is applied.

Change `uses: wowfun/jekyll-obsidian@v0.3.2` in the workflow to the desired release tag. The Action installs that release's exact gem version.

For Bundler, change the `jekyll-obsidian-site` version constraint in `Gemfile` to the same release, run `bundle update jekyll-obsidian-site`, and commit `Gemfile`, `Gemfile.lock`, and the workflow together. Running `bundle update` alone cannot upgrade an exact Gemfile pin. For a standalone local installation, use `gem update jekyll-obsidian-site`. Package updates do not rewrite host content or configuration.

The earlier copied-workspace installation is not supported by this release. Preserve your content and `.github/jekyll-obsidian.yml`, remove its managed-marker comments, replace the old workflow, and remove the old implementation files. Keep any user-authored files under `website/`.

## Preview and build

`jekyll-obsidian dev` serves `http://127.0.0.1:58000/` and watches content and configuration. Failed rebuilds preserve the last successful output.

```sh
jekyll-obsidian build --url https://example.com --baseurl /project
jekyll-obsidian clean
```

The built site is `.jekyll-obsidian-cache/site/`. `clean` removes the tool's cached state and output while retaining notes, configuration, installed dependencies, and unrelated `_site/` directories. The installed gem is read-only during use.

Builds create an isolated Jekyll source under the host's `.jekyll-obsidian-cache/runtime/` using package-owned templates. The host's existing `_config.yml` and plugins do not participate. Use the `jekyll-obsidian` commands to build the site.

## Troubleshooting

- Missing configuration: run `init` in the repository root, or add the two example files.
- No public notes: add YAML boolean `publish: true`, or explicitly configure `website.content.publish_by_default`.
- Existing files conflict with `init`: edit those files directly; the command does not overwrite them.
- Installation selects a different project: the gem name is **jekyll-obsidian-site**, while the command name is **jekyll-obsidian**.
- Source or cache path contains a symbolic link: select a real directory inside the repository.
