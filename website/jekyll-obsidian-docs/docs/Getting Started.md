---
publish: true
title: Getting Started
nav_order: 10
aliases:
  - Setup
tags:
  - guide/getting-started
description: Publish a Markdown folder through GitHub Actions, with local preview available when you need it.
created: 2026-07-31
updated: 2026-08-22
---

# Getting Started

Jekyll Obsidian publishes a Markdown folder or Obsidian vault as a blog or documentation site. You can publish entirely through GitHub Actions, then add local preview when you need it.

## Publish through GitHub Actions

Follow [[Integration|Host Integration]] to add the configuration and workflow. Choose a content directory, such as `docs/` or `website/docs/`, and select GitHub Actions as the Pages publishing source. Push your changes to publish.

Only notes with YAML boolean `publish: true` are public by default:

```yaml
---
publish: true
title: My first note
---
```

To publish a whole directory, explicitly add it to `website.content.publish_by_default`. Paths are relative to the content directory; `.` selects the whole content tree. A note with `publish: false` remains excluded. The publication policy does not make files in a public Git repository private.

## Write and link notes

Open the content folder in Obsidian or a text editor. Wiki links, embeds, callouts, and supported Markdown are compiled without rewriting your source. See [[Syntax|Syntax]] for the authoring contract.

A public root `index.md` becomes the home page. Without a physical `index.md`, a public `README.md` can fill that role. Directories do not need an index file; the site can link to the first public page. At least one public note is required.

## Configure the site

Edit `.github/jekyll-obsidian.yml` directly. Use `website.theme: minimal` for a site with Home, Blog, and custom sections, or `website.theme: docs` for a documentation tree. Changing the theme does not change note URLs. See [[Customization|Customization]] for navigation and features.

## Preview locally

With Ruby 4.0.x on macOS, Linux, or WSL:

```sh
gem install jekyll-obsidian-site
jekyll-obsidian dev
```

Open `http://127.0.0.1:58000/`. Content and configuration changes trigger complete rebuilds. Failed rebuilds preserve the last successful site. Use `jekyll-obsidian dev --theme docs` for a temporary theme override.

## Deploy and update

Find the site URL under **Settings > Pages** or in the workflow's deployment result. Actions reads Pages metadata for the domain and base path. See [[Deployment|Deployment]] for custom domains.

Update the Action's pinned release reference, or use RubyGems/Bundler for a local installation. See [[Integration|Host Integration]] for the exact commands. Project development instructions are in [[docs/development/index|Developer Guide]].
