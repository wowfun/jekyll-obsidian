# jekyll-obsidian

`jekyll-obsidian` turns a folder that Obsidian can open directly into a configurable Jekyll blog, documentation site, or digital garden. Notes stay as Markdown in `vault/`; only notes whose frontmatter contains the YAML boolean `publish: true` enter the generated site. Obsidian's `.obsidian/` state and `.trash/` are excluded from the content snapshot.

The same vault can be built with three first-party themes:

- `blog`: a reading-first publishing ledger with recent posts, archive, tags, and Atom.
- `docs`: an instrument-handbook layout with a document tree, breadcrumbs, outline, and previous/next links.
- `digital-garden`: the annotated research folio with previews, backlinks, relation rail, and graph.

Each build uses one theme. Switching themes does not change note URLs.

## Before you publish

`publish: true` is a generated-site boundary, not repository privacy. Anyone who can read the repository can read every committed file, including unpublished notes. Do not commit secrets, personal records, or other material that must remain private.

Canvas and Bases files become downloads when a public note links to them. They can contain excerpts or references to unpublished material, so inspect them before committing.

## Requirements

- Ruby 4.0.x
- Node.js 26.x
- Git
- macOS, Linux, or WSL

Native Windows command scripts are not included.

## Start

Create a repository from this template, then run:

```sh
website/bin/setup
website/bin/dev
```

Open `vault/` directly in Obsidian. Publish a note with typed frontmatter:

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

Edit `website/_config.yml`:

```yaml
title: My Site
description: Built from an Obsidian vault
lang: en
url: ""
baseurl: ""

obsidian:
  source: vault
  syntax_profile: ofm@1
  theme: digital-garden
  repository: owner/repository
  edit_branch: main
  content:
    default_type: page
    directories:
      post: [blog]
      doc: [docs]
  features: {}
```

`obsidian.source` is resolved from the repository root, not from `website/`. It must name a normalized relative directory inside the repository. The compiler rejects symlinks, path traversal, overlap with the site or destination, and routes that normalize to the same destination.

`content_type: post | doc | page` overrides directory classification. Blog post dates resolve from `date`, then `created`, then the first Git commit. Docs navigation uses `nav_order` and `nav_exclude`. An `image` property resolves to a published image URL and supplies `og:image`. Theme feature defaults can be overridden with strict booleans for `search`, `tags`, `feed`, `graph`, `relations`, `previews`, and `outline`.

The root `vault/index.md` remains the authored homepage. Each theme appends its own useful overview to that content.

## Add the site to another repository

Copy `website/` and the Pages workflow into a host repository, then point `obsidian.source` at its documentation directory:

```text
repository/
├── docs/
├── website/
│   ├── _config.yml
│   ├── bin/
│   └── ...
└── .github/
    └── workflows/
        └── pages.yml
```

```yaml
obsidian:
  source: docs
```

Jekyll reads only `website/`; the adapter snapshots `docs/` from the host repository. Site dependencies, caches, test reports, and generated output remain under `website/`. The included workflow watches `website/**`, `vault/**`, `docs/**`, and the workflow file itself. If you use another source directory, add its path to both the `push.paths` and `pull_request.paths` lists.

## Test and deploy

```sh
website/bin/test
(cd website && npx playwright install chromium)
RUN_BROWSER_TESTS=1 website/bin/test
```

The included GitHub Actions workflow builds frontend assets once, verifies all three themes at the domain root plus one project-path deployment, then publishes the configured theme from trusted default-branch builds. See [the deployment guide](vault/docs/Deployment.md) for Pages permissions, custom domains, and artifact checks.

## Security model

Raw HTML in public notes is trusted author input. The compiler removes HTML and Obsidian comments, rejects dangerous Markdown URL schemes, and never discovers local attachments from raw HTML attributes.

Production pages include a meta Content Security Policy. GitHub Pages cannot promote it to a response header, so it is a browser-side safeguard rather than a complete hosting boundary. Review authored HTML and linked HTTPS media before publishing.

The pinned OFM contract is documented in [website/docs/ofm-conformance.md](website/docs/ofm-conformance.md). The public notes under `vault/docs/` cover setup, syntax, customization, deployment, architecture, and CJK behavior.

## License

MIT
