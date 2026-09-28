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
updated: 2026-08-06
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

- [x] Publish at least one note.
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

External HTTPS media uses the same Markdown image syntax. GIFs and other supported images keep image semantics and optional Obsidian dimensions. Direct video files use native controls. YouTube, Bilibili, and Vimeo links become privacy-conscious, lazy player frames, while X or Twitter status links become lazy Tweet embeds with a normal link as their fallback.

```md
![Animation|320x180](https://media.example/loop.gif)
![Product tour](https://cdn.example/tour.mp4)
![Conference talk](https://www.youtube.com/watch?v=NnTvZWp5Q7o&t=1m30s)
![](https://www.bilibili.com/video/BV1E7411e7hC?p=2)
![](https://vimeo.com/212731897)
![](https://x.com/obsdmd/status/1580548874246443010)
```

Use an explicit iframe only when the page cannot be represented by one of those media forms:

```html
<iframe
  src="https://example.com/interactive"
  title="Interactive example"
  height="560">
</iframe>
```

The compiler accepts only HTTPS iframe URLs without credentials or custom ports. It discards authored active attributes, rebuilds known video players from canonical provider URLs, and applies one fixed sandbox to generic pages. Every external embed loads only on pages that contain it and receives the narrow Content Security Policy it needs. Generic frames and Tweets retain plain HTTPS fallback links. Builds never contact the provider. An iframe written inside inline code, a code fence, or a comment remains inert source text.

## Tags and comments

Inline tags such as #field-notes and nested tags such as #guide/syntax join tags from frontmatter. The site uses one tag index with stable anchors.

Obsidian comments and HTML comments do not appear in HTML, previews, search, graph metadata, or feeds.

Every authored public note also has Copy page and View as Markdown actions. Both use the same frontmatter-free Markdown resource and preserve the authored body, including OFM syntax and comments. Treat comments in a public note as public source text.

%% This sentence is intentionally private to the source. %%

Read [[中文示例|CJK Showcase]] for mixed-script examples.
