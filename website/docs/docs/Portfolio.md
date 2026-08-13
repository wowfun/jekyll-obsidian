---
publish: true
title: Portfolio
nav_order: 35
tags:
  - guide/portfolio
description: Publish project pages and import a public GitHub README as a project body.
created: 2026-08-07
updated: 2026-08-09
---

# Portfolio

Minimal can turn a source folder into a Portfolio tab, index, and project grid. The compiler decides whether the collection exists and which pages belong to it. Templates and browser code do not inspect the source directory.

## Let Minimal detect the collection

With no Portfolio configuration, Minimal checks the source-relative `portfolio` folder. The collection appears when that folder contains at least one published Markdown project that is not excluded with `nav_exclude: true`.

Detection is recursive. The folder does not qualify when it contains only attachments, drafts, an `index.md`, or excluded projects. The index introduces the collection but is not a project.

Use a different folder, label, order, or tab visibility under `website.navigation`:

```yaml
website:
  theme: minimal
  navigation:
    portfolio:
      path: work
      label: Work
      order: 30
      visible: true
```

`path` is relative to `website.source` and may contain nested POSIX segments. An explicit path replaces `portfolio`; a missing or empty path leaves the collection off. Set `visible: false` to hide the built-in tab without removing the Portfolio index, project routes, or active scope. A custom tab root cannot sit inside the active Portfolio path; Portfolio pages can still join an outside custom tab through `tabs` or a topic match without changing their active Portfolio ownership.

Docs validates the Portfolio configuration but does not create a tab, collection index, or project grid. Notes under that path keep their ordinary Docs classification.

## Write project pages

Under Minimal, every published Markdown descendant of the active Portfolio path belongs to Portfolio and has the effective type `page`. Directory defaults cannot turn it into a post or document. An explicit `content_type: post` or `content_type: doc` is a build error.

Add `nav_exclude: true` to keep a project out of the grid. Its detail route remains public, and opening it still activates the Portfolio tab when that tab is visible.

Projects with `pinned: true` appear before unpinned projects. Within each group, projects with `nav_order` come first, followed by `nav_order`, localized title, and source path. Each card uses its title, optional `image`, and `description`; when `description` is absent, it uses the existing body preview. Missing images and summaries leave no placeholder.

Every project occupies one row. Add `tags`, `author`, or `categories` to a project wrapper to show its Topics on the card and add counted filters to the Portfolio index. These Topics are scoped to Portfolio: they do not enter the Blog filter. The `features.tags` switch controls both Blog and Portfolio topic surfaces.

Local GIF, WebP, AVIF, and APNG files are copied byte for byte and shown with an ordinary image element. The compiler does not transcode them or create thumbnails.

## Add an introduction or custom route

Create `<path>/index.md` to place an authored introduction above the project grid. Its frontmatter, body, translations, outline, graph, and source actions work like any other public note. A `permalink` on that index chooses the Portfolio landing route.

Without an index, the compiler derives the route from a virtual `<path>/index.md` and generates a system page. That page has no source file, Markdown endpoint, comments, or source actions.

## Import a GitHub Markdown file

A Portfolio project can use one public Markdown file from `github.com` as its complete body:

```yaml
---
publish: true
title: Example project
description: A short summary for the Portfolio card.
github_markdown: https://github.com/owner/repository/blob/main/README.md
---
```

The local wrapper body must be empty. Any non-whitespace body produces `github_markdown_body_conflict`. The wrapper still owns publication, title, description, image, pinning, order, route, and other page metadata. It may also declare `related` wiki links; wrapper frontmatter is compiled even though relation syntax inside the imported README is deliberately not interpreted.

The URL shorthand accepts a public GitHub `blob` URL with a single-segment branch, tag, or commit reference. Use the mapping form when a reference contains `/`:

```yaml
github_markdown:
  repository: owner/repository
  ref: release/v2
  path: docs/README.md
```

Only public `github.com` repositories and `.md` or `.markdown` files are supported. Private repositories, access tokens, GitHub Enterprise, Gists, raw URLs, arbitrary hosts, credentials, unknown keys, and paths outside the repository are rejected.

The build resolves the reference to a commit, then reads that exact version. A branch therefore follows its latest commit on the next push, pull request, or manual build, while every page produced by one build uses the same resolved version. No scheduled build is added. If the moving reference cannot be resolved, the build fails instead of publishing a stale cached version.

The exact document is cached by repository, commit, and path. One file may contain at most 1 MiB, and one site may import at most 28 files and 8 MiB in total. The included GitHub Actions workflow shares one verified, immutable materialization between verification and deployment. Standard tests use local fixtures and do not contact GitHub.

## Understand imported content

Imported files use a safe CommonMark and GFM profile. Raw HTML, remote frontmatter, Obsidian wikilinks, transclusions, and block IDs are not interpreted. The first level-one heading is preserved, and the page shell does not add a duplicate title. The text participates in the project page, outline, preview, Search, and View as Markdown output, but it does not create remote Graph relations or recursively import linked Markdown files.

Fragment-only links stay on the project page. Relative links point to the matching file or directory at the resolved GitHub commit; write directory targets with a trailing `/`, while extensionless files such as `LICENSE` remain file links. Relative images use the raw form of that same commit. A relative path cannot escape the repository root.

Edit continues to open the local wrapper. View imported Markdown opens the exact GitHub commit that supplied the body. GitHub-backed cards and their detail-page source actions also link to the repository root; that URL is derived from the validated `github_markdown.repository`, so the wrapper does not duplicate it. A translated wrapper can declare a different `github_markdown` file. If the translated wrapper does not exist, the normal localized fallback displays the default-language project and remains excluded from indexing.

## Troubleshoot Portfolio

| Symptom | Check |
| --- | --- |
| The Portfolio tab is absent | Confirm that Minimal is active and the configured path contains a published project without `nav_exclude: true`. |
| The index exists but the collection is absent | `index.md` does not count as a project. Add a separate published Markdown file. |
| A project reports a content type conflict | Remove an explicit `post` or `doc` type. Portfolio projects are pages. |
| An imported body conflicts with local content | Keep the wrapper frontmatter, then remove every non-whitespace character after it. |
| A GitHub link fails validation | Use a public `github.com` Markdown file. Use the mapping form for a reference that contains `/`. |
| A branch update is not visible | Push or manually run the Pages workflow. Branch content refreshes during a build, not on a timer. |

See [[Customization#Minimal navigation|Customization]] for the complete navigation configuration and [[Localization|Localization]] for translation ownership.
