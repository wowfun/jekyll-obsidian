---
publish: true
title: Jekyll Obsidian
content_type: page
aliases:
  - Site home
tags:
  - jekyll-obsidian
  - guide
description: One Obsidian vault, two intentional site models.
image: assets/research-folio.svg
cssclasses:
  - website-home
created: 2026-07-31
updated: 2026-08-04
---

# One vault, two ways to publish

This site is both starter content and the manual for `jekyll-obsidian`. Every page began as an ordinary Markdown note in this vault. Minimal combines a Home page, Blog, Docs, and custom sections; Docs provides a focused handbook.

> [!note] Open the source in Obsidian
> The compiler reads `website/docs/`, but never rewrites the vault. Open this directory directly and keep using links, properties, callouts, and embeds in Obsidian.

![An annotated folio connecting notes, tags, and source material](assets/research-folio.svg)

## Begin here

- [[Integration|Host Integration]] covers copying `website/` into another repository.
- [[Getting Started]] covers local authoring and the publication boundary.
- [[Syntax]] lists the Obsidian-flavored Markdown supported in v1.
- [[Customization]] explains type, color, navigation, and repository links.
- [[Comments]] explains GitHub Discussions setup and comment-thread behavior.
- [[Localization]] explains locale manifests, translation overlays, fallback pages, and SEO behavior.
- [[Deployment]] follows the GitHub Pages workflow from pull request to release.
- [[docs/development/index|Developer Guide]] covers contributor setup, architecture, and the OFM contract.
- [[中文示例|CJK showcase]] demonstrates Chinese, Japanese, and mixed-script search.

## A useful constraint

The repository is public source material. The publication policy controls generated site output, not access to committed files. Keep truly private notes in another vault or an uncommitted location.

Minimal is the default build and deployment theme. Docs is the standalone handbook. Both use the same authored content routes without bringing Docs navigation into the general-purpose experience.
