---
publish: true
title: Getting Started
nav_order: 10
aliases:
  - Setup
tags:
  - guide/getting-started
description: Configure a site, publish the first note, and run the local server.
created: 2026-07-31
updated: 2026-08-02
---

# Getting Started

The bundled vault lives in `website/docs/`; the publishing workflow stays in `website/`. Obsidian opens the content folder without conversion or a special export step.

## Install the toolchain

To integrate this site into another repository without installing Ruby or Node.js, follow [[Integration|Host Integration]]. The dependency-free integration command generates the host configuration and Pages workflow; GitHub Actions installs the complete build toolchain remotely.

For local preview, install Ruby 4.0.x, Node.js 26.x, and Git on macOS, Linux, or WSL. CI pins the exact patch versions used by the repository. Then run these commands from the repository root:

```sh
website/bin/setup
website/bin/dev
```

`website/bin/setup` installs the locked Ruby and Node dependencies under `website/`. `website/bin/dev` watches the configured content directory and the site sources, rebuilds frontend assets only when their inputs change, and serves `website/_site` with the Minimal theme by default. Pass `--theme docs` to preview the standalone handbook.

Native Windows initialization and Pages deployment use `website\bin\integrate.cmd`; use WSL when a local Jekyll preview is required.

## Publish one note

Create a Markdown file under `website/docs/`. Add frontmatter with a YAML boolean:

```yaml
---
publish: true
title: My first note
tags:
  - fieldwork
---
```

The value must be the boolean `true`. The strings `"true"` and `"yes"` are invalid. Without publication defaults, a Markdown file that omits `publish` stays out of HTML, search, graph data, feeds, sitemaps, and copied assets.

To publish a directory recursively, add its source-relative path to `website.content.publish_by_default`. The special path `.` selects the complete content tree. Within that scope, set `publish: false` on an individual note to keep it out of the site. An explicit `publish: true` can still include a note outside the configured directories. The configured content directory's `.obsidian/` and `.trash/` trees are excluded before this publication check.

## Add links and attachments

Use the same syntax you use in Obsidian:

```md
Read [[docs/development/architecture#Compiler boundary]].
![[docs/development/architecture#^compiler-contract]]
![[assets/research-folio.svg|640]]
```

Only attachments reached from public notes, their `image` property, or their transclusion closure are copied. An `image` property also supplies the page's public `og:image` URL. Files found only in private notes are ignored.

## Check before a push

Build the configured content with production checks before publishing:

```sh
JEKYLL_ENV=production website/bin/build \
  --url https://example.test \
  --baseurl /jekyll-obsidian \
  --destination _site
```

The build command resolves `_site` inside the site directory and writes `website/_site`. Contributors changing the implementation should also run the test suites documented in [[docs/development/index|Developer Guide]].

The production build fails on ambiguous or private embeds, cycles, path escapes, symlinks, and URL collisions. Ordinary unresolved links stay visible and produce warnings.

Continue with [[docs/Syntax|Syntax]] or review the [[docs/Deployment|Deployment]] path.
