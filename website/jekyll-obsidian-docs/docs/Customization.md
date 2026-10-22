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
updated: 2026-10-21
---

# Customization

Both themes use icon-only header actions for search, language selection and color scheme. Accessible names and hover hints identify each action; search keeps its Ctrl/⌘ K shortcut. Repeated collection headings and descriptions are omitted automatically, and language menus fit their option labels. Daily archives open only the newest day on the current page by default and retain manual folding choices through filtering and pagination until reload. These presentation defaults need no feature flags. Archive homepages, pagination and browser-local favorites remain explicit site choices.

Both themes provide a **Back to top** arrow on index, article, documentation, archive, and favorites pages. It appears in the lower-right corner only after scrolling more than one viewport height, hides again within the first screen, and sits above the mobile toolbar without covering translation notices. When visible, it follows the skip link in keyboard navigation order. Activating it moves focus to the main content and scrolls smoothly to the top, or immediately when reduced motion is preferred, without changing the URL. This default needs no configuration and stays hidden without JavaScript and when printing. Translate its accessible name and hover hint with the `back_to_top` locale message.

The early keyboard position makes the control quick to reach when restoring a scrolled page; pressing Tab again continues into the header. The control and its main-content focus target remain outlined in forced-colors mode.

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
  syntax_profile: ofm@1
  repository: owner/repository
  edit_branch: main
  content:
    publish_by_default: []
    default_type: doc
    directories:
      post: []
      doc: []
  features: {}
  html:
    slides/runtime: /presentations/runtime/
  contacts:
    - label: GitHub
      url: https://github.com/owner
    - label: Email
      url: mailto:hello@example.com
```

`website.source` is relative to the host repository root and defaults to `docs`. You can use `website/docs` or another directory inside the repository. The project documentation lives in `website/jekyll-obsidian-docs` and is not installed with the gem.

Configuration precedence is package defaults, `.github/jekyll-obsidian.yml`, then explicit command-line or Pages values. All host settings are directly editable. `jekyll-obsidian build` creates an isolated Jekyll source in its cache and writes output to `.jekyll-obsidian-cache/site/`. Use the `jekyll-obsidian` commands; the host's existing Jekyll `_config.yml` and plugins do not participate in the build.

`website.theme` selects `minimal` or `docs`. `website.syntax_profile` pins the Markdown contract and currently accepts only `ofm@1`. `website.edit_branch` selects the branch used by Edit and other host source links; it defaults to `main`.

## Publication defaults

`website.content.publish_by_default` is an array of directories relative to `website.source`. Each entry selects Markdown files in that directory and its descendants. The default is an empty array, which keeps `publish: true` as the required opt-in. Use `.` when every Markdown file in the content tree should publish unless it opts out:

```yaml
website:
  content:
    publish_by_default:
      - .
```

An explicit YAML boolean always wins. `publish: false` excludes one note from a selected directory, while `publish: true` includes one note outside those directories. Publication directories do not classify content; `default_type`, `directories.post`, `directories.doc`, and a note's `content_type` still decide whether a published note is a page, post, or document. Attachments remain private unless a published note, its `image` property, or its transclusion closure references them.

## Standalone HTML slides

`website.html` explicitly publishes trusted HTML outside the theme renderer. Map a vault-relative source path to one root-relative public route:

```yaml
website:
  html:
    slides/runtime: /presentations/runtime/
    slides/status.html: /status.html
