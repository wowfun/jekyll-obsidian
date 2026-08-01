---
publish: true
title: Jekyll Obsidian
content_type: page
aliases:
  - Site home
tags:
  - jekyll-obsidian
  - guide
description: One Obsidian vault, three intentional ways to publish it.
image: assets/research-folio.svg
cssclasses:
  - obsidian-home
created: 2026-07-31
updated: 2026-07-31
---

# One vault, three ways to publish

This site is both starter content and the manual for `jekyll-obsidian`. Every page began as an ordinary Markdown note in this vault; the configured theme decides whether the result reads as a blog, a handbook, or a digital garden.

> [!note] Open the source in Obsidian
> The site compiler reads `vault/`, but it never rewrites the vault. Open this directory directly and keep using links, properties, callouts, and embeds in Obsidian.

![An annotated folio connecting notes, tags, and source material](assets/research-folio.svg)

## Begin here

- [[Getting Started]] covers the first local build and the publication boundary.
- [[Syntax]] lists the Obsidian-flavored Markdown supported in v1.
- [[Customization]] explains type, color, navigation, and repository links.
- [[Deployment]] follows the GitHub Pages workflow from pull request to release.
- [[Architecture]] describes the compiler and the Jekyll adapter.
- [[中文示例|CJK showcase]] demonstrates Chinese, Japanese, and mixed-script search.

## A useful constraint

The repository is public source material. `publish: true` controls generated site output, not access to committed files. Keep truly private notes in another vault or an uncommitted location.

With the default digital-garden theme, the relation rail beside this page is derived from authored links. Blog and Docs use the same relationships and routes without forcing garden navigation into their reading models.
