---
publish: true
title: Architecture
nav_order: 10
permalink: /docs/Architecture/
tags:
  - guide/development
  - guide/architecture
description: How the pure vault compiler and the filesystem-facing Jekyll adapter divide responsibility.
created: 2026-07-31
updated: 2026-08-06
---

# Architecture

The project has three cooperating modules behind one compiler interface: the pure vault compiler, an internal theme presenter seam, and the Jekyll adapter. That shape keeps publication rules testable without a live site, gives two theme adapters one immutable content model, and keeps Jekyll lifecycle details out of note parsing.

## Reader isolation

`website/` is the Jekyll source, while the configured content directory is resolved from the host repository root. The bundled `website/docs/` vault is the one controlled site-local exception; an `after_init` hook resolves the workspace and excludes that directory before Jekyll's Reader runs. External host content such as `docs/` remains outside the site directory. A highest-priority generator checks Jekyll pages, collections, and static files again and stops the build if Reader isolation was bypassed through configuration or a symlink.

## Compiler boundary

The compiler receives an immutable snapshot of public-source bytes, attachment metadata, normalized paths, configuration, and optional Git dates. It does not read the filesystem, ask Jekyll for state, use the network, inspect environment variables, or read the current clock. Its sorted result contains pages, generated files, copied assets, and diagnostics. Localization stays behind this same `VaultCompiler.compile(BuildRequest)` interface: one locale plan creates default-authoritative overlay snapshots and combines their immutable outputs before Jekyll receives them. ^compiler-contract

The fixed pipeline is:

1. Validate the build configuration and, when i18n is enabled, its locale plan and manifests.
2. Build the default snapshot and same-path translation overlays.
3. Resolve one content policy, then use it in each locale partition to validate paths, select default-language notes, and apply translation opt-outs.
4. Scan Obsidian-specific syntax with lexical state and parse each partition's public note bodies with Commonmarker.
5. Build locale-local identity, anchor, and relation indexes.
6. Resolve links, embeds, and attachment closure within that partition.
7. Resolve the selected built-in theme and feature defaults.
8. Produce themed HTML and deterministic locale-specific JSON or XML files.
9. Combine the immutable partitions, shared attachments, routes, and reciprocal SEO metadata.

## Identity and relations

A note ID is its NFC-normalized vault-relative path, including `.md`. Relations record source, target, `link` or `embed`, fragment, and source span before rendering. HTML, backlinks, the relation rail, and graph edges all derive from those occurrences. The published model also records each node's complete-graph degree. The presenter projects a `LocalGraphPayload` only for a note with at least one different one-hop neighbour: the current note, all such neighbours, and every incident typed edge, stably sorted inside the current locale partition. A self-link alone does not create a page-local payload.

Embedded links remain relationships of their authored source note. They do not become new relationships of every host that transcludes them.

## Adapter boundary

The adapter takes one filesystem snapshot from the content root, optionally scans Git history from the workspace root, and calls the compiler. Jekyll and frontend assets continue to use the site root, while caches and destinations stay below it. The adapter performs a global preflight before it appends any output to Jekyll. Generated HTML, JSON, and XML use pages without source files. Reachable attachments use a controlled static-file subclass because Jekyll's ordinary static files copy existing source files.

The adapter also loads only the selected theme and feature closure from the hashed frontend manifest into `site.data`. Layouts pass routes through Jekyll's URL helpers, so JavaScript never assumes a deployment base path.

## Theme presenter seam

`minimal` and `docs` consume the same published model. They select layouts, navigation, and homepage additions; they never parse Markdown, discover attachments, or recalculate relations. Shared note features keep one Liquid and frontend implementation across the themes while inheriting each theme's visual tokens. Theme IDs are closed in v1 rather than exposed through a speculative third-party registry. The compiler also owns Minimal's `SiteNavigation` projection, so Liquid receives one ordered interface for built-in, folder, and page tabs instead of rediscovering navigation rules.

`GraphPayload` remains the complete, schema-v1 public graph stored in `graph.v1.json`; it retains isolated and self-link-only nodes, is emitted whenever Graph is enabled, and is fetched only when the complete-graph dialog opens. Data generation is not truncated. The browser's SVG viewer has a separate 250-node/1,000-edge safety boundary and falls back to local graphs or search when a payload exceeds it, avoiding an unbounded DOM and force simulation. When present, the page-level `LocalGraphPayload` is embedded in note data, so the right rail never downloads the full site to discover neighbours. `/graph/` is deliberately not reserved or generated.

Structured comment settings are validated once into an immutable `CommentsConfig`. The shared presenter projects only the small `page.website.comments` interface needed by eligible post pages; Liquid never interprets raw configuration. Giscus is one external implementation owned by the shared frontend, so the project does not expose a hypothetical multi-provider adapter seam. Development output keeps a server-rendered Discussions link without loading the external client, while production pages receive a narrowly scoped CSP profile. Theme defaults are resolved at this boundary: a present i18n mapping defaults on for Docs, and a present comments mapping defaults on for Minimal; explicit YAML booleans override either default for every built-in theme.

## Determinism

Generated data is UTF-8, schema-versioned, and stably sorted. No build timestamp is added. A post's explicit `date` or `created` value wins over its Git first-commit time, and the compiler never falls back to the current time. `updated` is author-optional and is never synthesized from Git history. Atom entries prefer explicit `updated`, then fall back to the publication time for posts; non-post notes without `updated` are omitted, and the feed is skipped only when no timed entries remain.

See [[docs/Syntax|Syntax]] for the authoring contract and [[docs/Deployment|Deployment]] for the hosted pipeline.