```

A file mapping requires an exact `.html` source and an `.html` target, and publishes only that file. A directory mapping requires an exact `index.html` and a target ending in `/`; it preserves the relative paths of regular bundle files. The complete bundle can therefore include CSS, JavaScript, fonts, images, and application-specific data files. Markdown and compiler locale manifests such as `_locale.yml` remain under the normal compiler rules and are not copied with the bundle.

The source must be a normalized, vault-relative POSIX path. Sources cannot overlap. The target must not include `baseurl`, a query, a fragment, encoded path separators, `/`, `/assets/website/`, or `/assets/vault/`. File, directory, locale, generated-system, and host Jekyll destination collisions fail before output is appended.

The compiler copies these files byte for byte: it does not apply a theme, execute Liquid, inject metadata, synthesize a Content Security Policy, or rewrite relative URLs. Root-relative URLs authored inside raw HTML must already include the deployment `baseurl`; relative URLs are usually more portable. A normal Markdown link or `[[slides/runtime/index.html|Open slides]]` resolves to the configured route. Non-HTML bundle media referenced by a Markdown embed or an `image` property reuse their mapped route without creating a second vault-asset copy. `![[...html]]` is rejected because raw HTML cannot be embedded in a themed page.

An HTML mapping is publication authorization independent of `website.content.publish_by_default`. Raw documents are shared across locales and stay out of navigation, Search, Graph, feeds, sitemap, Markdown resources, and automatic locale copies; link them manually from a public Markdown page. These documents execute as trusted same-origin code, so review the entire mapped bundle as public executable content. The manifest authorizes paths, not response MIME types: for files with uncommon extensions, verify that the deployment server sends the intended `Content-Type` and disables unsafe content sniffing. This repository's working example is the [[slides/jekyll-obsidian/index.html|five-minute Jekyll Obsidian slide tour]].

## Site identity

`title`, `description`, and `lang` feed the shell, metadata, Atom, and accessibility labels. Set `website.repository` to an `owner/repository` pair to show the Edit link and a GitHub icon on the right of the header. If it is blank, the build checks `GITHUB_REPOSITORY` and the local `origin` remote. These actions stay hidden when no repository can be identified. This host repository setting never changes the Built by Jekyll Obsidian footer link, which always identifies the official project at `https://github.com/wowfun/jekyll-obsidian`.

Minimal Home renders the public root directory index, followed by the six most recent posts as editorial rows. The index is `index.md`, or the exact sibling `README.md` when no physical `index.md` exists. A selected directory index without an authored level-one heading does not render a substitute heading from its filename or frontmatter title; the resolved title remains available to metadata and navigation. A row with an image places a 16:9 thumbnail beside its summary on wide screens and above it on narrow screens; a row without an image uses the full width with no placeholder. Each summary can also show `subtitle`, a body excerpt, authors, and its publication date. The Blog link opens the complete reverse-chronological list at `/blog/`.

Add `website.contacts` to place contact links after the recent-post section. Each entry requires a short `label` and an `https:`, `mailto:`, or `tel:` URL; use an empty list or omit it when the base configuration does not define contacts. Email, phone, GitHub, LinkedIn, X/Twitter, Mastodon, Bluesky, Instagram, YouTube, Telegram, RSS, and Website links receive an accessible icon automatically. Other providers keep their label as text, so the configuration stays provider-neutral and needs no icon field.

## Site themes

Each build selects one complete presentation preset. `minimal` supports a Home page, Blog, Docs, and custom sections in one general-purpose shell. `docs` provides a focused hierarchical handbook. Search, wiki-link previews, page outlines, note relations, and the interactive graph are shared capabilities in both themes. A command-line override is useful for comparing the same content without editing configuration:

```sh
jekyll-obsidian dev --theme docs
jekyll-obsidian build --theme minimal --url https://example.test --baseurl ""
```

The built site is written to `.jekyll-obsidian-cache/site/`. Supported theme identifiers are `minimal` and `docs`.

Feature keys omitted from `website.features` inherit the theme defaults. Explicit YAML booleans can override `search`, `tags`, `feed`, `graph`, `relations`, `previews`, and `outline`.

| Feature | Minimal | Docs |
| --- | --- | --- |
| `search`, `previews`, `outline`, `relations`, `graph` | on | on |
| `tags`, `feed` | on | off |

Set any shared feature to the YAML boolean `false` to remove it. For example:

```yaml
website:
  features:
    graph: false
    previews: false
```

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

The Portfolio path is relative to `website.source`; an explicit path replaces the default `portfolio` path. Published Markdown descendants become Portfolio pages, so an explicit `content_type` within that path must be `page`. A public directory index keeps its authored introduction above the project grid. Use `<path>/index.md`, or `<path>/README.md` when no physical index exists. When the selected index is not public, the compiler generates the Portfolio index at that route. The selected index itself is not a project. Projects with `pinned: true` appear first; each group is then ordered by `nav_order`, title, and path. Set `nav_exclude: true` on a project to omit its card, or set `website.navigation.portfolio.visible: false` to hide only the tab while keeping the Portfolio index and project pages public.

Each project card uses its `image`, title, and `description`, falling back to a preview from the body when no description is present. Local GIF, WebP, AVIF, and APNG files are copied byte for byte and rendered with `<img>`, which preserves animation. The compiler does not transcode them or generate thumbnails.

