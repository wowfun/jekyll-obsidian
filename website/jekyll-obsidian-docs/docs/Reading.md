---
publish: true
title: Reading and Navigation
nav_order: 25
tags:
  - guide/reading
description: Use page navigation, search, reading-time hints, graphs, and wiki-link previews.
created: 2026-10-30
updated: 2026-10-30
---

# Reading and Navigation

This guide covers navigation, search, graphs, and reading controls. See [[Customization|Customization]] for theme and feature switches, and [[Archives|Archives and favorites]] for article filters, inline reading, exports, and saving favorites.

## Header and page navigation

Both themes use icon-only header actions for search, language selection and color scheme. Accessible names and hover hints identify each action; search keeps its Ctrl/⌘ K shortcut. Repeated collection headings and descriptions are omitted automatically, and language menus fit their option labels.

Tabs that do not fit the desktop header move into an accessible More menu. The mobile Browse sheet and the Search dialog's quick navigation use the same ordered destinations and active state. Search narrows those quick links by their configured labels while it queries note content. Without JavaScript, the header links remain visible and wrap naturally. Opening Docs from Minimal keeps the Minimal site shell while adding the handbook tree, page outline, and previous or next links.

Switching tabs in the header or mobile Browse sheet keeps the header in place and updates the content, active tab, page controls, and browser history. Minimal sites with archive pages reserve space for reading and export controls on every page, so their availability does not move the navigation. Sites without archive pages need no reservation. Document links in the sidebar also preserve the documentation tree. Navigation uses a full page load when the destination changes the language, header controls, theme assets, or Content Security Policy, or when loading fails. Without JavaScript, links use normal browser navigation.

Every Docs page server-renders the complete documentation tree; JavaScript navigation preserves the shared shell while replacing only page-specific content and context.

## Search

Search builds its index in a Web Worker. By default it searches titles, aliases, tags, and note summaries; [[Customization#Output limits|search settings]] can enable authored full text. Queries accept up to 256 characters and wait briefly for typing to pause. Only one worker query runs at a time. The dialog shows up to 12 matches, the total matching count, and a short text excerpt.

Search focuses its input immediately, including while its Worker loads; use `Ctrl/⌘ K` to open it. Worker initialization times out after 15 seconds, and Worker failures show an unavailable message. After a Worker failure, edit the query to retry in the open dialog, or close and reopen search. Document navigation disposes the previous search Worker, including unfinished initialization. A failed search-module download retries on the next open; a failed graph-module download retries on the next document navigation.

## Back to top

Both themes provide a **Back to top** arrow on index, article, documentation, archive, and favorites pages. It appears in the lower-right corner only after scrolling more than one viewport height, hides again within the first screen, and sits above the mobile toolbar without covering translation notices. When visible, it follows the skip link in keyboard navigation order. Activating it moves focus to the main content and scrolls smoothly to the top, or immediately when reduced motion is preferred, without changing the URL. This default needs no configuration and stays hidden without JavaScript and when printing. Translate its accessible name and hover hint with the `back_to_top` locale message.

The early keyboard position makes the control quick to reach when restoring a scrolled page; pressing Tab again continues into the header. The control and its main-content focus target remain outlined in forced-colors mode.

## Reading time

Both themes show an estimated reading time in the metadata at the top of independent posts, documentation pages, and ordinary pages when the estimate exceeds two minutes. Exactly two minutes stays hidden; 2.1 minutes displays **About 3 min read**. Home pages, directory indexes, system pages, and article lists do not show this hint. It is built into the HTML and works without JavaScript.

The estimate uses 400 Chinese or other CJK characters per minute and 200 words per minute for other text, adding the two before rounding up. Other words are continuous Unicode letter/number sequences, including combining marks. Headings, lists, tables, quotations, inline code, and ordinary code blocks count. Expanded note embeds and imported GitHub Markdown count as part of the displayed body; frontmatter and generated controls or source labels do not. Images, formulas, Mermaid diagrams, media, and embedded attachments add no time; authored captions count as text. Hidden markup is excluded using `hidden`, `aria-hidden="true"`, and the theme's `visually-hidden` class. This is a text-length estimate, not a measure of comprehension time.

Translations use the body actually displayed, including default-language fallback content. The reading speeds and two-minute threshold are fixed; there is no per-page override.

See [[Customization#Reading time|Customization]] to hide or translate the hint.

## Graph and wiki-link previews

A published note places its one-hop graph above Outline and Relations in the right-hand context rail only when it links to, embeds, is linked from, or is embedded by another public note in the current language partition. The graph contains the current note and up to 31 direct neighbours, ordered by degree and then note ID, with at most 64 relations and 64 KiB of embedded data. A notice identifies larger neighbourhoods. The Linked notes disclosure remains available alongside the graph. Isolated notes and notes with only self-links omit the local graph. Node area grows with its degree in the complete public graph.

Use the graph's left button to open the global graph and its right button to enlarge the current note's local graph. In the compact graph, hold Ctrl or ⌘ while scrolling to zoom around the pointer; ordinary scrolling moves the page. In graph dialogs, scroll directly to zoom. With a mouse, drag empty canvas space to pan, and drag a neighbouring node to reposition it; the current node stays fixed at the visual centre. On touchscreens, swipe over the compact graph to scroll the page; open a graph dialog to pan, pinch to zoom, or drag nodes. Nodes are native links, including browser context menus and opening in a new tab. Tab enters the graph once; arrow keys move between links, Home and End reach the first and last link, and Enter follows it. Dense graphs reveal additional labels on hover or focus. Compact simulations pause while hidden or offscreen.

Global graph data loads only when its dialog opens. Graphs above 250 nodes, 1,000 relations, or 512 KiB produce a small count summary at build time; the browser offers local graphs or search without downloading the full graph. There is no generated `/graph/` page or navigation tab, so a published note may use that route.

Rest the pointer on a wiki link for 0.3 seconds to open a reading preview. Leaving before the delay cancels it. Keyboard focus shows catalog metadata immediately without downloading the note body; Alt+ArrowDown expands the preview and enters it. Ordinary Tab continues to the next page control. The expanded body is sanitized and scrolls independently, with normal page scrolling at its boundaries. Its title opens the note; links within the body remain plain text. Touch taps on the original link go directly to the note.

Obsolete body requests are aborted. Each page retains at most 20 preview bodies within a 2 MiB weighted cache, and each fetched note is limited to 1 MiB. Navigation releases the cache. Oversized or failed bodies leave the catalog summary available. Set `previews: false` to disable previews.
