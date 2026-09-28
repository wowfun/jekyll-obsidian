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

The project keeps one public compiler interface, `VaultCompiler.compile(BuildRequest)`. Behind it, the pure vault compiler delegates raw HTML authorization and projection to the internal `HtmlPublication` deep module, delegates presentation to the internal theme seam, and hands immutable output to the Jekyll adapter. That shape keeps publication rules testable without a live site, gives two theme adapters one immutable content model, and keeps Jekyll lifecycle details out of note parsing.

## Reader isolation

The runtime creates an isolated Jekyll source under the host's `.jekyll-obsidian-cache/runtime/` and copies only package-owned templates into it. Content is resolved independently from the host repository root, including `website/docs/`. The installed package is read-only. The adapter runs only for sites created with the internal runtime context; ordinary Jekyll sites are unaffected. A highest-priority generator checks pages, collections, and static files and rejects any content that bypassed the compiler through the Reader or a symlink.

## Compiler boundary

The compiler receives an immutable snapshot of public-source bytes, attachment metadata, normalized paths, configuration, and optional Git dates. It does not read the filesystem, ask Jekyll for state, use the network, inspect environment variables, or read the current clock. Its sorted result contains pages, generated files, projected files, and diagnostics. Localization stays behind this same `VaultCompiler.compile(BuildRequest)` interface: one locale plan creates default-authoritative overlay snapshots and combines their immutable outputs before Jekyll receives them. ^compiler-contract

`HtmlPublication.resolve` validates explicit mappings, expands directory bundles, creates the source-to-route index, and emits the stable raw HTML manifest in one pass. Localized compilation reuses that resolution and merges raw HTML once as a shared projection instead of creating locale copies. The manifest is a publication allowlist, not a MIME policy; the deployment server remains responsible for safe `Content-Type` headers and content-sniffing behavior for uncommon extensions.

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

The adapter takes one filesystem snapshot from the content root, optionally scans Git history from the workspace root, and calls the compiler. Frontend assets are read from the package manifest. Runtime caches, staged builds, and the final site belong to the host application cache. The adapter performs a global preflight before it appends any output to Jekyll. Generated HTML, JSON, and XML use pages without source files. Source-backed attachments and raw HTML bundle files share `ProjectedFile` plus a controlled static-file subclass. The adapter pins inode, modification time, and size while atomically staging each projection, so a source cannot change between compilation and Jekyll's copy.

The adapter also loads only the selected theme and feature closure from the hashed frontend manifest into `site.data`. Layouts pass routes through Jekyll's URL helpers, so JavaScript never assumes a deployment base path.

## Theme presenter seam

`minimal` and `docs` consume the same published model. They select layouts, navigation, and homepage additions; they never parse Markdown, discover attachments, or recalculate relations. Shared note features keep one Liquid and frontend implementation across the themes while inheriting each theme's visual tokens. Theme IDs are closed in v1 rather than exposed through a speculative third-party registry. The compiler-owned `SiteNavigation` module discovers built-ins and authored custom roots, resolves folder, explicit-page, and topic membership, assigns active ownership, and emits one ordered interface to both themes. Liquid only renders that projection and never rediscovers tab rules.

`GraphPayload` remains the complete, schema-v1 public graph stored in `graph.v1.json`; it retains isolated and self-link-only nodes, is emitted whenever Graph is enabled, and is fetched only when the complete-graph dialog opens. Data generation is not truncated. The browser's SVG viewer has a separate 250-node/1,000-edge safety boundary and falls back to local graphs or search when a payload exceeds it, avoiding an unbounded DOM and force simulation. When present, the page-level `LocalGraphPayload` is embedded in note data, so the right rail never downloads the full site to discover neighbours. `/graph/` is deliberately not reserved or generated.

Structured comment settings are validated once into an immutable `CommentsConfig`. The shared presenter projects only the small `page.website.comments` interface needed by eligible post pages; Liquid never interprets raw configuration. Giscus is one external implementation owned by the shared frontend, so the project does not expose a hypothetical multi-provider adapter seam. Development output keeps a server-rendered Discussions link without loading the external client, while production pages receive a narrowly scoped CSP profile. Theme defaults are resolved at this boundary: a present i18n mapping defaults on for Docs, and a present comments mapping defaults on for Minimal; explicit YAML booleans override either default for every built-in theme.

## Determinism

Generated data is UTF-8, schema-versioned, and stably sorted. No build timestamp is added. A post's explicit `date` or `created` value wins over its Git first-commit time, and the compiler never falls back to the current time. `updated` is author-optional and is never synthesized from Git history. Atom entries prefer explicit `updated`, then fall back to the publication time for posts; non-post notes without `updated` are omitted, and the feed is skipped only when no timed entries remain.

See [[docs/Syntax|Syntax]] for the authoring contract and [[docs/Deployment|Deployment]] for the hosted pipeline.