A project can replace its local body with a public GitHub Markdown file by setting `github_markdown`. The local wrapper continues to own card metadata and its route, while the resolved remote body supplies the detail page, outline, Search text, preview, and Markdown endpoint. See [[Portfolio|Portfolio]] for the accepted URL and mapping forms, empty-body rule, branch refresh behavior, content limits, relative URLs, localization, and security boundary.

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

In Minimal, set `tab.layout: archive` to give a tab the same paginated ledger, time archive, and facet filters as the homepage archive. The default is `collection`. Archive tabs use `website.blog` settings for page size, timezone, date grouping, timeline granularity, and source/topic facet prefixes. Their counts, filters, pagination, and Markdown exports include only that tab's members. Members appear newest first with undated entries last; `pinned` and `nav_order` do not override archive chronology. The authored introduction remains above the filters. Docs supports the default collection layout only. Translations inherit `tab.layout` from the default-language index and may still override `tab.label`.

Tabs that do not fit the desktop header move into an accessible More menu. The mobile Browse sheet and the Search dialog's quick navigation use the same ordered destinations and active state. Search narrows those quick links by their configured labels while it queries note content. Without JavaScript, the header links remain visible and wrap naturally. Opening Docs from Minimal keeps the Minimal site shell while adding the handbook tree, page outline, and previous or next links.

## Expiring recommendations

A vault-root `_recommendations.json` can supply external recommendations without adding graph edges:

```json
{ "version": 1, "items": { "a.md": [{ "path": "b.md", "expires_at": "2026-10-18T00:00:00Z" }] } }
```

Paths refer to public posts in the default vault; titles and URLs follow the active locale. Manual `related` takes precedence. Missing, private, self and expired targets are omitted. The metadata file is not published. Automatic cards require JavaScript and disappear at expiry even between builds; manual related cards remain available without JavaScript.

## Graph and wiki-link previews

A published note places its one-hop graph above Outline and Relations in the right-hand context rail only when it links to, embeds, is linked from, or is embedded by another public note in the current language partition. The graph contains the current note and those direct neighbours. Isolated notes and notes with only self-links omit the local graph, while the complete graph still contains their nodes. Node area grows with its degree in the complete public graph.

Use the graph's left button to open the complete graph and its right button to enlarge the current note's local graph. In either view, scroll the mouse wheel over the canvas to zoom around the pointer, drag empty canvas space to pan, and drag a neighbouring node to reposition it; the current node stays fixed at the visual centre. Click a node to visit that note, or focus it and press Enter or Space. The complete graph JSON loads only when its dialog is opened and always contains every public node and relation. To keep the page responsive, the SVG viewer declines to render complete graphs above 250 nodes or 1,000 relations and directs readers to local graphs or search instead. There is no generated `/graph/` page or navigation tab, so a published note may use that route.

Rest the pointer on a wiki link for 0.3 seconds, or keyboard-focus it, to open its reading preview. Leaving before the pointer delay cancels the preview; keyboard focus remains immediate. Catalog metadata appears first, followed by a compact, independently scrolling view of the target note's sanitized body. The preview title opens the target note; links inside the body remain plain text. Touch taps on the original wiki link continue directly to the target page. Set `previews: false` to disable this behavior.

## GitHub Discussions comments

