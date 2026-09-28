---
publish: true
title: Releasing
nav_order: 73
tags:
  - guide/development
description: Configure RubyGems publishing and release the gem with its matching GitHub Action.
---

# Releasing

The RubyGems package is `jekyll-obsidian-site`. Its executable is `jekyll-obsidian`. Each GitHub Action tag installs that exact gem version, so the gem must be available before downstream repositories can use the tag.

## First publication

Sign in to RubyGems.org and create a [pending trusted publisher](https://rubygems.org/profile/oidc/pending_trusted_publishers) with these values:

| Field | Value |
| --- | --- |
| Gem name | `jekyll-obsidian-site` |
| Repository owner | `wowfun` |
| Repository name | `jekyll-obsidian` |
| Workflow filename | `release.yml` |
| Environment | `rubygems` |

Leave the optional Workflow Repository fields empty. The release workflow runs in this repository. On GitHub, create the `rubygems` environment under **Settings → Environments** and set any desired reviewer restrictions.

RubyGems converts the pending publisher after the first successful publication. No long-lived API key is needed. See the [RubyGems Trusted Publishing guide](https://guides.rubygems.org/trusted-publishing/) for account setup.

## Prepare a version

Keep the version in `website/lib/jekyll_obsidian/version.rb`, `website/package.json`, and `website/package-lock.json` aligned. Update the pinned Action reference in `examples/pages.yml` and the installation examples in the documentation. The initializer uses the Ruby version constant to render its workflow.

Run the full suite before tagging:

```sh
(cd website && npx playwright install --with-deps chromium)
RUN_BROWSER_TESTS=1 website/bin/test
```

Commit the release changes and push an immutable tag matching the version, such as `v0.2.0`. The release workflow must also be present on the default branch so GitHub can display its manual trigger.

## Publish and verify

In GitHub Actions, open **Publish Ruby gem**, choose **Run workflow**, and enter the existing tag. The workflow checks that the tag and gem version agree, builds and tests the package, then publishes the tested artifact with Trusted Publishing. A final job uses that tag's Action to install the public gem and build an independent host.

Wait for publication to finish before announcing the Action tag. In a fresh directory with Ruby 4.0.x and Git installed, verify the public package:

```sh
gem install jekyll-obsidian-site --version 0.2.0
jekyll-obsidian _0.2.0_ init
jekyll-obsidian _0.2.0_ build --url https://example.test
```

Check a downstream Pages run using `wowfun/jekyll-obsidian@v0.2.0`. The downstream build must succeed without a checked-in `website/` implementation or npm dependencies.

If publication fails, fix the cause before retrying. If only the installation check fails after publication, rerun that failed job without repeating the successful publish job. Never replace an already published gem version or move a released Action tag; prepare a new version instead.
