---
publish: true
title: Architecture
nav_order: 40
tags:
  - guide/architecture
description: How the pure vault compiler and the small Jekyll adapter divide responsibility.
created: 2026-07-31
updated: 2026-07-31
---

# Architecture

The project has three cooperating modules behind one compiler interface: the pure vault compiler, an internal theme presenter seam, and the Jekyll adapter. That shape keeps publication rules testable without a live site, gives three real theme adapters one immutable content model, and keeps Jekyll lifecycle details out of note parsing.

## Reader isolation

Jekyll reads ordinary pages and static files before it runs generators. `_config.yml` excludes the default `vault/`, and an `after_init` hook validates and excludes the configured source before the Reader runs. A highest-priority generator checks the pages, collections, and static files again and stops the build if vault material escaped that boundary.

## Compiler boundary

The compiler receives an immutable snapshot of public-source bytes, attachment metadata, normalized paths, configuration, and optional Git dates. It does not read the filesystem, ask Jekyll for state, use the network, inspect environment variables, or read the current clock. Its sorted result contains pages, generated files, copied assets, and diagnostics. ^compiler-contract

The fixed pipeline is:

1. Validate paths and frontmatter.
2. Select notes with `publish: true`.
3. Scan Obsidian-specific syntax with lexical state.
4. Parse every public note body once with Commonmarker.
5. Build identity, anchor, and relation indexes.
6. Resolve links, embeds, and attachment closure.
7. Resolve the selected built-in theme and feature defaults.
8. Produce themed HTML and deterministic JSON or XML files.

## Identity and relations

A note ID is its NFC-normalized vault-relative path, including `.md`. Relations record source, target, `link` or `embed`, fragment, and source span before rendering. HTML, backlinks, the relation rail, and graph edges all derive from those occurrences.

Embedded links remain relationships of their authored source note. They do not become new relationships of every host that transcludes them.

## Adapter boundary

The adapter takes one filesystem snapshot, optionally scans Git history once, and calls the compiler. It performs a global preflight before it appends any output to Jekyll. Generated HTML, JSON, and XML use pages without source files. Reachable attachments use a controlled static-file subclass because Jekyll's ordinary static files copy existing source files.

The adapter also loads only the selected theme and feature closure from the hashed frontend manifest into `site.data`. Layouts pass routes through Jekyll's URL helpers, so JavaScript never assumes a deployment base path.

## Theme presenter seam

`blog`, `docs`, and `digital-garden` consume the same published model. They select layouts, navigation, homepage additions, and system pages; they never parse Markdown, discover attachments, or recalculate relations. Theme IDs are closed in v1 rather than exposed through a speculative third-party registry.

## Determinism

Generated data is UTF-8, schema-versioned, and stably sorted. No build timestamp is added. Explicit note dates win over Git dates, and the compiler never falls back to the current time. If one public note lacks a deterministic update time, the compiler skips the entire Atom feed and emits a warning.

See [[Syntax]] for the authoring contract and [[Deployment]] for the hosted pipeline.
