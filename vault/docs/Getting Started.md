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
updated: 2026-07-31
---

# Getting Started

The template keeps the writing workflow inside `vault/` and the publishing workflow outside it. Obsidian can open the folder without conversion or a special export step.

## Install the toolchain

Install Ruby 4.0.6, Node.js 26.3.1, and Git. Then run these commands from the repository root:

```sh
bin/setup
bin/dev
```

`bin/setup` installs the locked Ruby and Node dependencies. `bin/dev` builds frontend assets, watches the vault and site sources, and serves the resulting `_site` directory.

## Publish one note

Create a Markdown file anywhere under `vault/`. Add frontmatter with a YAML boolean:

```yaml
---
publish: true
title: My first note
tags:
  - fieldwork
---
```

The value must be the boolean `true`. The strings `"true"` and `"yes"` are invalid. A Markdown file without frontmatter, or with `publish: false`, stays out of HTML, search, graph data, feeds, sitemaps, and copied assets.

## Add links and attachments

Use the same syntax you use in Obsidian:

```md
Read [[Architecture#Compiler boundary]].
![[Architecture#^compiler-contract]]
![[assets/research-folio.svg|640]]
```

Only attachments reached from public notes, their `image` property, or their transclusion closure are copied. Files found only in private notes are ignored.

## Check before a push

Run:

```sh
RUN_BROWSER_TESTS=1 bin/test
JEKYLL_ENV=production bin/build \
  --url https://example.test \
  --baseurl /jekyll-obsidian \
  --destination _site
```

Install the local browser once with `npx playwright install chromium`. Without `RUN_BROWSER_TESTS=1`, `bin/test` runs the Ruby and TypeScript suites and reports that browser coverage was skipped.

The production build fails on ambiguous or private embeds, cycles, path escapes, symlinks, and URL collisions. Ordinary unresolved links stay visible and produce warnings.

Try `bin/dev --theme blog`, `bin/dev --theme docs`, or `bin/dev --theme digital-garden` against this same vault. Continue with [[Syntax]] or review the [[Deployment]] path.
