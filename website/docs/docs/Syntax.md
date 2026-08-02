---
publish: true
title: Syntax
nav_order: 20
aliases:
  - OFM reference
tags:
  - guide/syntax
  - ofm
description: The OFM v1 authoring surface, with links, embeds, callouts, math, and media.
created: 2026-07-31
updated: 2026-07-31
---

# Syntax

The `ofm@1` profile has a versioned contract. It favors source that reads well in Obsidian, on the generated site, and in a plain text editor.

## Links and embeds

Use a wikilink for another note and an alias for display text: [[docs/development/architecture|compiler architecture]]. A heading fragment links to [[docs/development/architecture#Compiler boundary|Compiler boundary]]. A block fragment links to [[docs/development/architecture#^compiler-contract|compiler contract]].

The next excerpt is embedded from the architecture note:

![[docs/development/architecture#^compiler-contract]]

Embeds keep their source attribution. When the same excerpt appears more than once, the compiler scopes its DOM IDs so anchors remain unique.

## Text marks and tasks

Common Markdown works alongside ==highlighting==, footnotes, and task states.[^contract]

- [x] Publish a root index.
- [ ] Replace the sample title.
- [/] Review a draft.

[^contract]: The full compatibility table is maintained in [[docs/development/ofm-conformance|OFM v1 Conformance]].

## Callouts

> [!tip] Source remains useful
> A callout is still a readable blockquote in editors that do not recognize Obsidian syntax.

> [!question]- A folded note
> Folded callouts use a native details element, so they remain keyboard accessible.

> [!field-observation] Custom type
> Unknown callout identifiers use the neutral callout style.

> [!note] Nested context
> A parent callout can contain ordinary text.
> > [!tip] Inner observation
> > The inner callout keeps its own title and type.

## Math and diagrams

Inline math such as $e^{i\pi}+1=0$ keeps its source visible until MathJax loads.

$$
\operatorname{score}(q, d)=\sum_{t\in q}\operatorname{weight}(t, d)
$$

```mermaid
flowchart LR
  Vault --> Compiler
  Compiler --> Jekyll
  Jekyll --> Pages
```

Mermaid and MathJax load only on pages that use them.

## Media

An image embed can include its width or width and height:

![[assets/research-folio.svg|640]]

```md
![[diagram.png|640x360]]
![[paper.pdf#page=3]]
![[paper.pdf#height=560]]
```

Local audio, video, and PDF files use native browser controls. In v1, `.3gp` is audio and `.webm` is video. PDF embeds accept page and height options. Canvas and Bases files become download cards because v1 does not execute their data models.

## Tags and comments

Inline tags such as #field-notes and nested tags such as #guide/syntax join tags from frontmatter. The site uses one tag index with stable anchors.

Obsidian comments and HTML comments do not appear in HTML, previews, search, graph metadata, or feeds.

%% This sentence is intentionally private to the source. %%

Read [[中文示例|CJK Showcase]] for mixed-script examples.
