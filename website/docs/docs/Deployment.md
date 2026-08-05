---
publish: true
title: Deployment
nav_order: 50
tags:
  - guide/deployment
  - github-pages
description: Test and deploy any built-in theme with the included GitHub Pages workflow.
created: 2026-07-31
updated: 2026-08-02
---

# Deployment

The generated workflow targets GitHub.com. It separates untrusted verification from the trusted Pages build. A host can create or refresh it without a local Ruby or Node.js installation by running `website/bin/integrate` or `website\bin\integrate.cmd`.

## Pull requests and pushes

Every pull request and every push to the repository's default branch checks out the full Git history, runs the dependency-free integration drift check, installs the locked Ruby and Node dependencies, runs the template test suite, and validates the configured host content. The bundled example builds both themes at a domain root and builds Minimal again under a project path, covering both deployment shapes:

1. At a domain root, such as `https://owner.github.io/`.
2. Under a project path, such as `https://owner.github.io/jekyll-obsidian/`.

Pull request jobs have `contents: read` permission. They do not call `configure-pages`, upload a Pages artifact, or deploy.

The workflow watches the configured content directory, `website/**`, `.github/jekyll-obsidian.yml`, and its own file. Do not edit these trigger paths manually; re-run the integration command when the source changes. Template browser and visual baselines always use `website/docs`, while a separate production build validates the host source, so custom documentation cannot be mistaken for a visual regression.

## Trusted Pages build

On a trusted default-branch push or a default-branch manual run, `build_pages` waits for verification. `actions/configure-pages` supplies the authoritative `origin` and `base_path`. The workflow passes both values to `website/bin/build`, which writes a temporary Jekyll config overlay under the site directory.

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
