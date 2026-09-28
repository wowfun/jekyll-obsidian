# jekyll-obsidian

English | [简体中文](README.zh-CN.md)

`jekyll-obsidian` turns a Markdown folder, including an Obsidian vault, into a blog or documentation site. Keep writing in your editor and push to GitHub; Actions builds and publishes the site. Add a configuration file and a workflow to your repository. The implementation is installed as the `jekyll-obsidian-site` Ruby gem.

Live preview: [sinputer.top/jekyll-obsidian](https://sinputer.top/jekyll-obsidian/)

Choose one built-in theme for each build:

- `minimal` combines an authored Home page with recent posts, a full Blog, documentation, and explicit custom sections for personal or organization sites.
- `docs` provides a document tree and previous or next links.

Both themes enable search, wiki-link reading previews, the page outline, note relations, and an interactive local graph by default. A note participating in a link or embed relation with another public note keeps its local graph at the top of the right-hand context rail; isolated and self-link-only notes omit it. Its two controls open the complete public graph or an expanded view of the current note's neighbourhood. The complete graph still contains every public note, and `/graph/` is not a generated route.

Switching themes does not change note URLs.
The default build and deployment theme is `minimal`. Both themes can publish locale overlays from `_translations/<locale>/` and attach GitHub Discussions comments to posts. When the corresponding mapping is present and omits `enabled`, localization defaults on only for `docs`, while comments default on only for `minimal`.

See [Localization](website/jekyll-obsidian-docs/docs/Localization.md) for locale manifests, which content controls site structure, fallback pages, and SEO behavior.

Minimal also provides Blog, tags, Atom feeds, contacts, source actions, and an automatically detected Portfolio with project cards. A project wrapper can use a public GitHub Markdown file as its body. Both themes generate Search and Graph data, canonical metadata, a sitemap, a 404 page, and frontmatter-free Markdown resources. Optional traffic measurement supports either Cloudflare Web Analytics or Google Analytics and stays off until configured.

## Before you publish

Deploying with GitHub Pages does not require Ruby, Node.js, Bundler, npm, or a browser on your computer. The generated GitHub Actions workflow installs the build toolchain.

[GitHub Pages is available for public repositories on GitHub Free](https://docs.github.com/en/pages/quickstart#who-can-use-this-feature), so a public `jekyll-obsidian` site needs no paid hosting.

The publication policy controls what enters the generated site. It does not make other committed files private. Anyone who can read the repository can read unpublished notes too, so do not commit secrets, personal records, or other private material.

Canvas and Bases files become downloads when a public note links to them. Inspect them before committing because they can contain excerpts or references to unpublished material.

## Add it to your repository

1. Create `.github/jekyll-obsidian.yml`, using [the example configuration](examples/jekyll-obsidian.yml):

```yaml
title: My Site
website:
  source: docs
  theme: minimal
```

2. Copy [the Pages workflow](examples/pages.yml) to `.github/workflows/pages.yml`.
3. Put a Markdown note with `publish: true` in `docs/`, then select **Settings > Pages > Build and deployment > Source > GitHub Actions** and push.

The content directory can also be `website/docs/` or another repository-relative directory. Edit `website.source` to select it. No local Ruby, Node.js, or build command is needed for Actions.

For local initialization, install Ruby 4.0.x and run:

```sh
gem install jekyll-obsidian-site
jekyll-obsidian init --source docs
```

`init` creates the same configuration and workflow. It adds a public welcome note only when the content directory is absent or empty. Existing conflicting files are left unchanged. See [Host Integration](website/jekyll-obsidian-docs/docs/Integration.md) for Bundler, updates, and existing repositories.

## Preview the deployed site

Wait for the **Build and deploy Pages** workflow on the default branch to succeed. GitHub reports the deployed URL in the workflow's `deploy` job and in **Settings → Pages**.

Without a custom domain, the expected URL is:

- `https://<owner>.github.io/<repository>/` for a normal project repository.
- `https://<owner>.github.io/` when the repository itself is named `<owner>.github.io`.

If you configure a custom domain, use the URL shown in **Settings → Pages**. The workflow reads GitHub Pages metadata and builds links for that URL automatically. See [Deployment](website/jekyll-obsidian-docs/docs/Deployment.md) for the workflow and custom-domain details.

## Configure and publish

Edit `.github/jekyll-obsidian.yml` to configure the title, language, content directory, theme, and features. All entries are directly editable. Changing `website.source` or `website.theme` takes effect on the next build; the workflow does not need to be regenerated.

The configuration interface is the root `website:` mapping.

Both themes can store post comments in GitHub Discussions through Giscus. Comments use the publication repository by default and can point at a separate public repository. When `website.comments` exists and omits `enabled`, `minimal` enables comments by default; `docs` requires `website.comments.enabled: true`. Enabling comments before Discussions or the Giscus App is ready does not fail the build; incomplete Giscus configuration produces a warning and a non-interactive fallback. See [Comments](website/jekyll-obsidian-docs/docs/Comments.md) for repository setup, thread identity, privacy boundaries, and troubleshooting.

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

`index.md` is optional at the content root and in every nested folder. When a folder has no physical `index.md`, a published sibling named exactly `README.md` becomes its index. A physical `index.md` keeps priority even when it is unpublished; in that case, `README.md` remains an ordinary note. A selected README keeps its source path and source actions but publishes at the folder route. Minimal places the selected public root index above the six most recent posts on Home; without one, Home can still show the post stream. A folder without a public selected index links to its first ordered public page. A content directory with no public notes still fails the build.

Trusted standalone HTML slides can also publish at explicit routes without a theme or Liquid pass. Map one `.html` file or a directory bundle containing `index.html`; a bundle publishes its regular files with their relative structure intact, except Markdown and compiler locale manifests such as `_locale.yml`:

```yaml
website:
  html:
    slides/product-tour: /slides/product-tour/
```

HTML mappings are an explicit publication boundary independent of Markdown defaults. Raw pages stay out of navigation, Search, Graph, feeds, and sitemap, and they execute as trusted same-origin code. Review the complete bundle before publishing. See [Customization](website/jekyll-obsidian-docs/docs/Customization.md#standalone-html-slides) and the [working slide source](website/jekyll-obsidian-docs/slides/jekyll-obsidian/index.html).

Update the Action version in your workflow to use a new release. For a local gem installation, run `gem update jekyll-obsidian-site`; for Bundler, run `bundle update jekyll-obsidian-site` and commit the lockfile. Your content and configuration remain in your repository.

## Optional local preview

With Ruby 4.0.x on macOS, Linux, or WSL:

```sh
gem install jekyll-obsidian-site
jekyll-obsidian dev
```

Open `http://127.0.0.1:58000/`. Content and configuration changes trigger a complete rebuild. A failed rebuild leaves the last successful site available. Run `jekyll-obsidian dev --help` for host, port, base path, and theme options.

Build for another host with `jekyll-obsidian build --url https://example.com --baseurl /project`. Output is written to `.jekyll-obsidian-cache/site/`. `jekyll-obsidian clean` removes this project's cache and output. The gem includes frontend assets, so local use does not require Node.js.

## Guides

- [Host Integration](website/jekyll-obsidian-docs/docs/Integration.md) covers installation and updates in another repository.
- [Getting Started](website/jekyll-obsidian-docs/docs/Getting%20Started.md) covers GitHub Actions publishing, authoring, and optional local preview.
- [Syntax](website/jekyll-obsidian-docs/docs/Syntax.md) documents the supported Obsidian-flavored Markdown.
- [Customization](website/jekyll-obsidian-docs/docs/Customization.md) covers site identity, themes, navigation, and features.
- [Portfolio](website/jekyll-obsidian-docs/docs/Portfolio.md) covers project collections and public GitHub Markdown bodies.
- [Analytics](website/jekyll-obsidian-docs/docs/Analytics.md) covers optional Cloudflare and Google traffic measurement.
- [Comments](website/jekyll-obsidian-docs/docs/Comments.md) covers GitHub Discussions setup and privacy boundaries.
- [Localization](website/jekyll-obsidian-docs/docs/Localization.md) covers translations, fallback pages, and localized SEO.
- [Deployment](website/jekyll-obsidian-docs/docs/Deployment.md) covers GitHub Pages, URL paths, and custom domains.

Contributors can continue with the [Developer Guide](website/jekyll-obsidian-docs/docs/development/index.md).

## License

MIT
