---
publish: true
title: Publishing Content
nav_order: 15
tags:
  - guide/publishing
description: Control publication, organize pages, and author note properties, dates, and source metadata.
created: 2026-10-30
updated: 2026-10-30
---

# Publishing Content

This guide covers publication rules, page structure, note properties, and source metadata. See [[Syntax|Syntax]] for Markdown authoring and [[Customization|Customization]] for themes and tab configuration.

`website.syntax_profile` pins the Markdown contract and currently accepts only `ofm@1`.

## Publication defaults

`website.content.publish_by_default` is an array of directories relative to `website.source`. Each entry selects Markdown files in that directory and its descendants. The default is an empty array, which keeps `publish: true` as the required opt-in. Use `.` when every Markdown file in the content tree should publish unless it opts out:

```yaml
website:
  content:
    publish_by_default:
      - .
```

An explicit YAML boolean always wins. `publish: false` excludes one note from a selected directory, while `publish: true` includes one note outside those directories. Publication directories do not classify content; `default_type`, `directories.post`, `directories.doc`, and a note's `content_type` still decide whether a published note is a page, post, or document. Attachments remain private unless a published note, its `image` property, or its transclusion closure references them.

## Content and navigation

An explicit `content_type: post | doc | page` wins over directory defaults. Post publication dates use `date`, then `published`, then `created`, then the first Git commit. A production build rejects a post with no deterministic date. On Minimal Home and Blog, posts with `pinned: true` appear before unpinned posts; both groups retain reverse-chronological order. Pinning affects card presentation only, not Atom feed chronology or the previous and next post sequence.

Docs navigation follows vault directories. `nav_order` sorts sibling documents and `nav_exclude: true` removes only that note link; children remain reachable. `index.md` is optional at every level. When no physical `index.md` exists, a published exact `README.md` becomes the folder index. An existing `index.md` reserves that role even when unpublished, leaving `README.md` as an ordinary note. A published root index always owns `/`, so a different `permalink` on that note is rejected. A folder without a public selected index links to its first visible child after `nav_order`, title, and path sorting.

Minimal Home can render without a root index when posts exist; if neither exists, the root redirects to the first visible top-level navigation destination, or the generated Portfolio entry when available. When there is no section entry, it redirects to a public note: prefer notes without `nav_exclude`, then explicit `nav_order` values in ascending order, then source paths in ascending order. If every public note has `nav_exclude: true`, choose from all public notes using the same order. This property hides navigation links, not published content. Translated titles do not change the selected note. The redirect keeps the note at its original URL, uses that URL as canonical, and stays out of the sitemap. A site with no public notes still fails the build.

On indexless Minimal sites, Favorites never becomes the root redirect target. Its home link and canonical URL follow the selected content landing page, whether Favorites is visible in navigation or hidden. When that page is an untranslated fallback, the canonical URL points to the indexable default-language page.

Docs redirects an indexless root to its first navigation item.

## Home and post summaries

Minimal Home renders the public root directory index, followed by the six most recent posts as editorial rows. The index is `index.md`, or the exact sibling `README.md` when no physical `index.md` exists. A selected directory index without an authored level-one heading does not render a substitute heading from its filename or frontmatter title; the resolved title remains available to metadata and navigation. A row with an image places a 16:9 thumbnail beside its summary on wide screens and above it on narrow screens; a row without an image uses the full width with no placeholder. Each summary can also show `subtitle`, a body excerpt, authors, and its publication date. The Blog link opens the complete reverse-chronological list at `/blog/`.

## Page properties

The compiler reserves these note properties for publication behavior and validates each one with a closed schema:

- `publish`, `title`, `subtitle`, `aliases`, `tags`, `author`, `categories`, and `description`
- `permalink`, `image`, and `cssclasses`
- `created` and `updated`
- `content_type`, `date`, `date_basis`, `pinned`, `nav_order`, `nav_exclude`, `tab`, and `tabs`
- `comments`, `github_markdown`, `related`, `source_url`, `source`, `source_title`, `published`, and `lang`