Both themes can attach a GitHub Discussion to each `content_type: post` through [Giscus](https://giscus.app/). Comments are disabled when `website.comments` is absent. When the mapping is present and omits `enabled`, Minimal enables comments while Docs keeps them disabled. To use comments, first prepare a public GitHub repository:

1. Enable **Settings → General → Features → Discussions**.
2. Create a `Blog comments` category. The Announcement format is recommended because maintainers and Giscus can create discussions there while visitors can still reply.
3. Install the [Giscus GitHub App](https://github.com/apps/giscus) for that repository.
4. Enter the repository and category at [giscus.app](https://giscus.app/) and copy their generated IDs.

Then add the values to the host configuration:

```yaml
website:
  theme: minimal
  repository: owner/site
  comments:
    # Optional. Omit this to reuse website.repository.
    repository: owner/community
    repository_id: R_kgDOxxxxxxxx
    category: Blog comments
    category_id: DIC_kwDOxxxxxxxx
```

Add `enabled: true` inside `comments` when the active theme is Docs; add `enabled: false` to keep a configured Minimal site dormant. The comments repository may be the publication repository or a separate public community repository. The build never checks whether Discussions is enabled or the Giscus App is installed. Missing provider IDs produce a warning and a non-interactive fallback instead of failing the build. Add a `giscus.json` file to the comments repository when you want to restrict embedding to the production site origin.

Once enabled, every `content_type: post` has comments in any theme. Disable one article with a YAML boolean:

```yaml
---
publish: true
content_type: post
comments: false
---
```

Threads use a strict, route-independent term derived from the note path. Changing a domain, `baseurl`, or permalink keeps the thread; moving or renaming the source note creates a new identity. Reactions are enabled, the input appears above existing comments, and Giscus lazily loads its iframe near the comments area. The Giscus client itself is still requested when a published comment page initializes.

Local development does not connect to Giscus. It shows a publication-only notice and a normal link to the repository's Discussions page. Published and CI builds load the widget, synchronize it with the site's light or dark scheme, and retain the GitHub link when JavaScript or the external service is unavailable. Localized pages share the post's route-independent Discussion thread, while the Giscus interface follows each page locale when supported and otherwise falls back to English.

See [[Comments|Comments with GitHub Discussions]] for thread identity, origin restrictions, privacy boundaries, and troubleshooting.

## Analytics

Analytics is off when `website.analytics` is absent. A production site can select Cloudflare Web Analytics:

```yaml
website:
  analytics:
    provider: cloudflare
    token: SITE_TOKEN
```

Or it can select one Google Analytics 4 property:

```yaml
website:
  analytics:
    provider: google
    measurement_id: G-XXXXXXXXXX
```

Only one provider may be active. Local development and redirect pages do not load either client. See [[Analytics|Analytics]] for provider setup, Docs navigation tracking, Content Security Policy sources, privacy differences, and troubleshooting.

## Localization

Both themes can opt into static localization by listing locales under `website.i18n`. The mapping enables localization by default for Docs and stays disabled by default for Minimal; set `enabled: true` there. The top-level `lang` is the default locale and must appear in the list when localization is enabled:

```yaml
lang: en

website:
  theme: docs
  i18n:
    locales:
      - en
      - zh-CN
```

Add `enabled: true` inside `i18n` for Minimal; add `enabled: false` to keep a configured Docs locale plan dormant. Keep the default language in the normal content tree. Put translated notes at the same relative path below `_translations/<locale>/`. A translation inherits the publication state of its public default-language note; set `publish: false` on the translation to show the existing default-language fallback instead. Every configured locale requires `_locale.yml` at its locale root; `name` is required, while `hreflang`, `dir`, and the closed `messages` catalog are optional. A missing or disabled translation does not fail the build. It keeps its localized URL, briefly shows a notice over the default-language content, and is excluded from search-engine indexing and the sitemap.

```yaml
name: 简体中文
hreflang: zh-Hans
dir: ltr
messages:
  search: 搜索
```

`dir` accepts only `ltr` or `rtl`. Message values must be strings and keys must belong to the closed built-in theme catalog; unknown keys fail the build. Omitted messages use the built-in English text. The locale list order is also the language-switcher order.

The default locale keeps existing URLs. Other locales use their configured tag as a prefix, such as `/zh-CN/docs/Getting%20Started/`. Navigation, search, theme system pages, language switching, SEO metadata, and locale assets stay partitioned for Minimal and Docs alike.

See [[Localization|Localization guide]] for locale manifests, translation authority, fallback pages, SEO behavior, and troubleshooting.

## Color and type

The themes share a narrow set of CSS custom properties. Light mode uses warm paper and surface tones; dark mode uses neutral black and gray. Blue marks links and focus, while terracotta marks relationships and secondary annotations.

Articles and controls use the platform sans-serif stack, with installed Noto Sans CJK or Source Han Sans preferred for CJK text. Code uses the platform monospace stack. The site does not download a webfont, so the exact face follows the reader's operating system while the typographic scale and spacing remain consistent.

Override tokens in your own stylesheet rather than editing hashed build output. Keep text and focus contrast above WCAG AA in both color schemes.

## Output limits

Large sites can bound generated indexes without removing published pages. These settings apply independently to every locale. Omitted settings preserve full-text search, an unlimited feed, and six recent posts on Minimal Home.

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

`website.search.mode` accepts `full` or `summary`. Summary mode uses each note's existing preview, capped by the positive integer `excerpt_length` (default 240). `max_entries` is an optional positive integer; when set, the newest publication dates (or update dates for undated notes) come first, with note ID as a deterministic tie-breaker. `content_types` filters to any of `page`, `post`, and `doc`; its default empty array includes all types.

`website.feed.max_entries` optionally limits the existing feed order to a positive number of entries. `website.home.recent_posts_limit` is a nonnegative integer; zero hides the automatic recent-post rows while retaining authored Home content. These limits do not remove pages, archives, Markdown downloads, or sitemap entries.


Use `website.home.layout: archive` to show the chronological archive at `/`.
`website.blog.page_size` enables a paged archive (1–100; default full archive).
`website.blog.facets` maps query parameters to tag prefixes, for example
`{source: "source/", topic: "topics/"}`. Each group uses OR; groups and chronology use AND.
The query names `page`, `year`, `month`, and `day` are reserved for pagination and chronology.
`website.blog.utc_offset: "+08:00"` controls displayed archive dates.
Set `website.blog.timeline_granularity: day` to list dates as `MM-DD` under each year,
newest first, with daily counts and `?day=YYYY-MM-DD` filters. The default is `month`.
Day boundaries follow `utc_offset`; day selection combines with source/topic filters
and resets pagination. Selecting the same date again clears it.
The first page is rendered in HTML. Pagination offers up to five nearby page links and a numeric jump field; both keep the current filters. Header actions in Minimal and Docs use icons, localized accessible names and hover hints; the language menu retains full language names, and active reading and color-scheme states remain visible.

Remaining pages use generation-scoped card chunks
and lazy bitmaps. Counts are global, selections survive language switching,
and unknown IDs match zero entries. Loading failures retain the last successful page.
Each ledger entry shows its description (or the note preview when no description is set).
The header's **Read in full** switch expands the current page's articles in place,
following pagination and filters. The choice persists across reloads and languages.
Bodies load only while enabled and approaching the viewport (within 400 pixels),
with at most four requests at once; individual failures
keep the entry and offer retry. Switching off restores the compact ledger.
Reading, pagination and export share that request budget. A bounded cache keeps
sanitized article bodies for return visits within the archive; retrying one article
does not restart the other loads. Relative article links use the final URL after redirects.

The paged archive's **Export** button combines all matching entries into one UTF-8
Markdown file in the current language. Each opening copies the current source/topic
selections into independent filters; changing them leaves the archive and URL intact.
Both dates are required and inclusive, using `utc_offset` calendar boundaries.
`website.blog.export_max_days` is a positive integer, default `7`. A selected day
defaults to that day; otherwise the range ends on the latest matching entry and spans
up to the configured limit. Undated entries are excluded; gaps between dates are allowed.
The file contains the site, conditions, count, article metadata and complete published
Markdown, including media links. It uses the archive's order across every page.
Up to four resources load concurrently. Cancel or close stops the download; any failed
body prevents an incomplete file and retry reuses successfully loaded bodies from that task.
If the site changes while the panel is open, its selection refreshes before downloading.
Review the updated conditions and count, then click **Download Markdown** again.
Progress counts successfully loaded bodies. Date edits briefly wait for typing to stop
before calculating matches; download is disabled immediately while conditions change.
Successful bodies also serve repeated downloads until the conditions change or the
panel closes. The file is assembled from Blob parts without a combined document string.
Each export allows up to 5,000 entries and 64 MiB of decoded Markdown response bytes,
including in-flight bodies. Exceeding either limit stops the task with a message to
narrow the selection; no partial file is downloaded. Failed transfers release their
byte reservation before retry. Entry details show an indeterminate loading phase.
The matching count remains exact even when it exceeds the limit; only the first
5,000 matching ordinals are collected. The byte budget measures response data,
not browser heap: decoded strings, retained bodies and the download Blob also
consume memory. Close the panel to release the retained bodies.

Locale manifests may provide `tag_labels` and flattened `tag_aliases` keyed by complete
stable tags. Labels can differ across languages; IDs remain shared.

## Page properties

The compiler reserves these note properties for publication behavior and validates each one with a closed schema:

- `publish`, `title`, `subtitle`, `aliases`, `tags`, `author`, `categories`, and `description`
- `permalink`, `image`, and `cssclasses`
- `created` and `updated`
- `content_type`, `date`, `date_basis`, `pinned`, `nav_order`, `nav_exclude`, `tab`, and `tabs`
- `comments`, `github_markdown`, `related`, and `source_url`

Other top-level properties may contain scalar values or flat scalar lists. Custom property names must be normalized, single-line text without leading or trailing whitespace. Both themes display these fields by default in an expanded property block below tags and the original source link, above the body. Labels use the original field names and fields retain their authored order. Nested lists and mappings are not supported.

Plain strings are escaped text with their line breaks preserved; Markdown, HTML, and Liquid inside them are not evaluated. A complete HTTP(S) URL without credentials becomes a clickable link. Numbers and booleans retain their values, including `0` and `false`. Native YAML dates and timestamps use ISO 8601 `<time>` values; a quoted date remains a string. Null, empty strings, and empty lists display as `null`, `""`, and `[]`. Flat lists retain order and duplicates, with each value rendered by its type.

Authored property values display in full, like the note body. The search and feed output limits apply to generated indexes; they do not truncate page properties.

A complete wiki link becomes an ordinary note relation when it is a YAML double-quoted string. In the property block it also links to the public target, using the authored alias or the target title. Unresolved links retain their authored alias or target as text, with the existing compiler diagnostics. Wiki targets follow the page locale; ordinary external URLs remain unchanged.

Use `website.properties.hidden` to hide named custom fields from the display projection. It defaults to an empty list and does not change relation discovery. Reserved fields above already have separate rendering or publication behavior and are excluded from this block, as are `alias`, `layout`, and `render_with_liquid`. Custom fields are public by default; the compiler supplies typed display data rather than merging raw properties into Jekyll page controls.

`date_basis` is optional authored metadata: `published` labels the post date as Published; `observed` labels it as First observed. Omission uses Published. It changes the date label only, without changing date selection or chronology. The compiler does not derive `date_basis`, including when a post's publication date comes from Git. Translations inherit the default note's value and cannot change it.

Themes read the typed field array from `page.website.display_properties`. The separate `site.website.properties` mapping holds site-wide display configuration, including `hidden`.

```yaml
website:
  properties:
    hidden: [first_seen, internal_id]
```

Hidden names must be unique valid property names. The setting is site-wide; page-level display overrides are not supported. A page with no visible custom fields has no property block. `source_url` remains a separate clickable original source link beneath the tags.

The ignored Jekyll controls `alias`, `layout`, and `render_with_liquid` do not create note relations, even when their values resemble wiki links.

```yaml
project: "[[portfolio/fauni-search|Fauni Search]]"
references:
  - background
  - "[[docs/development/architecture]]"
related:
  - "[[blog/launch-notes]]"
  - "[[docs/Getting Started|Start here]]"
```

`related` is the curated list variant. It accepts only a list of double-quoted wiki links, preserves the authored order, removes repeated targets, and shows the resolved pages as Recent-post-style cards at the bottom of the page. Broken related links fail a production build. Other custom-property links join Direct links, Backlinks, and Graph data independently of their property-block visibility: hiding a field's display does not remove its note relations.

`aliases`, `tags`, `author`, `categories`, `cssclasses`, and `tabs` are string arrays; `subtitle` is a string. `publish`, `pinned`, `nav_exclude`, and `comments` use YAML booleans. `tab` is the closed mapping documented above. `github_markdown` accepts only the URL or mapping documented in [[Portfolio|Portfolio]], and only on a Portfolio project wrapper. Dates use ISO 8601. A note title comes from `title`, its first level-one heading, or its filename, in that order.

`updated` is optional and appears in page metadata only when the author supplies it; the compiler never infers an update date from Git. A post's publication time uses `date`, then `created`, then its first Git commit. Atom entries use explicit `updated` when present and otherwise use that publication time for posts. A non-post note without `updated` is omitted from the feed.

Minimal Home shows `subtitle` below the article title, then uses `description` or a compiler-generated body excerpt for the summary. When `author` is present, the summary footer lists its values. Both `author` and `categories` join `tags` in the Home Topics area. Their entries may be ordinary strings or wiki links to public notes:

```yaml
---
subtitle: Dreamers among programmers
author:
  - "[[People/Ada Lovelace|Ada]]"
  - Editorial team
categories:
  - "[[AI]]"
  - "[[Machine Learning|ML]]"
---
```

Wiki-link entries must be YAML double-quoted strings. Their visible label uses the alias after `|`, or the target note title when no alias is supplied. Every Home Topics capsule opens the matching Blog filter; a wiki-linked author shown in a post summary may additionally link directly to that public author page. On Minimal Blog, tags and categories appear together below each archive date and as filter capsules beside the publication date on the article page. Repeating the same name across `tags` and `categories` shows one topic. Unresolved wiki links produce a compiler warning and remain filterable text instead of leaking `[[...]]` into the site.

Author and category wiki links now use the same UTF-8 percent-encoded fragments as body links, related cards, and custom-property links. For example, a heading fragment `#你好-世界` appears in a generated URL as `#%E4%BD%A0%E5%A5%BD-%E4%B8%96%E7%95%8C`. The heading ID and destination stay the same; existing links using the unencoded fragment still identify that heading.

## Content and navigation

An explicit `content_type: post | doc | page` wins over directory defaults. Post publication dates use `date`, then `created`, then the first Git commit. A production build rejects a post with no deterministic date. On Minimal Home and Blog, posts with `pinned: true` appear before unpinned posts; both groups retain reverse-chronological order. Pinning affects card presentation only, not Atom feed chronology or the previous and next post sequence.

Docs navigation follows vault directories. `nav_order` sorts sibling documents and `nav_exclude: true` removes only that note link; children remain reachable. `index.md` is optional at every level. When no physical `index.md` exists, a published exact `README.md` becomes the folder index. An existing `index.md` reserves that role even when unpublished, leaving `README.md` as an ordinary note. A published root index always owns `/`, so a different `permalink` on that note is rejected. A folder without a public selected index links to its first visible child after `nav_order`, title, and path sorting. Minimal Home can render without a root index when posts exist; if neither exists, the root redirects to the first visible top-level navigation destination. Docs redirects an indexless root to its first navigation item. Every Docs page server-renders the complete documentation tree; JavaScript navigation preserves the shared shell while replacing only page-specific content and context. Search builds its index in a Web Worker. Local graphs are projected by the compiler; the browser fetches the complete graph only after its dialog opens.

See [[docs/development/architecture|Architecture]] before changing compiler or adapter seams.

`source_url`: an absolute HTTP(S) URL without credentials; shown as a clickable original source link.

## Daily ledger and local favorites

Set `website.blog.ledger_group_by: day` to group entries under collapsible date headings and omit the per-entry date column. Each heading shows the localized month/day, weekday and count on the current page; dates outside the current year include the year. Dates use `website.blog.utc_offset`, independent of the browser timezone. Only the newest day in the current result opens by default. Days open independently, and manual choices survive filters, pagination and browser history within the current page; reloads reset them. Native disclosures work without JavaScript. Read in full loads visible entries in open days and keeps loaded bodies when a day is closed. This behavior is shared by archive tabs and Favorites. The default grouping remains `year`; static rendering and pagination use the same daily headings.

Daily groups stay in reverse chronological order, with pinned entries first within their own day. The reference year comes from the build's explicit reference time in the configured offset; static headings keep that reference until the next build.

Customize the date headings with locale messages `ledger_date`, `ledger_date_year`, `ledger_months`, `ledger_weekdays`, `ledger_entry` and `ledger_entries`. Month and weekday names are pipe-separated lists of exactly 12 and 7 non-empty names, starting with January and Sunday respectively. Date formats require `{month}` and `{day}`; `ledger_date_year` also requires `{year}`, which is optional in `ledger_date`. Entry formats require `{count}`. Unknown or unbalanced placeholders and invalid name lists stop compilation with a locale diagnostic.

The minimal theme supports `website.features.favorites: true` (default `false`). It adds Save buttons to ledger entries and post actions, and a Favorites navigation tab at `/favorites/`. `website.navigation.favorites` accepts label, order and visible overrides. The route is reserved while the feature is enabled.

Favorites are stored in the current browser, isolated by site base URL, and shared across language versions. Clearing browser storage removes them; separate origins, browsers and devices have separate collections. The collection retains title, summary, dates, facets and links, but not article bodies. Currently published entries use the selected language; removed entries keep their saved-language snapshot and original link. Network failures show saved summaries with Retry and do not mark articles as removed. Storage failures leave the previous collection intact and show an error.

Saving requires Web Locks in a current browser on HTTPS or localhost. Writes from tabs and language versions share a site lock, so saving an article or refreshing its snapshot does not overwrite another tab's changes. Buttons report success after the write completes. Blocked storage, insufficient space, and unsupported browsers show separate messages. Damaged entries or language snapshots are isolated while healthy favorites remain usable; before repairing a partially damaged collection, one original payload is copied to a site-scoped recovery key. The Recovery copies panel downloads original bytes, restores available favorites without replacing newer snapshots, or explicitly clears the copies. A different damaged payload cannot be repaired until the existing copy has been downloaded and cleared, preventing unlimited backup growth. Older recovery copies remain accessible through the same panel. An unreadable collection or unknown storage version is kept unchanged.

The Favorites page sorts by article day descending, then article ID, with 50 entries per page. Source/topic facets and chronology count only favorites. Read in full loads available articles lazily; removed snapshots remain summaries. Export remains available on the ordinary archive. Identity lookup uses a separate small index and requests only card chunks containing saved IDs.

Enabling favorites also generates a manifest, identity index, deployment descriptor and card chunks for each language, even without archive pagination. Facet bitmap files are generated only for paged archives. The lookup index uses chronological order independently of pinned posts on the home page. Without JavaScript, the Favorites page explains how to enable access to browser storage.

If checking the current deployment fails on return to an ordinary archive, its last loaded generation remains available for filtering and pagination, with a Retry notice. Favorites continue to use saved snapshots until deployment verification succeeds. The reading switch shows a check mark when enabled and reports its state in the hover hint; the search hint includes Ctrl/⌘ K.

Filtering and pagination reuse the loaded collection and requested facet bitmaps. Retry and browser restoration rediscover the current generation from the page, rather than retrying an old deployment's archive path. Refreshing the same page preserves an unfinished page-number input. Facet links retain the selected filters when opened in another tab.

### Archive visibility

Minimal archive Home can set `website.home.hide_tab_sources: true` (default false). It requires a `source` facet in `website.blog.facets`; the compiler warns if it is enabled with `website.home.layout: recent` or the Docs theme. It derives excluded sources from the source tags of actual archive tabs. The button below Sources includes those sources and their entries; counts, chronology, pagination and Markdown export use the same scope. Collection tabs, search, article pages and Favorites retain their full content.

This option requires a facet named `source` in `website.blog.facets`; its prefix is configurable (normally `source/`). Builds reject the option if that facet is missing. Only `tab.topics` values matching this prefix after alias resolution define excluded sources. A topic-only tab, a tab without explicit source topics, or a misspelled source with no matching posts excludes nothing; this option does not infer sources from tab names or membership. Check the tab's source tag IDs when Home does not change.

Locale manifests accept `hidden_tags`, a unique list of complete tag IDs such as `topics/research`. Aliases are resolved through `tag_aliases`, then deduplicated; locales must describe the same canonical set. Single-language sites can also set `hidden_tags`, `tag_aliases` and `tag_labels` in the vault-root `_locale.yml` without enabling i18n. Both modes reject unknown manifest keys. Hidden tags stay on articles and saved entries but are omitted from default archive, collection, Favorites and export choices. Each button reveals hidden choices only within its own facet: “Show hidden topics” for Topics and “Show hidden tags” for other facets. Sources can offer both this disclosure and “Include tab sources”; the controls operate independently. Selected hidden choices remain visible when collapsed.

Disclosure state uses `include_tabs=1` and repeated `show_hidden` parameters naming the expanded facets, for example `show_hidden=source&show_hidden=topic`. Explicit source links automatically include tab sources. Export inherits each facet's state but its controls are independent of the page. With no explicit source selection, exported headings describe the scope as “All (excluding tab sources)” rather than listing every remaining source. Static HTML always starts with the default scope; JavaScript applies URL selections and reveals selected hidden options after loading. Without JavaScript, entries and counts retain that default and the disclosure buttons remain absent. Customize labels with `include_tab_sources`, `hide_tab_sources`, `show_hidden_topics`, `hide_hidden_topics`, `show_hidden_tags`, `hide_hidden_tags` and `all_without_tab_sources`.
