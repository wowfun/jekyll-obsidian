---
publish: true
title: Developer Guide
nav_order: 70
aliases:
  - Development
tags:
  - guide/development
description: Set up the toolchain, run the test suites, and work within the website module boundaries.
created: 2026-08-02
updated: 2026-08-02
---

# Developer Guide

This page is for contributors changing the implementation. To use the published gem or Action in another repository, follow [[docs/Integration|Host Integration]].

## Workspace boundary

`website/` contains the compiler, templates, frontend sources, dependencies, and tests. Project documentation lives in `website/jekyll-obsidian-docs/`. The gem includes runtime files and compiled assets only. Host content and configuration remain independent of the installation directory.

Runtime output is under the host root's `.jekyll-obsidian-cache/`. Frontend development assets are under `website/.jekyll-obsidian-cache/assets/`; packaging copies the selected build into `website/assets/`, which is ignored by Git.

## Set up the toolchain

Install Ruby 4.0.x, Node.js 26.x, and Git on macOS, Linux, or WSL. From the repository root:

```sh
website/bin/setup
website/bin/dev
```

Setup installs locked Ruby and Node dependencies and builds the gem. After editing frontend sources, rerun the package command before previewing. Restart the preview after changing Ruby implementation files.

## Run the tests

```sh
website/bin/test
```

This builds assets and the gem, runs compiler and runtime tests, installs the actual gem in an isolated host, then runs TypeScript and Node tests. The package smoke test makes package files read-only and rejects Node/npm execution during the host build.

For browser coverage:

```sh
(cd website && npx playwright install --with-deps chromium)
RUN_BROWSER_TESTS=1 website/bin/test
```

The project workflow runs this full suite. Downstream workflows build and verify only their host content.

## Build a production fixture

```sh
website/bin/build --example --theme minimal \
  --url https://example.test --baseurl /jekyll-obsidian \
  --destination site-fixture
```

The output is `.jekyll-obsidian-cache/site-fixture/`. The contributor wrapper builds frontend assets and then calls the same runtime as the installed gem. `--skip-assets` reuses an existing frontend build.

## Build and release a gem

```sh
(cd website && bundle exec ruby scripts/package.rb)
```

The gem is written to `pkg/`. The package task requires a complete asset manifest and excludes project documentation, tests, Node dependencies, and caches. See [[docs/development/releasing|Releasing]] for the first publication and the versioned Action.

## Authored content trust

Raw HTML in public notes is trusted author input. The compiler removes HTML and Obsidian comments, rejects dangerous Markdown URL schemes, and does not publish local attachments referenced only by raw HTML attributes.

Production pages include a meta Content Security Policy. Review authored HTML and linked HTTPS media before publishing.

Continue with [[docs/development/architecture|Architecture]], [[docs/development/ofm-conformance|OFM v1 Conformance]], or [[docs/Deployment|Deployment]].
