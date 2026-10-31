---
publish: true
title: Customization
nav_order: 30
tags:
  - guide/customization
related:
  - "[[docs/Syntax]]"
  - "[[docs/Localization]]"
description: Adjust site identity, visual tokens, navigation, and repository links.
created: 2026-07-31
updated: 2026-10-30
---

# Customization

Configure site identity, themes, navigation, the footer, property display, and output limits here. See [[Publishing|Publishing content]] for authoring rules, [[Reading|Reading and navigation]] for reader controls, and [[Archives|Archives and favorites]] for archive features.

Edit `.github/jekyll-obsidian.yml` to configure the site. The gem supplies defaults, so the host only needs the settings it wants to override:

```yaml
title: My Site
description: Built from Markdown
lang: en
url: ""
baseurl: ""

website:
  source: docs
  theme: minimal
  repository: owner/repository
  edit_branch: main
  features: {}
  contacts:
    - label: GitHub
      url: https://github.com/owner
    - label: Email
      url: mailto:hello@example.com
```

`website.source` is relative to the host repository root and defaults to `docs`. Configuration precedence is package defaults, host configuration, then explicit command-line or Pages values. See [[Integration|Host Integration]] for build commands and isolation rules.

## Site identity

Keep `title`, `description`, `lang`, `url`, and `baseurl` at the YAML root. Put content, theme, and feature settings under `website`.

`title`, `description`, and `lang` feed the shell, metadata, Atom, and accessibility labels. Set `website.repository` to an `owner/repository` pair to show the Edit link and a GitHub icon on the right of the header. If it is blank, the build checks `GITHUB_REPOSITORY` and the local `origin` remote. These actions stay hidden when no repository can be identified. This host repository setting never changes the Built by Jekyll Obsidian footer link, which always identifies the official project at `https://github.com/wowfun/jekyll-obsidian`.

`website.edit_branch` selects the branch used by Edit and other host source links; it defaults to `main`.

### Footer contacts and site navigation

Add `website.contacts` to place contact links in the footer on every page, in both Minimal and Docs. Each entry requires a short `label` and an `https:`, `mailto:`, or `tel:` URL; use an empty list or omit it when the base configuration does not define contacts. Email, phone, GitHub, LinkedIn, X/Twitter, Mastodon, Bluesky, Instagram, YouTube, Telegram, RSS, and Website links receive an accessible icon automatically. Other providers keep their label as text, so the configuration stays provider-neutral and needs no icon field. Home does not repeat these links below recent posts.

`website.footer.links` adds a Sites section alongside contacts. It defaults to `[]`; empty sections take no space. Both themes share the footer, with stacked sections on mobile and the project credit, license, and year below.

```yaml
website:
  contacts:
    - label: GitHub
      url: https://github.com/wowfun
  footer:
    links:
      - label: Jekyll Obsidian
        url: https://sinputer.top/jekyll-obsidian/
        locale_urls:
          zh-CN: https://sinputer.top/jekyll-obsidian/zh-CN/
```

Every link requires a non-empty `label` and an absolute HTTPS `url` without credentials. Optional `locale_urls` maps language identifiers to full HTTPS addresses; the current UI language selects its override, falling back to `url` when none exists. Addresses are used exactly as configured, including links to another site on the same domain: the current site's `baseurl` and language prefix are never added. Links open in the same tab. Customize the section headings with the `footer_sites` and `contact` locale messages. The theme credit continues to link to the official GitHub repository.

Custom locale messages require `website.i18n.enabled: true`. Put them under `messages` in the root `_locale.yml` or `_translations/<locale>/_locale.yml`. A single-language site can list only its root `lang` in `locales` to customize these headings without creating translation copies.

Configure at most 12 links, with single-line labels up to 64 characters and URLs up to 2,048 characters (including locale overrides). Surrounding Unicode whitespace and byte-order marks (`U+FEFF`) are trimmed; tabs and line breaks are rejected. Locale keys match without case sensitivity, so `zh-cn` matches `zh-CN`; duplicate keys differing only in case are rejected. Overrides for languages not currently enabled are retained but unused, so the same configuration can serve single-language and multilingual builds.

Custom templates read contacts from `page.website.footer.contacts` and the selected navigation links from `page.website.footer.links`. The former replaces `page.website.theme_data.contacts`; update templates that used the old home-only data. The authored contact configuration remains `website.contacts`.

