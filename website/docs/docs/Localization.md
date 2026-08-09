---
publish: true
title: Localization
nav_order: 45
tags:
  - guide/localization
  - i18n
description: Publish locale overlays with localized navigation, search, and SEO metadata.
created: 2026-08-04
updated: 2026-08-09
---

# Localization

Static localization is available in Minimal and Docs. One build publishes every configured locale, so a localized site does not need a second Jekyll invocation, a translation service, or browser language detection.

## Enable localization

Localization is disabled for every theme when `website.i18n` is absent. When the mapping exists and omits `enabled`, the active theme supplies this default:

| Theme | Default with `website.i18n` present |
| --- | --- |
| `minimal` | Disabled |
| `docs` | Enabled |

The top-level `lang` is the default locale and must appear in `locales`. List order controls the language switcher order.

```yaml
lang: en

website:
  theme: docs
  i18n:
    locales:
      - en
      - zh-CN
```

Add `enabled: true` under `i18n` for Minimal. Add `enabled: false` to keep a configured Docs locale plan dormant. Locale tags use a BCP 47 style form such as `en`, `zh-CN`, or `ar-EG`; comparisons are case-insensitive, duplicates are rejected, and `assets` is reserved.

## Lay out locale content

The default language stays in the normal content tree. Each other locale mirrors that tree below `_translations/<locale>/`:

```text
content/
├── _locale.yml
├── Start.md
├── guide/
│   └── Advanced.md
└── _translations/
    └── zh-CN/
        ├── _locale.yml
        ├── Start.md
        └── guide/
            └── Advanced.md
```

Relative paths pair translations. In this example, `_translations/zh-CN/guide/Advanced.md` translates `guide/Advanced.md`. A translated note without a default note at the same path is an orphan and fails the build. Locale roots do not require `index.md`; each one redirects to its localized form of the default tree's first ordered page.

The default tree owns site structure. It decides which notes exist, how they are classified, their structural `nav_order`, and which public routes they use. Translations supply localized content without creating a separate information architecture. Presentation lists may use each locale's rendered title as a stable tie-breaker; for example, Portfolio projects with the same `nav_order` follow their localized titles.

## Define a locale manifest

Every configured locale needs `_locale.yml` at its locale root. The default locale manifest belongs at the content root; another locale uses `_translations/<locale>/_locale.yml`.

```yaml
name: 简体中文
hreflang: zh-Hans
dir: ltr
messages:
  search: 搜索
```

`name` is required and appears in the language switcher. `hreflang` defaults to the configured locale tag. `dir` defaults to `ltr` and accepts only `ltr` or `rtl`.

`messages` overrides fixed interface text used by the themes. Values must be strings, and every key must belong to the built-in catalog. Unknown keys and non-string values fail the build. Omitted messages use the built-in English text, so a locale can begin with a small, reviewed set of overrides.

## Write a translation

Every translated note inherits publication from its public default-language counterpart, so the translated frontmatter can omit `publish`:

```yaml
---
title: 快速开始
description: 安装并构建第一个站点。
tags:
  - 指南
---
```

A translation can replace the body and the translatable properties `title`, `subtitle`, `description`, `tags`, `author`, `categories`, `image`, and `cssclasses`. When the default page opts into top-level navigation, its translation may also replace `navigation.label`. It inherits omitted values from the default note. Set the YAML boolean `publish: false` on a translation to disable only that translation and serve the default-language fallback at its localized URL.

A translated Portfolio wrapper may select its own `github_markdown` file or provide a local body. The remote property does not carry into a physical translation that supplies its own content. When the translated wrapper is absent, the ordinary fallback page uses the default-language project and its imported body. See [[Portfolio#Import a GitHub Markdown file|Portfolio]] for the source contract.

Structural properties belong to the default note. This includes `permalink`, `content_type`, `date`, `created`, `updated`, `pinned`, `nav_order`, `nav_exclude`, `aliases`, and `comments`. Omit these properties from the translation; if present, they must exactly match the default value. Always omit `navigation.order` and `navigation.visible` from a translation because any attempt to set them is rejected. A post without `date` or `created` inherits the default note's Git-derived publication date. `updated` is never derived from Git; omit it unless the default note declares an explicit update date. Committing only a translation therefore changes neither post chronology nor the Blog order.

## Understand localized URLs and resources

The default locale keeps its existing URLs. Other locales use the configured locale tag as the first path segment:

```text
guide/Start.md
→ /guide/Start/

_translations/zh-CN/guide/Start.md
→ /zh-CN/guide/Start/
```

The site's `baseurl` still prefixes both forms. Locale tags are preserved as configured in public paths.

Each locale receives its own instances of the active theme's navigation, previous and next links, tags, note-local graph and relations, search index, feed, and system pages. Its complete graph is a locale-specific resource opened from note pages rather than a generated `/graph/` page. Default-locale resources stay below `/assets/website/`; another locale uses `/assets/website/i18n/<locale>/`. This keeps navigation, previews, search, and graph data from different languages separate.

## Link notes and share attachments

Wikilinks, embeds, backlinks, and source actions resolve in the current locale first. When a translated target is unavailable, the compiler uses the default note. The Edit action points to the source file that supplied the displayed content.

Binary attachments remain shared in the default content tree. Do not put locale-specific images, PDFs, Canvas files, or other binary assets under `_translations/`. A translated note can continue to reference a shared attachment from the default tree.

## Handle missing translations

When a note has no translation, the build still succeeds and the compiler creates its locale-prefixed URL. A missing translation is not a warning or an error. The page shows a localized missing-translation notice and displays the default-language content. The authored content retains the default language and text direction, including when the surrounding locale is right-to-left.

A fallback page has a canonical link to the default page and a `noindex` directive. It is omitted from the sitemap and from reciprocal `hreflang` groups. The language switcher can still link to it, which keeps the localized navigation complete while making the SEO boundary explicit.

## Switch languages and publish SEO metadata

The language switcher is server-rendered with ordinary links and follows the configured locale order. It works without JavaScript. JavaScript only adds dismissal and focus behavior; the site never detects a browser language or redirects automatically.

Real translations use self-canonical URLs. Every complete translation group emits reciprocal `hreflang` links plus `x-default` for the default-language page. The page shell receives the current locale's `<html lang dir>` values, while fallback authored content keeps its own language boundary.

Dates use a deterministic ISO representation in every locale. This avoids English month names appearing in otherwise localized navigation and system pages.

## Troubleshoot localization builds

| Build failure | What to check |
| --- | --- |
| Default locale is missing | Add top-level `lang` to `website.i18n.locales`. |
| Locale manifest is missing or invalid | Add `_locale.yml` at every locale root, provide `name`, and check `hreflang`, `dir`, and message values. |
| Translation is orphaned | Create the default note at the same relative path, or remove the translation. |
| Translation overrides structure | Remove structural properties from the translation, or make them exactly match the default note. |
| Localized asset is unsupported | Move the binary asset to the default content tree and reference the shared file. |
| Locale route collides | Rename the conflicting note or permalink. Locale feeds, assets, and system pages reserve their destination paths. |

Keep locale tags and relative note paths stable after publication. Changing either one changes localized public URLs, while moving or renaming a note can also change its comment-thread identity.
