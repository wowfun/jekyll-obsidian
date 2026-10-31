---
publish: true
title: Archives and Favorites
nav_order: 32
tags:
  - guide/archives
description: Configure article archives, filters, inline reading, exports, and browser-local favorites.
created: 2026-10-30
updated: 2026-10-30
---

# Archives and Favorites

Minimal supports archives on Home and custom tabs, with daily grouping, inline reading, Markdown export, and browser-local favorites.

See [[Customization#Custom tabs|Customization]] to declare tabs and [[Publishing|Publishing content]] for article dates and metadata.

## Archive settings and filters

Shared filter URLs accept up to 16 values per facet and 32 in total. Excess values are removed in a deterministic order before posting requests; a visible notice explains the limit, and the URL reflects the retained selections.

Use `website.home.layout: archive` to show the chronological archive at `/`.
`website.blog.page_size` enables a paged archive (1 to 100; default full archive).
`website.blog.facets` maps query parameters to tag prefixes, for example
`{source: "source/", topic: "topics/"}`. Each group uses OR; groups and chronology use AND.
The query names `page`, `year`, `month`, and `day` are reserved for pagination and chronology.
`website.blog.utc_offset: "+08:00"` controls displayed archive dates.
Set `website.blog.timeline_granularity: day` to list dates as `MM-DD` under each year,
newest first, with daily counts and `?day=YYYY-MM-DD` filters. The default is `month`.
Day boundaries follow `utc_offset`; day selection combines with source/topic filters
and resets pagination. Selecting the same date again clears it.
The first page is rendered in HTML. Pagination offers up to five nearby page links and a numeric jump field; both keep the current filters.

Remaining pages use generation-scoped card chunks
and lazy bitmaps. Counts are global, selections survive language switching,
and unknown IDs match zero entries. Loading failures retain the last successful page.
Each ledger entry shows its description (or the note preview when no description is set).

## Read in full

The header's **Read in full** switch expands the current page's articles in place,
following pagination and filters. The choice persists across reloads and languages.
Bodies load only while enabled and approaching the viewport (within 400 pixels),
with at most four requests at once; individual failures
keep the entry and offer retry. Switching off restores the compact ledger.
Reading, pagination and export share that request budget. A bounded cache keeps
sanitized article bodies for return visits within the archive; retrying one article
does not restart the other loads. Relative article links use the final URL after redirects.

## Export Markdown

The paged archive's **Export** button combines all matching entries into one UTF-8
Markdown file in the current language. Each opening copies the current source/topic
selections into independent filters; changing them leaves the archive and URL intact.
Both dates are required and inclusive, using `utc_offset` calendar boundaries.
`website.blog.export_max_days` is a positive integer, default `7`. A selected day
defaults to that day; otherwise the range ends on the latest matching entry and spans
up to the configured limit. Undated entries are excluded; gaps between dates are allowed.
The file contains the site, conditions, count, article metadata and complete published
Markdown, including media links. It uses the archive's order across every page.

Local Markdown images in these resources use their actual published attachment address: an absolute URL when `url` is configured, otherwise a root-relative URL including `baseurl`. Inline and reference-style images share this behavior, as do Copy page and every interface language. Reference images become inline images in the published Markdown so ordinary links sharing a definition keep their destination. Original Markdown files retain their authored relative paths.

This URL projection covers image files only. PDF, audio, video, wiki embeds, and ordinary links keep their authored destinations in exported Markdown, even when the HTML page uses a published attachment URL. Use absolute URLs for those destinations when the exported file must work outside the site.

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

## Archive tabs

In Minimal, set `tab.layout: archive` to give a tab the same paginated ledger, time archive, and facet filters as the homepage archive. The default is `collection`. Archive tabs use `website.blog` settings for page size, timezone, date grouping, timeline granularity, and source/topic facet prefixes. Their counts, filters, pagination, and Markdown exports include only that tab's members. Members appear newest first with undated entries last; `pinned` and `nav_order` do not override archive chronology. The authored introduction remains above the filters. Docs supports the default collection layout only. Translations inherit `tab.layout` from the default-language index and may still override `tab.label`.

## Daily grouping

Set `website.blog.ledger_group_by: day` to group entries under collapsible date headings and omit the per-entry date column. Each heading shows the localized month/day, weekday and count on the current page; dates outside the current year include the year. Dates use `website.blog.utc_offset`, independent of the browser timezone. Only the newest day in the current result opens by default. Days open independently, and manual choices survive filters, pagination and browser history within the current page; reloads reset them. Native disclosures work without JavaScript. Read in full loads visible entries in open days and keeps loaded bodies when a day is closed. This behavior is shared by archive tabs and Favorites. The default grouping remains `year`; static rendering and pagination use the same daily headings.

Daily groups stay in reverse chronological order, with pinned entries first within their own day. The reference year comes from the build's explicit reference time in the configured offset; static headings keep that reference until the next build.

Customize the date headings with locale messages `ledger_date`, `ledger_date_year`, `ledger_months`, `ledger_weekdays`, `ledger_entry` and `ledger_entries`. Month and weekday names are pipe-separated lists of exactly 12 and 7 non-empty names, starting with January and Sunday respectively. Date formats require `{month}` and `{day}`; `ledger_date_year` also requires `{year}`, which is optional in `ledger_date`. Entry formats require `{count}`. Unknown or unbalanced placeholders and invalid name lists stop compilation with a locale diagnostic.

## Local favorites

The minimal theme supports `website.features.favorites: true` (default `false`). It adds Save buttons to ledger entries and post actions, and a Favorites navigation tab at `/favorites/`. `website.navigation.favorites` accepts label, order and visible overrides. The route is reserved while the feature is enabled.

Favorites are stored in the current browser, isolated by site base URL, and shared across language versions. Clearing browser storage removes them; separate origins, browsers and devices have separate collections. The collection retains title, summary, dates, facets and links, but not article bodies. Currently published entries use the selected language; removed entries keep their saved-language snapshot and original link. Network failures show saved summaries with Retry and do not mark articles as removed. Storage failures leave the previous collection intact and show an error.

Saving requires Web Locks in a current browser on HTTPS or localhost. Writes from tabs and language versions share a site lock, so saving an article or refreshing its snapshot does not overwrite another tab's changes. Buttons report success after the write completes. Blocked storage, insufficient space, and unsupported browsers show separate messages. Damaged entries or language snapshots are isolated while healthy favorites remain usable; before repairing a partially damaged collection, one original payload is copied to a site-scoped recovery key. The Recovery copies panel downloads original bytes, restores available favorites without replacing newer snapshots, or explicitly clears the copies. A different damaged payload cannot be repaired until the existing copy has been downloaded and cleared, preventing unlimited backup growth. Older recovery copies remain accessible through the same panel. An unreadable collection or unknown storage version is kept unchanged.

The Favorites page sorts by article day descending, then article ID, with 50 entries per page. Source/topic facets and chronology count only favorites. Read in full loads available articles lazily; removed snapshots remain summaries. Export remains available on the ordinary archive. Identity lookup uses a separate small index and requests only card chunks containing saved IDs.

Enabling favorites also generates a manifest, identity index, deployment descriptor and card chunks for each language, even without archive pagination. Facet bitmap files are generated only for paged archives. The lookup index uses chronological order independently of pinned posts on the home page. Without JavaScript, the Favorites page explains how to enable access to browser storage.

## Loading, retry, and access without JavaScript

Archive scripts load only on pages with archive controls. When favorites are enabled, their script loads on every page to support the recovery panel for damaged browser data. Both modules load asynchronously. While archive controls load, pagination stays disabled. Without JavaScript, archives keep the first page of entries and their article links, hide interactive controls and per-entry filter links, remove the empty chronology column, and explain when more entries are available.

If checking the current deployment fails on return to an ordinary archive, its last loaded generation remains available for filtering and pagination, with a Retry notice. Favorites continue to use saved snapshots until deployment verification succeeds. The reading switch shows a check mark when enabled and reports its state in the hover hint; the search hint includes Ctrl/⌘ K.

Filtering and pagination reuse the loaded collection and requested facet bitmaps. Retry and browser restoration rediscover the current generation from the page, rather than retrying an old deployment's archive path. Refreshing the same page preserves an unfinished page-number input. Facet links retain the selected filters when opened in another tab.

## Archive visibility

Minimal archive Home can set `website.home.hide_tab_sources: true` (default false). It requires a `source` facet in `website.blog.facets`; the compiler warns if it is enabled with `website.home.layout: recent` or the Docs theme. It derives excluded sources from the source tags of actual archive tabs. The button below Sources includes those sources and their entries; counts, chronology, pagination and Markdown export use the same scope. Collection tabs, search, article pages and Favorites retain their full content.

This option requires a facet named `source` in `website.blog.facets`; its prefix is configurable (normally `source/`). Builds reject the option if that facet is missing. Only `tab.topics` values matching this prefix after alias resolution define excluded sources. A topic-only tab, a tab without explicit source topics, or a misspelled source with no matching posts excludes nothing; this option does not infer sources from tab names or membership. Check the tab's source tag IDs when Home does not change.

Locale manifests accept `hidden_tags`, a unique list of complete tag IDs such as `topics/research`. Aliases are resolved through `tag_aliases`, then deduplicated; locales must describe the same canonical set. Single-language sites can also set `hidden_tags`, `tag_aliases` and `tag_labels` in the vault-root `_locale.yml` without enabling i18n. Both modes reject unknown manifest keys. Hidden tags stay on articles and saved entries but are omitted from default archive, collection, Favorites and export choices. Each button reveals hidden choices only within its own facet: “Show hidden topics” for Topics and “Show hidden tags” for other facets. Sources can offer both this disclosure and “Include tab sources”; the controls operate independently. Selected hidden choices remain visible when collapsed.

Disclosure state uses `include_tabs=1` and repeated `show_hidden` parameters naming the expanded facets, for example `show_hidden=source&show_hidden=topic`. Explicit source links automatically include tab sources. Export inherits each facet's state but its controls are independent of the page. With no explicit source selection, exported headings describe the scope as “All (excluding tab sources)” rather than listing every remaining source. Static HTML always starts with the default scope; JavaScript applies URL selections and reveals selected hidden options after loading. Without JavaScript, entries and counts retain that default and the disclosure buttons remain absent. Customize labels with `include_tab_sources`, `hide_tab_sources`, `show_hidden_topics`, `hide_hidden_topics`, `show_hidden_tags`, `hide_hidden_tags` and `all_without_tab_sources`.