Custom contact CSS must also move from `.minimal-contact` and `.minimal-contact__*` / `.minimal-contact--*` to the corresponding `.site-contact` classes. The old `.minimal-contacts` home container is gone; the shared footer's contact list uses `.site-footer__contacts`.

## Site themes

Each build selects one complete presentation preset. `minimal` supports a Home page, Blog, Docs, and custom sections in one general-purpose shell. `docs` provides a focused hierarchical handbook. Search, wiki-link previews, page outlines, note relations, and the interactive graph are shared capabilities in both themes. A command-line override is useful for comparing the same content without editing configuration:

```sh
jekyll-obsidian dev --theme docs
jekyll-obsidian build --theme minimal --url https://example.test --baseurl ""
```

The built site is written to `.jekyll-obsidian-cache/site/`. Supported theme identifiers are `minimal` and `docs`. Notes that remain published keep their URLs when switching themes; set `website.i18n.enabled: true` explicitly to retain translations.

Feature keys omitted from `website.features` inherit the theme defaults. Explicit YAML booleans can override `search`, `tags`, `feed`, `graph`, `relations`, `previews`, `outline`, and `reading_time`.

| Feature | Minimal | Docs |
| --- | --- | --- |
| `search`, `previews`, `outline`, `relations`, `graph`, `reading_time` | on | on |
| `tags`, `feed` | on | off |

The separate `i18n` and `comments` mappings have their own defaults when present without `enabled`:

| Setting | Minimal | Docs |
| --- | --- | --- |
| `website.i18n` | off | on |
| `website.comments` | on | off |

Omitting either mapping disables it. An explicit `enabled: true` or `enabled: false` overrides its theme default.

Set any shared feature to the YAML boolean `false` to remove it. For example:

```yaml
website:
  features:
    graph: false
    previews: false
```

### Reading time

