# jekyll-obsidian

`jekyll-obsidian` turns a folder that Obsidian can open directly into a configurable Jekyll blog, documentation site, or digital garden. The bundled example vault lives in `website/docs/`; only notes whose frontmatter contains the YAML boolean `publish: true` enter the generated site. Obsidian's `.obsidian/` state and `.trash/` are excluded from the content snapshot.

The same vault can be built with three first-party themes:

- `blog`: a reading-first publishing ledger with recent posts, archive, tags, and Atom.
- `docs`: an instrument-handbook layout with a document tree, breadcrumbs, outline, and previous/next links.
- `digital-garden`: the annotated research folio with previews, backlinks, relation rail, and graph.

Each build uses one theme. Switching themes does not change note URLs.

## Before you publish

`publish: true` is a generated-site boundary, not repository privacy. Anyone who can read the repository can read every committed file, including unpublished notes. Do not commit secrets, personal records, or other material that must remain private.

Canvas and Bases files become downloads when a public note links to them. They can contain excerpts or references to unpublished material, so inspect them before committing.

## Requirements

Publishing through GitHub Pages does not require Ruby, Node.js, Bundler, npm, or a browser on your computer. GitHub Actions installs the complete build toolchain.

Local preview and testing additionally require Ruby 4.0.x, Node.js 26.x, and Git on macOS, Linux, or WSL. Native Windows supports the integration and deployment setup below; use WSL for the local Jekyll development commands.

## Deploy in three steps

1. Copy `website/` to the host repository root and make sure the chosen content directory has a public `index.md`.
2. Run `website/bin/integrate` on macOS, Linux, or WSL. On native Windows, run `.\website\bin\integrate.cmd`.
3. In the repository's Pages settings, select GitHub Actions as the source, then commit and push.

The command creates the host configuration and Pages workflow. It does not install anything or contact GitHub. Ruby, Node.js, and Chromium are installed by GitHub Actions after the push.

## Local development

Create a repository from this template, then run:

```sh
website/bin/setup
website/bin/dev
```

Open `website/docs/` directly in Obsidian. Publish a note with typed frontmatter:

```yaml
---
publish: true
title: A public note
tags:
  - example
---
```

Preview another built-in theme without rewriting `website/_config.yml`:

```sh
website/bin/dev --theme docs
website/bin/build --theme blog --url https://example.com --baseurl "" --destination _site
```

The destination name is resolved inside `website/`, so the second command writes `website/_site`.

## Configure

The bundled example uses `website/_config.yml`. A host repository should keep its overrides in `.github/jekyll-obsidian.yml`, which is loaded after the bundled defaults:

```yaml
title: My Site
description: Built from an Obsidian vault
lang: en

obsidian:
  # jekyll-obsidian:managed-start
  source: docs
  theme: docs
  # jekyll-obsidian:managed-end
  repository: owner/repository
  edit_branch: main
  content:
    default_type: doc
    directories:
      post: []
      doc: []
  features: {}
```

`obsidian.source` is resolved from the repository root, not from `website/`. It must name a normalized relative directory inside the repository. The bundled `website/docs` directory is the only content root allowed inside the Jekyll source; host content normally remains outside it. The compiler rejects symlinks, path traversal, other site overlaps, destination overlaps, and routes that normalize to the same destination.

`content_type: post | doc | page` overrides directory classification. Blog post dates resolve from `date`, then `created`, then the first Git commit. Docs navigation uses `nav_order` and `nav_exclude`. An `image` property resolves to a published image URL and supplies `og:image`. Theme feature defaults can be overridden with strict booleans for `search`, `tags`, `feed`, `graph`, `relations`, `previews`, and `outline`.

The root `website/docs/index.md` remains the authored homepage. Each theme appends its own useful overview to that content.

## Add the site to another repository

Copy only `website/` into the host repository. With an existing public `docs/index.md`, configure the site and generate the Pages workflow with one dependency-free command:

```sh
# macOS, Linux, or WSL
website/bin/integrate
```

```powershell
# Native Windows, from PowerShell
.\website\bin\integrate.cmd
```

The default is `--source docs --theme docs`. Use options such as `--source handbook --theme digital-garden` for another repository-relative content directory or theme. The command does not install dependencies or contact GitHub.

```text
repository/
├── docs/
├── website/
│   ├── _config.yml
│   ├── bin/
│   └── ...
└── .github/
    ├── jekyll-obsidian.yml
    └── workflows/
        └── pages.yml
```

The command maintains `source` and `theme` inside `.github/jekyll-obsidian.yml`, preserves other host overrides, and renders `.github/workflows/pages.yml` with the correct content trigger. Run `website/bin/integrate --check` to verify that they remain synchronized. Existing unrelated Pages workflows are never overwritten without `--force-workflow`.

Finally, open the repository's **Settings → Pages**, choose **GitHub Actions** under **Build and deployment → Source**, then commit and push. No `gh-pages` branch, deployment secret, or manual `url`/`baseurl` is required. See the [host integration guide](website/docs/docs/Integration.md) for Windows commands, conflict handling, updating, and the publication boundary.

Jekyll reads `website/`, but the adapter excludes its bundled example vault before Jekyll's Reader runs and snapshots only the configured content root. Site dependencies, examples, caches, test reports, and generated output remain under `website/`.

## Test and deploy

```sh
website/bin/test
(cd website && npx playwright install chromium)
RUN_BROWSER_TESTS=1 website/bin/test
```

These commands are optional for deploy-only consumers. The generated GitHub Actions workflow independently installs the locked toolchain, tests the bundled template, validates the host content, and publishes the configured theme from trusted default-branch builds. See [the deployment guide](website/docs/docs/Deployment.md) for Pages permissions, custom domains, and artifact checks.

## Security model

Raw HTML in public notes is trusted author input. The compiler removes HTML and Obsidian comments, rejects dangerous Markdown URL schemes, and never discovers local attachments from raw HTML attributes.

Production pages include a meta Content Security Policy. GitHub Pages cannot promote it to a response header, so it is a browser-side safeguard rather than a complete hosting boundary. Review authored HTML and linked HTTPS media before publishing.

The pinned OFM contract is documented in [website/docs/ofm-conformance.md](website/docs/ofm-conformance.md). The public notes under `website/docs/docs/` cover setup, syntax, customization, deployment, architecture, and CJK behavior.

## License

MIT
