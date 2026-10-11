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

The [Pages workflow example](https://github.com/wowfun/jekyll-obsidian/blob/v0.2.1/examples/pages.yml) uses the versioned Jekyll Obsidian Action. The Action installs Ruby and builds with the matching `jekyll-obsidian-site` gem. If the host commits a Gemfile and lockfile, it uses that frozen bundle; otherwise it installs the gem directly. No npm installation or project regression suite runs in downstream repositories.

## Pull requests and pushes

Pull requests build and validate the site without deploying it. Default-branch pushes build and deploy; other branch pushes are ignored. Manual runs deploy only when the selected ref is the default branch.

The workflow has no content-path filter. Change `website.source` in `.github/jekyll-obsidian.yml` without regenerating the workflow. The project repository runs its own compiler, package, frontend, and browser tests separately.

## Trusted Pages build

Select **Settings > Pages > Build and deployment > Source > GitHub Actions**. The build job reads Pages metadata, builds once, audits that output, and uploads the verified artifact. The deploy job receives only the Pages and identity-token permissions required for deployment.

Before upload, the audit checks output paths, file types, site size, URLs, and asset references. A failed build does not replace the previous local output or deploy an artifact.

The Action accepts `url` and `baseurl`, and returns `site-path`, the absolute output directory. The example workflow passes Pages metadata to these inputs and uploads that directory.

## Find the deployed site

The deployment job and **Settings > Pages** show the published URL. A project repository normally uses `https://<owner>.github.io/<repository>/`; an `<owner>.github.io` repository uses the origin root.

## Root sites and project paths

For another static host, run:

```sh
jekyll-obsidian build --url https://example.com --baseurl /project
```

Upload `.jekyll-obsidian-cache/site/`. Set `--baseurl ""` for an origin-root site. Production builds require an origin; `url` and `baseurl` can also be set in the site configuration. Explicit command-line values take precedence.

## Custom domains

Configure the custom domain and DNS in GitHub Pages. The workflow reads the resulting origin and base path from Pages metadata. You do not need to hard-code them in the configuration for this workflow.

## Update the builder

Change the Action reference to a published release tag. Each Action release installs its matching gem version. Content and configuration stay in the host repository; no copied implementation or snapshot updater is involved.
