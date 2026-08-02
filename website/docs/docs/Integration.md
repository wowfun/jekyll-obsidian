---
publish: true
title: Host Integration
nav_order: 60
tags:
  - guide/integration
  - github-pages
description: Add the website workspace to another repository and deploy its documentation without a local build toolchain.
created: 2026-08-02
updated: 2026-08-02
---

# Host integration

Copy the complete `website/` directory to the root of a host repository. The host content remains outside that directory, so the publishing implementation can be replaced or updated without moving the authored notes.

## Deploy without installing a toolchain

The host must already contain a public root note such as `docs/index.md`:

```yaml
---
publish: true
title: Documentation
---
```

On macOS, Linux, or WSL, run from the host repository root:

```sh
website/bin/integrate
```

On native Windows, run from Command Prompt:

```bat
website\bin\integrate.cmd
```

Or from PowerShell:

```powershell
.\website\bin\integrate.cmd
```

The CMD launcher uses PowerShell 7 when it is available and otherwise falls back to Windows PowerShell 5.1 without changing the machine execution policy. You can also call the adapter directly:

```powershell
.\website\bin\integrate.ps1
```

The command needs neither Ruby nor Node.js. It defaults to `docs/` and the `docs` theme, creates `.github/jekyll-obsidian.yml`, and renders `.github/workflows/pages.yml`. It never calls GitHub or modifies repository settings.

Then open **Settings → Pages → Build and deployment**, choose **GitHub Actions** as the Source, commit the generated files, and push. GitHub Actions installs Ruby, Node.js, dependencies, and Chromium before building and deploying the site.

## Choose a source and theme

Both platform adapters accept the same options:

```text
--source PATH
--theme blog|docs|digital-garden
--check
--force-workflow
--help
```

For example:

```sh
website/bin/integrate --source handbook --theme digital-garden
website/bin/integrate --check
```

Windows path separators are accepted and normalized before writing the portable configuration:

```powershell
.\website\bin\integrate.cmd --source "Documentation\User Guide" --theme docs
```

The source must be an existing repository-relative directory with a regular, non-symlink `index.md`. Its root frontmatter must contain one top-level `publish: true` entry. Traversal, site overlap, symbolic links, Windows junctions, reparse points, and path casing mismatches are rejected. The dependency-free check validates this integration contract; the compiler in Actions remains authoritative for complete YAML, routing, link, attachment, and publication validation.

## Customize the host

The generated host configuration contains a managed block:

```yaml
title: My Project Documentation

obsidian:
  # jekyll-obsidian:managed-start
  source: docs
  theme: docs
  # jekyll-obsidian:managed-end
  repository: ""
  edit_branch: main
  content:
    default_type: doc
    directories:
      post: []
      doc: []
```

`integrate` updates only the marked `source` and `theme` lines. Other keys and comments remain under host ownership. The generated content defaults classify files directly below `docs/` as documentation, so a file such as `docs/guide.md` appears in the Docs navigator.

Configuration precedence is `website/_config.yml`, then `.github/jekyll-obsidian.yml`, then explicit `bin/build` and Pages values. `bin/build` pins Jekyll's source, implementation directories, caches, destination, and safety settings to `website/`; host configuration cannot move those paths or bypass the adapter.

The generated workflow is fully tool-owned. Re-run `integrate` after updating `website/` or changing the source. An existing unmanaged `pages.yml` causes a safe failure; inspect it before explicitly using `--force-workflow`. The read-only `--check` mode reports drift without writing files and also runs at the start of CI.

When a host configuration already exists without the managed markers, the command prints the block that you need to merge and leaves both files untouched. After adding the markers, run the same command again. Arguments that you omit keep their current managed values.

## Keep editor state local

The compiler and watcher exclude `.obsidian/` and `.trash/`, but repository readers can still see any committed file. Add source-specific ignore entries when they are not already present:

```gitignore
docs/.obsidian/workspace*.json
docs/.trash/
```

Only notes with YAML boolean `publish: true` enter the generated site, but that is not a repository privacy mechanism. Never commit secrets or private records to a readable repository.

## Optional local development

Deployment does not require a local toolchain. Install Ruby 4.0.x and Node.js 26.x only when local preview or testing is useful:

```sh
website/bin/setup
website/bin/dev
```

The native Windows support in this guide covers integration and deployment. Use WSL for the Jekyll development commands. Continue with [[Customization]] or [[Deployment]].

## Troubleshooting

- If `index.md must use ... publish: true` appears, put one unquoted, top-level `publish: true` entry between the opening and closing frontmatter delimiters.
- If the command reports a site overlap, keep host content outside `website/`. Only the bundled `website/docs/` example is allowed inside it.
- If `pages.yml is not managed` appears, inspect the existing workflow. Use `--force-workflow` only when replacing it is intentional.
- If `--check` reports drift after updating `website/`, run `integrate` once without `--check`, then commit the refreshed files.
- If GitHub builds but does not deploy, confirm that **Settings → Pages → Build and deployment → Source** is set to **GitHub Actions**.
