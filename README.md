# jekyll-obsidian

English | [简体中文](README.zh-CN.md)

Turn a Markdown folder or Obsidian vault into a blog or documentation site. Keep writing in your editor and push to GitHub; Actions builds and publishes the site using the [jekyll-obsidian-site](https://rubygems.org/gems/jekyll-obsidian-site) Ruby gem.

Live preview: [sinputer.top/jekyll-obsidian](https://sinputer.top/jekyll-obsidian/)

Choose a built-in theme:

- `minimal` (default): an authored home page, recent posts, a blog, documentation, and project portfolios or custom sections.
- `docs`: a document tree with previous and next links.

Both themes include search, wiki-link previews, page outlines, note relations, and interactive graphs. They support media embeds, translations, and GitHub Discussions comments, with canonical metadata, a sitemap, and Markdown downloads.

## Publish with GitHub Pages

The workflow installs the build tools, so you do not need Ruby or Node.js locally. [Public repositories can use GitHub Pages on GitHub Free](https://docs.github.com/en/pages/quickstart#who-can-use-this-feature).

Publication settings control the generated site, not access to committed files. Anyone who can read the repository can read unpublished notes too. Keep private material out of public repositories, and inspect linked Canvas and Bases files before publishing them as downloads.

**Already have a Gemfile?** Follow [Host Integration](website/jekyll-obsidian-docs/docs/Integration.md#use-bundler) first: the Action requires both `Gemfile` and `Gemfile.lock`, with the builder version matching the Action release.

1. Create `.github/jekyll-obsidian.yml` using [the example configuration](examples/jekyll-obsidian.yml):

<!-- example:site-config -->
```yaml
title: My Site
website:
  source: docs
  theme: minimal
```

2. Copy [the Pages workflow](examples/pages.yml) to `.github/workflows/pages.yml`.
3. Create `docs/index.md`:

<!-- example:public-note -->
```markdown
---
publish: true
title: Welcome
---

# Welcome

My first public note.
```

4. Select **Settings > Pages > Build and deployment > Source > GitHub Actions**, then commit and push to the default branch.

After **Build and deploy Pages** succeeds, find the URL in the `deploy` job or **Settings > Pages**. Project sites normally use `https://<owner>.github.io/<repository>/`; repositories named `<owner>.github.io` use the domain root. The workflow also reads custom-domain settings automatically. See [Deployment](website/jekyll-obsidian-docs/docs/Deployment.md).

## Configure and update

Edit `.github/jekyll-obsidian.yml`. Site identity fields (`title`, `description`, `lang`, `url`, `baseurl`) belong at the YAML root; content, theme, and feature settings belong under `website`. Set `website.source` to a repository-relative content directory and `website.theme` to `minimal` or `docs`. Changes take effect on the next build.

By default, only notes whose frontmatter has the YAML boolean `publish: true` enter the site. To publish folders recursively, list content-relative paths under `website.content.publish_by_default`; `.` selects the whole content tree. Use `publish: false` to exclude a note. Quoted strings such as `"true"` are not booleans. Obsidian's `.obsidian/` and `.trash/` directories are excluded.

A home page is optional: without one, the site can open a section or another public note. At least one public note is required. See [Publishing content](website/jekyll-obsidian-docs/docs/Publishing.md#content-and-navigation) for index selection and navigation.

Switching themes preserves the URLs of notes that remain published. For multilingual sites, set `website.i18n.enabled: true` explicitly to keep translations enabled across theme changes. See [Localization](website/jekyll-obsidian-docs/docs/Localization.md).

See [theme defaults](website/jekyll-obsidian-docs/docs/Customization.md#site-themes) for feature, localization, and comment settings.

To upgrade, change the Action release in the workflow. If you use Bundler, update the Gemfile constraint to the same version, run `bundle update jekyll-obsidian-site`, and commit both dependency files with the workflow. For a standalone local installation, run `gem update jekyll-obsidian-site`.

## Optional local preview

With Ruby 4.0.x on macOS, Linux, or WSL, run from your repository root:

```sh
gem install jekyll-obsidian-site
jekyll-obsidian dev
```

Open `http://127.0.0.1:58000/`. Content and configuration changes trigger a rebuild; failures preserve the last successful site. Run `jekyll-obsidian dev --help` for host, port, base path, and theme options. The gem includes frontend assets, so Node.js is not required.

To create the configuration and workflow locally, run `jekyll-obsidian init --source docs`. It adds a public welcome note only when the content directory is absent or empty, and reports conflicting files without overwriting them. For Bundler commands, see [Host Integration](website/jekyll-obsidian-docs/docs/Integration.md).

For another host, run `jekyll-obsidian build --url https://example.com --baseurl /project` and upload `.jekyll-obsidian-cache/site/`. `jekyll-obsidian clean` removes this project's cache and output.

## Guides and contributing

- [Host Integration](website/jekyll-obsidian-docs/docs/Integration.md): installation, Bundler, and upgrades.
- [Getting Started](website/jekyll-obsidian-docs/docs/Getting%20Started.md): publishing and authoring.
- [Syntax](website/jekyll-obsidian-docs/docs/Syntax.md): Obsidian-flavored Markdown and media embeds.
- [Publishing content](website/jekyll-obsidian-docs/docs/Publishing.md): publication rules, note properties, recommendations, and trusted HTML slides.
- [Reading and navigation](website/jekyll-obsidian-docs/docs/Reading.md): header navigation, search, reading-time hints, graphs, and previews.
- [Customization](website/jekyll-obsidian-docs/docs/Customization.md): site identity, themes, navigation, footer links, and output limits.
- [Archives and favorites](website/jekyll-obsidian-docs/docs/Archives.md): archive tabs, filters, inline reading, Markdown exports, and saved articles.
- [Portfolio](website/jekyll-obsidian-docs/docs/Portfolio.md): project collections and public GitHub Markdown bodies.
- [Analytics](website/jekyll-obsidian-docs/docs/Analytics.md): optional Cloudflare or Google traffic measurement.
- [Comments](website/jekyll-obsidian-docs/docs/Comments.md): GitHub Discussions setup and privacy.
- [Localization](website/jekyll-obsidian-docs/docs/Localization.md): translations, fallback pages, and SEO.
- [Deployment](website/jekyll-obsidian-docs/docs/Deployment.md): hosting, URL paths, and custom domains.

For development setup and native Windows PowerShell commands, read the [Developer Guide](website/jekyll-obsidian-docs/docs/development/index.md). On macOS, Linux, or WSL, run `website/bin/test` from the repository root. It builds frontend assets and packages the gem before running the Ruby, TypeScript, frontend, and Node checks. If running Ruby tests separately from `website/`, first run `npm run build` and `bundle exec ruby scripts/package.rb --skip-assets`, then `bundle exec rake test`; the suite tests an actual installed gem.

## License

MIT
