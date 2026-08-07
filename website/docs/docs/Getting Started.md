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
updated: 2026-08-07
---

# Getting Started

Jekyll Obsidian publishes any folder of Markdown files, including an Obsidian vault. Keep writing in Obsidian or another text editor, then push. GitHub Actions installs the build tools, checks the content, and deploys the site to Pages. You do not need Ruby, Node.js, or a local build command for this path.

The bundled content lives in `website/docs/`; the publishing implementation stays in `website/`. Obsidian opens the content folder without conversion or a special export step.

## Publish through GitHub Actions

When adding Jekyll Obsidian to another repository, copy the complete `website/` directory and follow [[Integration|Host Integration]]. Its dependency-free command creates the host configuration and Pages workflow without installing Ruby or Node.js:

```sh
website/bin/integrate --source docs
```

Commit the content directory, `website/`, and the generated `.github/` files. In GitHub, set **Settings → Pages → Build and deployment → Source** to **GitHub Actions**, then push. The **Verify and deploy Pages** workflow reports the final URL after deployment.

## Publish one note

Create a Markdown file in the configured content directory. Add frontmatter with a YAML boolean:

```yaml
---
publish: true
title: My first note
tags:
  - fieldwork
---
```

The value must be the boolean `true`. The strings `"true"` and `"yes"` are invalid. Without publication defaults, a Markdown file that omits `publish` stays out of HTML, Search, Graph data, feeds, sitemaps, and copied assets.

To publish a directory recursively, add its source-relative path to `website.content.publish_by_default`. The special path `.` selects the complete content tree. Within that scope, set `publish: false` on an individual note to keep it out of the site. An explicit `publish: true` can still include a note outside the configured directories. The configured content directory's `.obsidian/` and `.trash/` trees are excluded before this publication check.

The publication policy controls generated output, not repository access. Keep secrets, personal records, and other private material out of a repository that other people can read.

## Add links and attachments

Use the same syntax you use in Obsidian:

```md
Read [[docs/development/architecture#Compiler boundary]].
![[docs/development/architecture#^compiler-contract]]
![[assets/research-folio.svg|640]]
```

Only attachments reached from public notes, their `image` property, or their transclusion closure are copied. An `image` property also supplies the page's public `og:image` URL. Files found only in private notes are ignored. [[Syntax|Syntax]] documents the complete authoring contract.

## Let the workflow check a push

Every pull request and default-branch push runs the production compiler and project checks. A production build stops on ambiguous or private embeds, cycles, path escapes, symlinks, and URL collisions. Ordinary unresolved links stay visible and produce warnings.

Open the workflow result before merging or sharing the site. The deployment job and **Settings → Pages** show the published URL. [[Deployment|Deployment]] explains project paths, custom domains, and the trusted deployment job.

## Optional local preview

Install Ruby 4.0.x, Node.js 26.x, and Git only when you want a local preview or plan to change the implementation. Use macOS, Linux, or WSL; native Windows users can integrate and deploy with `website\bin\integrate.cmd`, then use WSL for Jekyll development commands.

Run from the repository root:

```sh
website/bin/setup
website/bin/dev
```

`website/bin/setup` installs the locked Ruby and Node dependencies under `website/`. `website/bin/dev` watches the configured content and site sources, rebuilds frontend assets when needed, and serves `website/_site` with Minimal by default. Pass `--theme docs` to preview the handbook.

To reproduce a production build locally:

```sh
JEKYLL_ENV=production website/bin/build \
  --url https://example.test \
  --baseurl /jekyll-obsidian \
  --destination _site
```

The destination resolves below the site directory, so `_site` writes to `website/_site`. Contributors changing the implementation should also follow [[docs/development/index|Developer Guide]].

Continue with [[Syntax|Syntax]], [[Customization|Customization]], or [[Portfolio|Portfolio]].
