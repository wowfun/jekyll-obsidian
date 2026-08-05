---
publish: true
title: One vault, two site models
date: 2026-08-01
tags:
  - release-notes
  - themes
description: Why Minimal and Docs share one compiler but not one layout.
image: assets/research-folio.svg
---

# One vault, two site models

Minimal combines an authored Home page, a chronological Blog, documentation, and custom sections in one general-purpose site. Docs gives the same source notes a focused handbook navigator.

`jekyll-obsidian` keeps one publication and OFM contract, then gives each site model a distinct presenter. Authored URLs stay stable while navigation changes around them.

Read [[docs/development/architecture#Theme presenter seam|Architecture]] for the module seam or [[docs/Customization#Site themes|Customization]] to switch the active theme.
