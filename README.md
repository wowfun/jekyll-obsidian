# jekyll-obsidian

English | [简体中文](README.zh-CN.md)

`jekyll-obsidian` turns any folder of Markdown files, including an Obsidian vault, into a general-purpose Jekyll site or a documentation handbook. Your content remains editable in Obsidian or any text editor. Copy the bundled `website/` directory into your repository and push; GitHub Actions handles the build and publishes to Pages, so you do not need a local toolchain or build command.

**A complete blog or documentation site from a Markdown folder. Just push to GitHub. GitHub Actions builds and publishes it, with nothing to install or run locally.**

Live preview: [sinputer.top/jekyll-obsidian](https://sinputer.top/jekyll-obsidian/)

Choose one built-in theme for each build:

- `minimal` combines an authored Home page with recent posts, a full Blog, documentation, and explicit custom sections for personal or organization sites.
- `docs` provides a document tree and previous or next links.

Both themes enable search, wiki-link reading previews, the page outline, note relations, and an interactive local graph by default. A note participating in a link or embed relation with another public note keeps its local graph at the top of the right-hand context rail; isolated and self-link-only notes omit it. Its two controls open the complete public graph or an expanded view of the current note's neighbourhood. The complete graph still contains every public note, and `/graph/` is not a generated route.

Switching themes does not change note URLs.
The default build and deployment theme is `minimal`. Both themes can publish locale overlays from `_translations/<locale>/` and attach GitHub Discussions comments to posts. When the corresponding mapping is present and omits `enabled`, localization defaults on only for `docs`, while comments default on only for `minimal`.

See [Localization](website/docs/docs/Localization.md) for locale manifests, which content controls site structure, fallback pages, and SEO behavior.

Minimal also provides Blog, tags, Atom feeds, contacts, source actions, and an automatically detected Portfolio with project cards. A project wrapper can use a public GitHub Markdown file as its body. Both themes generate Search and Graph data, canonical metadata, a sitemap, a 404 page, and frontmatter-free Markdown resources. Optional traffic measurement supports either Cloudflare Web Analytics or Google Analytics and stays off until configured.

## Before you publish

Deploying with GitHub Pages does not require Ruby, Node.js, Bundler, npm, or a browser on your computer. The generated GitHub Actions workflow installs the build toolchain.

[GitHub Pages is available for public repositories on GitHub Free](https://docs.github.com/en/pages/quickstart#who-can-use-this-feature), so a public `jekyll-obsidian` site needs no paid hosting.

The publication policy controls what enters the generated site. It does not make other committed files private. Anyone who can read the repository can read unpublished notes too, so do not commit secrets, personal records, or other private material.

Canvas and Bases files become downloads when a public note links to them. Inspect them before committing because they can contain excerpts or references to unpublished material.

## Add it to your repository

1. Copy the complete `website/` directory to the root of your repository.
2. Choose a content directory outside `website/`, such as `docs/`, and add at least one public Markdown note.
3. Run the integration command from the repository root.

On macOS, Linux, or WSL:

```sh
website/bin/integrate --source docs
```

On native Windows, from PowerShell:

```powershell
.\website\bin\integrate.cmd --source docs
```

The command defaults to `--source docs --theme minimal`. It creates `.github/jekyll-obsidian.yml` and `.github/workflows/pages.yml` without installing dependencies or contacting GitHub.

Your repository will have this shape:

```text
repository/
├── docs/
│   └── Start.md
├── website/
└── .github/
    ├── jekyll-obsidian.yml
    └── workflows/
        └── pages.yml
```

Open **Settings → Pages → Build and deployment** in GitHub and choose **GitHub Actions** as the Source. Commit and push the content directory, `website/`, and the generated `.github/` files. You do not need a `gh-pages` branch, deployment secret, or manual `url` and `baseurl` values.

The integration command will not overwrite an unrelated Pages workflow unless you pass `--force-workflow`. See [Host Integration](website/docs/docs/Integration.md) for existing configuration, Windows details, and conflict handling.

## Preview the deployed site

Wait for the **Verify and deploy Pages** workflow on the default branch to succeed. GitHub reports the deployed URL in the workflow's `deploy` job and in **Settings → Pages**.

Without a custom domain, the expected URL is:

- `https://<owner>.github.io/<repository>/` for a normal project repository.
- `https://<owner>.github.io/` when the repository itself is named `<owner>.github.io`.

If you configure a custom domain, use the URL shown in **Settings → Pages**. The workflow reads GitHub Pages metadata and builds links for that URL automatically. See [Deployment](website/docs/docs/Deployment.md) for the workflow and custom-domain details.

## Configure and publish

The generated `.github/jekyll-obsidian.yml` is the host repository's configuration. Edit it to set the site title, description, language, repository links, content types, and feature overrides. Keep the managed markers around `website.source` and `website.theme`; change those values by running `website/bin/integrate` again with the desired options.

The configuration interface is the root `website:` mapping.

Both themes can store post comments in GitHub Discussions through Giscus. Comments use the publication repository by default and can point at a separate public repository. When `website.comments` exists and omits `enabled`, `minimal` enables comments by default; `docs` requires `website.comments.enabled: true`. Enabling comments before Discussions or the Giscus App is ready does not fail the build; incomplete Giscus configuration produces a warning and a non-interactive fallback. See [Comments](website/docs/docs/Comments.md) for repository setup, thread identity, privacy boundaries, and troubleshooting.

Open your content directory in Obsidian or any Markdown editor. By default, a note enters the site only when its frontmatter contains the YAML boolean `publish: true`:

```yaml
---
publish: true
title: A public note
tags:
  - example
---
```

The strings `"true"` and `"yes"` are not accepted. To publish a whole folder recursively, list its path under `website.content.publish_by_default`; use `.` to select the complete content tree. A note can opt out of either default with the YAML boolean `publish: false`. Obsidian's `.obsidian/` state and `.trash/` are excluded from the content snapshot.

`index.md` is optional at the content root and in every nested folder. Minimal uses a public root `index.md` above the six most recent posts on Home; without one, Home can still show the post stream. A folder without an index links to its first ordered public page. A content directory with no public notes still fails the build.

Update a tagged installation from the host repository root:

```sh
website/bin/update --check
website/bin/update
```

The updater fetches an official stable Semantic Versioning release from an immutable annotated `vX.Y.Z` tag in an isolated temporary repository, verifies the installed snapshot, refreshes only tool-managed files, and leaves review and commit decisions to you. Each numeric core identifier is either `0` or has no leading zeroes, and `0.y.z` denotes initial development. Prerelease and build metadata tags are outside the stable updater channel; dates belong in release notes rather than version numbers. The updater never adds a remote to the host repository or runs `git pull`, `git add`, `git commit`, or `git push`. The first update of an older installation succeeds only when its committed `website/` exactly matches an official tag; otherwise replace it once with a tagged snapshot. See [Host Integration](website/docs/docs/Integration.md) for provenance, exit codes, Windows commands, and recovery behavior.

## Optional local preview

Local preview requires Ruby 4.0.x, Node.js 26.x, and Git on macOS, Linux, or WSL. Native Windows users can run these commands in WSL.

```sh
website/bin/setup
website/bin/dev
```

Open the URL printed by the local server, which is `http://127.0.0.1:58000/` by default. Local preview uses the Minimal theme unless you pass `--theme docs`.

Run `website/bin/clean` from the repository root to remove generated sites, Jekyll and frontend caches, test reports, coverage, and temporary build directories. Installed Ruby and Node.js dependencies are preserved.

## Guides

- [Host Integration](website/docs/docs/Integration.md) covers installation and updates in another repository.
- [Getting Started](website/docs/docs/Getting%20Started.md) covers GitHub Actions publishing, authoring, and optional local preview.
- [Syntax](website/docs/docs/Syntax.md) documents the supported Obsidian-flavored Markdown.
- [Customization](website/docs/docs/Customization.md) covers site identity, themes, navigation, and features.
- [Portfolio](website/docs/docs/Portfolio.md) covers project collections and public GitHub Markdown bodies.
- [Analytics](website/docs/docs/Analytics.md) covers optional Cloudflare and Google traffic measurement.
- [Comments](website/docs/docs/Comments.md) covers GitHub Discussions setup and privacy boundaries.
- [Localization](website/docs/docs/Localization.md) covers translations, fallback pages, and localized SEO.
- [Deployment](website/docs/docs/Deployment.md) covers GitHub Pages, URL paths, and custom domains.

Contributors can continue with the [Developer Guide](website/docs/docs/development/index.md).

## License

MIT