See [[Reading#Reading time|Reading and navigation]] for display conditions and the calculation.

Hide the hint throughout the site:

```yaml
website:
  features:
    reading_time: false
```

A supplied `reading_time` locale message must contain exactly one `{minutes}` placeholder and no other braces; blank messages are rejected. A Chinese message can be `约 {minutes} 分钟阅读`. Omitting the message uses the English default, marked `lang="en" dir="ltr"` even in another interface language. Custom templates can read the integer `page.website.reading_time_minutes` (zero for no countable text). The estimate is computed even when `reading_time` is disabled; this flag controls the built-in hint, so custom templates retain the same data contract.

Locale messages are loaded only when `website.i18n.enabled` is true. A single-language site can opt in with root-level `lang: en` and `website.i18n: {enabled: true, locales: [en]}`, then set `messages.reading_time` in the root `_locale.yml` (with `name: English`). No translation copies are required. With i18n disabled, `lang` alone does not select or customize this message; the hint uses English.

## Minimal navigation

Minimal begins with Home, Blog, Docs, and Portfolio, ordered at `0`, `10`, `20`, and `30`. Blog and Docs disappear automatically when the content tree has no public post or documentation page. Portfolio uses the source-relative `portfolio` folder by default and appears when that folder contains at least one visible published project. An empty or unpublished folder adds no tab. Override built-in labels, order, visibility, or the Portfolio path under `website.navigation`:

```yaml
website:
  theme: minimal
  navigation:
    home:
      label: Home
      order: 0
      visible: true
    blog:
      label: Writing
      order: 10
      visible: true
    docs:
      label: Handbook
      order: 20
      visible: true
    portfolio:
      path: work
      label: Work
      order: 30
      visible: true
```

See [[Portfolio|Portfolio]] for folder discovery, introductions, card ordering, and GitHub Markdown imports.

## Custom tabs

Minimal and Docs use the same custom-tab contract. Declare a tab on a published folder index, either `index.md` or its eligible `README.md` fallback. That note remains the canonical tab homepage, and its authored body appears above the generated member cards:

```yaml
---
publish: true
content_type: page
tab:
  id: favorites
  label: Favorites
  order: 40
  topics:
    - favorite
    - reference
---
```

`id` is required and must be a lowercase ASCII identifier such as `favorites` or `team-work`; `home`, `blog`, `docs`, and `portfolio` are reserved. The label defaults to the localized index title, and order defaults to `100`. A custom tab is always visible. Its root must be a visible `content_type: page` folder index and cannot sit inside the active Portfolio path.

Members are the union of three sources: every published descendant of the tab folder, any published note that names the tab in `tabs`, and any published note whose `tags` or `categories` match one of the tab's `topics`. Multiple topics use OR matching after Unicode normalization and case folding. Add a page outside the folder without changing its route:

```yaml
---
publish: true
tabs:
  - favorites
---
```

Membership is additional: a Blog post remains active under Blog, a documentation page remains active under Docs, and a Portfolio page remains active under Portfolio. Only ordinary page descendants use the custom tab as their active navigation item; the deepest nested custom root wins. Cards are de-duplicated and sorted by `pinned`, then `nav_order`, localized title, and source path. `nav_exclude: true` removes a folder or topic match and cannot be combined with `tabs`. An empty topic result is valid and leaves only the authored index body.

Duplicate IDs, labels, or destinations, unknown `tabs` references, invalid roots, and reserved conflicts fail the build. Notes keep one canonical URL even when several tabs include them; custom tabs never create redirects or duplicate Search, feed, or sitemap entries.

In Minimal, `tab.layout: archive` selects a paged archive instead of the default `collection` layout. See [[Archives#Archive tabs|Archive tabs]] for membership scope, ordering, and shared settings.

## Color and type

The themes share a narrow set of CSS custom properties. Light mode uses warm paper and surface tones; dark mode uses neutral black and gray. Blue marks links and focus, while terracotta marks relationships and secondary annotations.

Articles and controls use the platform sans-serif stack, with installed Noto Sans CJK or Source Han Sans preferred for CJK text. Code uses the platform monospace stack. The site does not download a webfont, so the exact face follows the reader's operating system while the typographic scale and spacing remain consistent.

Override tokens in your own stylesheet rather than editing hashed build output. Keep text and focus contrast above WCAG AA in both color schemes.

## Page properties

Use `website.properties.hidden` to hide named custom fields from the display projection. It defaults to an empty list and does not change relation discovery. Reserved fields above already have separate rendering or publication behavior and are excluded from this block, as are `alias`, `layout`, and `render_with_liquid`. Custom fields are public by default; the compiler supplies typed display data rather than merging raw properties into Jekyll page controls.

Themes read the typed field array from `page.website.display_properties`. The separate `site.website.properties` mapping holds site-wide display configuration, including `hidden`.

```yaml
website:
  properties:
    hidden: [first_seen, internal_id]
```

Hidden names must be unique valid property names. The setting is site-wide; page-level display overrides are not supported. A page with no visible custom fields has no property block. `source_url` remains a separate clickable original source link beneath the tags.

See [[Publishing#Page properties|Publishing content]] for property types, dates, authors, sources, and related notes.

## Output limits

Large sites can bound generated indexes without removing published pages. These settings apply independently to every locale. Defaults use summary search, an unlimited feed, and six recent posts on Minimal Home.

```yaml
website:
  search:
    mode: summary
    max_entries: 3000
    excerpt_length: 240
    content_types: [post]
  feed:
    max_entries: 100
  home:
    recent_posts_limit: 0
```

`website.search.mode` accepts `summary` (default) or `full`. Summary mode uses each note's existing preview, capped by the positive integer `excerpt_length` (default 240). Choose `full` to index authored text when body-only matches are needed. Both modes index at most 5,000 notes within an 8 MiB payload budget. Notes that exceed the remaining budget are omitted from search; the build reports the indexed count and the search dialog identifies partial coverage. Titles are limited to 512 characters; up to 32 aliases and tags are indexed, each limited to 128 characters. Published pages remain unchanged.

`max_entries` is an optional positive integer that can lower the 5,000-note limit. The newest publication dates (or update dates for undated notes) come first, with note ID as a deterministic tie-breaker. `content_types` filters to any of `page`, `post`, and `doc`; its default empty array includes all types. The Worker also limits indexing to 200,000 field terms overall and 10,000 per field. Reaching either limit shows the partial-coverage notice; use narrower filters or summary mode for large collections.

`website.feed.max_entries` optionally limits the existing feed order to a positive number of entries. `website.home.recent_posts_limit` is a nonnegative integer; zero hides the automatic recent-post rows while retaining authored Home content. These limits do not remove pages, archives, Markdown downloads, or sitemap entries.

## Other feature settings

- [[Archives|Archives and favorites]]: Home layout, pagination, daily grouping, filters, export, and favorites.
- [[Comments|Comments]]: GitHub Discussions and Giscus setup.
- [[Analytics|Analytics]]: Cloudflare or Google Analytics configuration.
- [[Localization|Localization]]: locale lists, translation files, interface messages, and tag labels.
