---
publish: true
title: Comments
nav_order: 40
tags:
  - guide/comments
  - github-discussions
description: Configure GitHub Discussions comments, understand thread identity, and troubleshoot Giscus.
created: 2026-08-04
updated: 2026-08-04
---

# Comments with GitHub Discussions

Jekyll Obsidian uses [Giscus](https://giscus.app/) to attach a GitHub Discussion to a published post. The site remains static: it runs no comment database or server API, and the discussion data stays in GitHub.

Visitors can read the public discussion in the page. Posting a comment or reaction requires GitHub authentication through Giscus. The page also keeps a normal link to GitHub Discussions, so readers can continue there when JavaScript is disabled or the embedded service is unavailable.

## Where comments appear

Comments are available in every built-in theme, but only pages classified as `content_type: post` are eligible. Pages, documentation notes, Blog indexes, tags, and other generated pages never receive a comment widget.

The `website.comments` mapping must exist before comments can be enabled. If it is absent, comments are off for every theme. When the mapping exists and omits `enabled`, the theme decides the default:

| Theme | Default with `website.comments` present |
| --- | --- |
| `minimal` | Enabled |
| `docs` | Disabled |

Set `enabled: true` or `enabled: false` to override that default in any theme.

## Set up the Discussions repository

The publication repository and the comments repository may be the same public repository. You can also keep community conversations in a separate public repository.

1. In the comments repository, open **Settings → General → Features** and enable **Discussions**. See [GitHub's repository instructions](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/enabling-or-disabling-github-discussions-for-a-repository).
2. Create a category such as `Blog comments`. The Announcement format is recommended because maintainers and Giscus can create discussions there while visitors can still reply.
3. Install the [Giscus GitHub App](https://github.com/apps/giscus) for the comments repository.
4. Enter the repository at [giscus.app](https://giscus.app/). Under **Page ↔️ Discussions Mapping**, select **Discussion title contains a specific term** and enable **Use strict title matching**. Leave the term field empty: Jekyll Obsidian supplies a strict `website:post:...` term for each post. Do not select `pathname`, URL, page title, `og:title`, or a specific discussion number.
5. Select the category, then copy the generated repository ID and category ID. Do not infer these IDs from their display names or copy the generated `<script>` tag; Jekyll Obsidian owns the mapping, term, and runtime options.

The repository must be public for visitors to read its discussions. These are runtime prerequisites, not build prerequisites. The build does not enable Discussions, create a category, install the GitHub App, inspect their remote state, or contact GitHub. A missing or later-disabled prerequisite never fails the static build.

## Configure the site

Add the comment settings outside the managed `source` and `theme` lines in `.github/jekyll-obsidian.yml`:

```yaml
website:
  # jekyll-obsidian:managed-start
  source: docs
  theme: minimal
  # jekyll-obsidian:managed-end
  repository: owner/site
  comments:
    enabled: true
    # Optional. Omit this line to reuse website.repository.
    repository: owner/community
    repository_id: R_kgDOxxxxxxxx
    category: Blog comments
    category_id: DIC_kwDOxxxxxxxx
```

`repository` is optional only when `website.repository` already identifies the comments repository. A valid repository identity is required when comments are enabled.

`repository_id`, `category`, and `category_id` are required to load Giscus, but they are not required to finish a build. When any of them is missing, the compiler emits a `comments_unconfigured` warning. Eligible posts render a non-interactive setup notice and a link to the comments repository without loading the Giscus client. You can enable comments first, then add these values after Discussions and the Giscus App are ready.

Unknown settings, non-boolean `enabled` values, invalid repository names, and non-string provider values remain fatal configuration errors.

`website/bin/integrate` preserves the comment mapping but does not create it. Run a production build after editing the host configuration:

```sh
JEKYLL_ENV=production website/bin/build \
  --url https://docs.example.com \
  --baseurl "" \
  --destination _site
```

## Control individual posts

Once the site-level feature is enabled, every published post receives comments. Disable one post with a YAML boolean:

```yaml
---
publish: true
content_type: post
date: 2026-08-04
comments: false
---
```

The page property cannot enable comments when `website.comments` is absent or disabled. `comments: true` also does not turn a page or documentation note into a post. Use `content_type: post` or the configured post directory for that classification.

## Thread identity and creation

Each post uses a strict, route-independent term derived from its logical note path:

```text
website:post:blog/my-post
```

Changing the site domain, `baseurl`, or permalink keeps the same Discussion. Moving or renaming the source note changes the term and therefore starts a new thread identity. Existing Discussions are not migrated automatically.

Localized versions of the same logical post share one Discussion. The widget language follows the page locale when Giscus supports it, then falls back to English.

The build and the first page view do not create an empty Discussion. Giscus creates it when a visitor submits the first comment or reaction. A page with no existing Discussion is therefore a normal, usable state.

## Runtime and fallback behavior

Local development never connects to Giscus. It renders a publication-only notice and a link to the configured Discussions page.

Production and CI output load the Giscus client on eligible posts only when all provider values are present. The iframe loads lazily near the comment section, follows the site's light or dark color scheme, and receives later scheme changes without a reload.

If Discussions is disabled, the Giscus App is not installed, or the external client is unavailable, the site itself continues normally. The comment section changes to a non-fatal unavailable state and retains its server-rendered GitHub link. These runtime failures do not affect other page features or future builds.

Pages with active comments receive a narrow Content Security Policy that permits the Giscus script, iframe, and default stylesheet. Other pages keep the normal site-only policy.

## Privacy and origin restrictions

Comments and reactions are public data in the configured GitHub repository. Visitors authenticate with GitHub before posting, and moderation happens in GitHub Discussions. Review GitHub and Giscus policies before enabling the feature on a site with additional privacy or compliance requirements.

To stop unrelated sites from embedding your repository's Discussions, add `giscus.json` at the root of the comments repository:

```json
{
  "origins": ["https://docs.example.com"]
}
```

> [!important] Use the page's origin only
> Giscus compares `origins` with `window.origin`. Do not include a path or `baseurl`. For `https://owner.github.io/project/`, use `https://owner.github.io`.

See the [Giscus advanced usage guide](https://github.com/giscus/giscus/blob/main/ADVANCED-USAGE.md#giscusjson) for `originsRegex` and other repository-level settings.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No comment section is rendered | Confirm that `website.comments` exists, the feature is enabled for the active theme, the note is a post, and its frontmatter does not contain `comments: false`. |
| The build reports `invalid_comments` | Check that `enabled` is a YAML boolean, the repository uses `owner/repository`, all provider values are strings, and no unknown settings are present. |
| The build warns with `comments_unconfigured` | The build has succeeded, but Giscus will stay inactive. Enable Discussions, install the Giscus App, then copy the missing IDs and category from giscus.app. |
| The page says comments load only on the published site | This is expected in local development. Use a production build to exercise the external client. |
| The widget is unavailable | The rest of the site remains usable. Confirm that the repository is public, Discussions is enabled, the Giscus App is installed, the category still exists, and `giscus.json` permits the production origin. |
| A post has no Discussion yet | Submit the first comment or reaction. Giscus creates the Discussion on that first interaction. |
| A renamed post opens a new thread | The source path is part of the stable term. Rename the related Discussion for reference if needed, but the site does not migrate it automatically. |
