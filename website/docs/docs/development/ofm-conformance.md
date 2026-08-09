---
publish: true
title: OFM v1 Conformance
nav_order: 20
aliases:
  - OFM conformance
tags:
  - guide/development
  - ofm
  - specification
description: The pinned ofm@1 compatibility contract for notes, embeds, media, plugins, and build errors.
created: 2026-07-31
updated: 2026-08-09
---

# OFM v1 Conformance

The `ofm@1` profile is pinned to the Obsidian Help repository at commit [`1d26fe9d22673ba476c77919800ce514dc0907e0`](https://github.com/obsidianmd/obsidian-help/tree/1d26fe9d22673ba476c77919800ce514dc0907e0). This document describes the template contract. It does not claim compatibility with future Obsidian releases.

Each feature has one of three outcomes:

- `render`: the compiler produces site HTML or structured site data.
- `download`: the compiler publishes the referenced file as a download card but does not interpret its contents.
- `unsupported`: the compiler does not interpret the feature in v1.

## Notes and text

| Obsidian syntax or behavior | Outcome | v1 contract |
| --- | --- | --- |
| CommonMark paragraphs, lists, quotations, code, tables, and strikethrough | render | Parsed once per public note with Commonmarker 2.9.0. |
| Hard line breaks | render | Obsidian-style line breaks are enabled by the syntax profile. |
| Wikilinks | render | Resolution checks a vault-relative path, then a source-relative path, then a unique basename. |
| Wikilink display text | render | `[[note\|label]]` uses `label`. Frontmatter aliases do not become implicit link targets. |
| Heading and block links | render | Heading chains resolve by their terminal heading within the stated chain; duplicate headings receive stable suffixed IDs, and `^block-id` fragments resolve within a public target. Missing fragments keep links unresolved, while missing embed fragments follow the production/development error policy below. |
| Note, heading, and block embeds | render | Each embed gets a semantic wrapper, source link, and instance-scoped DOM IDs. One host page may expand at most 16 levels, 256 instances, and 2 MiB of embedded HTML. Development shows a deterministic placeholder at the limit; production fails. |
| Highlights | render | `==highlighted text==` produces semantic highlight markup. |
| Footnotes | render | Commonmarker footnotes are enabled. |
| Math | render | Inline and display math retain readable source and load MathJax only on pages that need it. |
| Mermaid code blocks | render | The source remains readable without JavaScript. Mermaid loads only when present. |
| CJK emphasis | render | Commonmarker CJK emphasis is enabled. Search adds deterministic CJK unigrams and bigrams. |
| Standard and relaxed task states | render | Standard and custom task markers keep their original state in `data-task`; each disabled checkbox has an accessible state label. |
| Tags and nested tags | render | Inline and frontmatter tags join one tag index. Nested tags use stable anchors on that page. |
| Properties in the supported allowlist | render | `publish`, `title`, `subtitle`, `aliases`, `tags`, `author`, `categories`, `description`, `permalink`, `image`, `cssclasses`, `created`, `updated`, `content_type`, `date`, `pinned`, `nav_order`, `nav_exclude`, `navigation`, `comments`, and `github_markdown` are accepted with strict types. `pinned` is a boolean that places Minimal Blog and Portfolio cards before their unpinned peers. `updated` is optional and never inferred from Git. `navigation` is a closed mapping of optional `label`, `order`, and `visible` values and is available only to public pages. `github_markdown` is limited to Portfolio project wrappers and replaces an empty local body with one public GitHub Markdown file. `author` and `categories` are string arrays; wiki-link entries must be double-quoted and resolve through the public-note linker. `image` must resolve to a local published image and supplies the public `og:image` URL. |
| Unknown properties and Jekyll control keys | unsupported | They are excluded from page data, HTML, JSON, and XML. |

## Callouts and comments

| Obsidian syntax or behavior | Outcome | v1 contract |
| --- | --- | --- |
| Standard callouts | render | Type, title, and body are rendered with semantic markup. |
| Nested callouts | render | Nesting follows the source blockquote structure. |
| Folded callouts using `+` or `-` | render | Fold state maps to a native `details` element. |
| Custom callout identifiers | render | Unknown identifiers render through the neutral callout style without remote assets. |
| `%%` comments | unsupported | Removed before HTML, search, previews, feeds, and JSON are derived. The authored Markdown resource preserves body source, so comments in a public note remain publicly readable there. |
| HTML comments | unsupported | Removed before HTML, search, previews, feeds, and JSON are derived. The authored Markdown resource preserves body source. |

## Links, embeds, and media

| Obsidian syntax or behavior | Outcome | v1 contract |
| --- | --- | --- |
| Markdown links to notes | render | Internal URLs use the same resolver and URL builder as wikilinks. |
| External HTTP and HTTPS links | render | Preserved with context-safe escaping. |
| `javascript:`, `data:`, `file:`, and `vbscript:` Markdown URLs | unsupported | Rejected. |
| Images: APNG, AVIF, BMP, GIF, JPEG, PNG, SVG, WebP | render | Local files publish only when reached from public authored content or its transclusion closure. HTTPS images and GIFs remain remote. Wikilink dimensions and Markdown alt suffixes such as `alt\|320x180` are supported for both. Animated formats are copied without transcoding. |
| Audio: 3GP, FLAC, M4A, MP3, OGG, WAV | render | Rendered with native controls when local and reachable. In v1, `.3gp` is always audio. |
| Video: MKV, MOV, MP4, OGV, WebM | render | Local reachable files and direct HTTPS video URLs render with native controls. In v1, `.webm` is always video; browser codec support still applies. |
| PDF embeds | render | Native PDF objects support page and height options. Only local published attachments are embedded. |
| YouTube, Bilibili, and Vimeo video links | render | Markdown image syntax produces a canonical lazy player with the provider's minimum permissions. Shortened URLs are rejected because builds never expand them over the network. |
| X and Twitter status links | render | Markdown image syntax produces a viewport-near Tweet widget with tracking protection enabled and a canonical X fallback link. The provider script and frame permission exist only on pages that contain a Tweet. |
| HTTPS iframe embeds | render | A complete authored `iframe` element is parsed and rebuilt by the compiler. Known video providers use their canonical player policy; all other pages receive a fixed sandbox, lazy loading, an accessible title, and a fallback link. Authored scripts, event handlers, `srcdoc`, permission policy, and sandbox values are discarded. Credentials, custom ports, insecure URLs, and unclosed frames fail the build. |
| Canvas `.canvas` links and embeds | download | Published as a download card. Canvas data is not rendered. |
| Bases `.base` links and embeds | download | Published as a download card. Bases queries are not executed. |
| Other or unknown attachment types | unsupported | They produce a fatal compiler diagnostic and are never copied into the published site. |
| Raw HTML other than iframe embeds | render | Trusted author HTML passes through after comments are removed. Authors must review it before publishing. An iframe in inline code, a code fence, or a comment stays inert. |
| Local `href` or `src` found only in raw HTML | unsupported | Raw HTML is trusted and passed through, but it does not cause local files to be published. |
| Remote HTTPS author media | render | Every active source is compiler classified and contributes only its own origin to that page's meta CSP. Builds do not contact providers. Runtime availability and privacy remain the author's responsibility. |

## Plugins and dynamic content

| Feature | Outcome | v1 contract |
| --- | --- | --- |
| Dataview and DataviewJS | unsupported | Queries and scripts are not executed. |
| Third-party Markdown dialects | unsupported | v1 does not expose a parser registry. |
| Obsidian plugin runtime | unsupported | The static site does not run Obsidian plugins. |
| Interactive Canvas or Bases views | unsupported | Their files remain available only through download cards. |

## Error policy

Development builds show a placeholder for missing, private, ambiguous, or over-budget embeds so the author can repair the source. Production and CI builds stop on those embed errors, transclusion cycles, path escapes, symlinks, and route or asset collisions. Ambiguous note and attachment basenames have separate diagnostics.

A missing or private ordinary link produces a warning and an unresolved link state in every environment. It does not publish the target.

Relations are recorded before rendering as typed `link` or `embed` occurrences. Backlinks list links, the separate Embedded by section lists embeds, and graph data preserves both edge kinds. Links inside transcluded content remain relationships of the note that authored them.
