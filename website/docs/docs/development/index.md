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

This page is for contributors changing the implementation under `website/`. If you only copy `website/` into another repository, follow [[docs/Integration|Host Integration]] instead.

## Workspace boundary

`website/` owns the Jekyll source, compiler, themes, frontend assets, dependencies, caches, tests, and generated output. A host repository supplies content and deployment configuration. Its content normally stays outside `website/`, and the generated workflow remains at the GitHub-required root path `.github/workflows/pages.yml`.

The supported commands resolve paths, configuration overlays, and caches against this boundary. Run them from the repository root. Direct `jekyll` commands do not load the host configuration or the adapter's ownership safeguards.

## Set up the toolchain

Install Ruby 4.0.x, Node.js 26.x, and Git on macOS, Linux, or WSL. Then run:

```sh
website/bin/setup
```

The setup command installs locked Ruby and Node dependencies under `website/` and builds the frontend assets.

## Run the tests

The default test command checks the POSIX integration contract, build command contract, frontend asset build, Ruby suite, and TypeScript suite:

```sh
website/bin/test
```

Install Chromium once and enable browser coverage when changing layouts, styles, navigation, or client-side features:

```sh
(cd website && npx playwright install chromium)
RUN_BROWSER_TESTS=1 website/bin/test
```

The generated GitHub Actions workflow runs browser coverage, builds every bundled theme at root and project paths, validates the host content, audits the result, and deploys only from trusted default-branch builds.

## Build a production fixture

Use an explicit origin and base path when checking generated URLs:

```sh
JEKYLL_ENV=production website/bin/build \
  --example \
  --theme minimal \
  --url https://example.test \
  --baseurl /jekyll-obsidian \
  --destination _site
```

The destination is resolved inside `website/`, so this command writes `website/_site`.

## Authored content trust

Raw HTML in public notes is trusted author input. The compiler removes HTML comments and Obsidian comments, rejects dangerous Markdown URL schemes, and does not publish local attachments referenced only by raw HTML attributes.

Production pages include a meta Content Security Policy. GitHub Pages cannot promote it to a response header, so it is a browser-side safeguard rather than a complete hosting boundary. Review authored HTML and linked HTTPS media before publishing.

Continue with [[docs/development/architecture|Architecture]] for compiler and adapter seams, [[docs/development/ofm-conformance|OFM v1 Conformance]] for the pinned authoring contract, or [[docs/Deployment|Deployment]] for the hosted pipeline.