`aliases`, `tags`, `author`, `categories`, `cssclasses`, and `tabs` are string arrays; `subtitle` is a string. `publish`, `pinned`, `nav_exclude`, and `comments` use YAML booleans. `tab` is the closed mapping documented in [[Customization#Custom tabs|Custom tabs]]. `github_markdown` accepts only the URL or mapping documented in [[Portfolio|Portfolio]], and only on a Portfolio project wrapper. Dates use ISO 8601. A note title comes from `title`, its first level-one heading, or its filename, in that order.

`lang` declares the authored body language of notes in `website.i18n.shared_directories`; see [[Localization#Share one body across languages|shared content]]. It does not select the interface language.

### Custom properties

Other top-level properties may contain scalar values or flat scalar lists. Custom property names must be normalized, single-line text without leading or trailing whitespace. Both themes display these fields by default in an expanded property block below tags and the original source link, above the body. Labels use the original field names and fields retain their authored order. Nested lists and mappings are not supported.

Plain strings are escaped text with their line breaks preserved; Markdown, HTML, and Liquid inside them are not evaluated. A complete HTTP(S) URL without credentials becomes a clickable link. Numbers and booleans retain their values, including `0` and `false`. Native YAML dates and timestamps use ISO 8601 `<time>` values; a quoted date remains a string. Null, empty strings, and empty lists display as `null`, `""`, and `[]`. Flat lists retain order and duplicates, with each value rendered by its type.

Authored property values display in full, like the note body. The search and feed output limits apply to generated indexes; they do not truncate page properties.

Reserved fields above have separate rendering or publication behavior and are excluded from the property block, as are `alias`, `layout`, and `render_with_liquid`. Custom fields are public by default. See [[Customization#Page properties|Customization]] to hide fields; hiding their display does not remove note relations.

### Links and related notes

A complete wiki link becomes an ordinary note relation when it is a YAML double-quoted string. In the property block it also links to the public target, using the authored alias or the target title. Unresolved links retain their authored alias or target as text, with the existing compiler diagnostics. Wiki targets follow the page locale; ordinary external URLs remain unchanged.

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

### Dates

`date_basis` is optional authored metadata: `published` labels the post date as Published; `observed` labels it as First observed. Omission uses Published. It changes the date label only, without changing date selection or chronology. The compiler does not derive `date_basis`, including when a post's publication date comes from Git. Translations inherit the default note's value and cannot change it.

`updated` is optional and appears in page metadata only when the author supplies it; the compiler never infers an update date from Git. A post's publication time uses `date`, then `published`, then `created`, then its first Git commit. Atom entries use explicit `updated` when present and otherwise use that publication time for posts. A non-post note without `updated` is omitted from the feed.

### Authors and categories

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

## Source metadata and directory tags

Obsidian Web Clipper notes can keep `published`, `source`, and quoted author wiki links. `published` accepts an ISO-8601 date or date-time; post chronology uses `date`, `published`, `created`, then Git first commit time. `source` accepts the same credential-free HTTP(S) URLs as `source_url`; when both exist, `source_url` supplies the original-source link. These recognized fields do not also appear as custom properties. Unresolved author wiki links display the authored name and produce a warning.

Use directory policy to publish a clipping collection without adding publication fields to every note:

```yaml
website:
  content:
    publish_by_default: [clippings]
    directories:
      post: [clippings]
      doc: [docs]
    directory_tags:
      clippings: [source/clippings]
```

`directory_tags` defaults to `{}`. Each normalized source-relative directory (or `.` for the whole content root) adds its tags to that directory and all descendants. Nested rules accumulate and duplicate tags collapse. It neither publishes a note nor changes the Markdown on disk. `publish: false` still excludes drafts; a section index can keep `content_type: page`.

Tags must be non-blank strings; whitespace-only values are rejected. Non-blank tag names retain their authored spelling, including internal spaces.

Directory rules (`publish_by_default`, `directories`, and `directory_tags`) match source paths case-sensitively on every platform. Use the directory's exact spelling: `clippings` does not select `Clippings`. Case-folded collision checks reject ambiguous paths; they do not expand publication rules.

Optional `source_title` labels the original-source link in article headers, archive cards, favorites and Markdown exports. Surrounding Unicode whitespace and byte-order marks (`U+FEFF`) are trimmed; omitting it or supplying a string empty after trimming shows the URL. This normalization does not rewrite the source Markdown. It is plain text, never HTML, and does not replace the note title. A title without a source URL does not create a link.

## Expiring recommendations

A vault-root `_recommendations.json` can supply external recommendations without adding graph edges:

```json
{ "version": 1, "items": { "a.md": [{ "path": "b.md", "expires_at": "2026-10-18T00:00:00Z" }] } }
```

Paths refer to public posts in the default vault; titles and URLs follow the active locale. Manual `related` takes precedence. Missing, private, self and expired targets are omitted. The metadata file is not published. Automatic cards require JavaScript and disappear at expiry even between builds; manual related cards remain available without JavaScript.

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
