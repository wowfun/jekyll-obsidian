---
publish: true
title: Deployment
nav_order: 50
tags:
  - guide/deployment
  - github-pages
description: Test and deploy any built-in theme with the included GitHub Pages workflow.
created: 2026-07-31
updated: 2026-08-19
---

# Deployment

The generated workflow targets GitHub.com. It separates untrusted verification from the trusted Pages build. A host can create or refresh it without a local Ruby or Node.js installation by running `website/bin/integrate` or `website\bin\integrate.cmd`.

## Pull requests and pushes

Every pull request and every push to the repository's default branch checks out the full Git history, runs the dependency-free integration drift check, installs the locked Ruby and Node dependencies, and performs a real production build of the configured host content. That build compiles the frontend assets, audits the generated site, and validates its URLs.

The workflow classifies the complete pull request difference, rather than only the latest push, into one of two validation tiers:

- **Host validation** covers content, translations, and host configuration. It keeps the production host build and its audit, but skips Chromium, template and browser regression tests, visual baselines, and the bundled-example matrix.
- **Full regression** covers Jekyll Obsidian implementation changes. It installs Chromium, runs `website/bin/test` with browser coverage, and builds every bundled deployment shape. The example builds both themes at a domain root and builds Minimal again under a project path:

1. At a domain root, such as `https://owner.github.io/`.
2. Under a project path, such as `https://owner.github.io/jekyll-obsidian/`.

Any change under `website/` selects full regression, except `website/docs/**`, which is the source repository's own content. A change to the generated `.github/workflows/pages.yml` also selects full regression. A pull request containing both content and implementation changes always uses full regression. Manual runs, initial pushes, invalid commit IDs, missing history, and Git comparison failures all fail safely to full regression; the workflow never reuses a previous run's classification.

Pull request jobs have `contents: read` permission. They do not call `configure-pages`, upload a Pages artifact, or deploy.

The workflow watches the configured content directory, `website/**`, `.github/jekyll-obsidian.yml`, and its own file. Do not edit these trigger paths manually; re-run the integration command when the source changes. Full-regression browser and visual baselines always use `website/docs`, while the production build in both tiers validates the host source, so custom documentation cannot be mistaken for a visual regression. A successful content-only push to the default branch continues through the trusted Pages build and deployment.

## Trusted Pages build

On a trusted default-branch push or a default-branch manual run, `build_pages` waits for verification. `actions/configure-pages` supplies the authoritative `origin` and `base_path`. The workflow passes both values to `website/bin/build`, which writes a temporary Jekyll config overlay under the site directory.

When Portfolio projects import GitHub Markdown, verification resolves each moving reference to a commit and exports one digest-checked materialization. The trusted Pages build consumes that same materialization instead of fetching the branch again, so verification and deployment cannot publish different revisions from one workflow run.

Before upload, the audit checks that `website/_site/index.html` exists, every output path is allowed, links are regular files rather than symbolic or multiply linked files, and the site remains within GitHub Pages' 1 GB published-site limit.

The deployment job alone receives `pages: write` and `id-token: write`. It uses the `github-pages` environment and reports the URL returned by the deployment action.

## Find the deployed site

After **Verify and deploy Pages** succeeds on the default branch, GitHub reports the public URL in the workflow's `deploy` job and in **Settings → Pages**. The deployment job's `github-pages` environment links to the same URL.

Without a custom domain, a repository named `<owner>.github.io` is available at `https://<owner>.github.io/`. Any other repository is available at `https://<owner>.github.io/<repository>/`.

## Root sites and project paths

The compiler keeps `baseurl` out of permalinks. One URL builder combines routes with the configured base path for HTML, assets, canonical links, feeds, sitemaps, and JSON requests.

When Pages metadata is unavailable in a pull request, `website/bin/build` inspects `GITHUB_REPOSITORY`. A repository named `<owner>.github.io` uses the domain root. Any other repository uses `/<repository>`.

## Custom domains

Configure the domain in Pages settings or through the GitHub Pages API. Add the required CNAME, A, ALIAS, or ANAME DNS records at your DNS provider. A `CNAME` file in the repository is ignored by this Actions publishing mode. After deployment, use the custom URL reported in **Settings → Pages**.

Run the workflow manually after adding or removing a domain. That rebuild updates canonical URLs, Open Graph metadata, Atom links, and the sitemap.

Return to [[docs/Getting Started|Getting Started]] for local commands or [[docs/development/architecture|Architecture]] for build internals.
