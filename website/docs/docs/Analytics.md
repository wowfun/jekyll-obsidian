---
publish: true
title: Analytics
nav_order: 42
tags:
  - guide/analytics
description: Add optional Cloudflare Web Analytics or Google Analytics without running a site backend.
created: 2026-08-07
updated: 2026-08-07
---

# Analytics

Jekyll Obsidian can load Cloudflare Web Analytics or Google Analytics on a published site. Analytics is off when `website.analytics` is absent, and one site can select only one provider.

The build never sends page data to an analytics service. It validates the configuration and adds the provider client only to production pages. Local development does not load either client, and redirect pages remain untracked so a redirect does not add a second page view.

## Use Cloudflare Web Analytics

Cloudflare Web Analytics is the recommended option for a public site that needs basic traffic counts. It is free, does not require moving DNS or proxying the site through Cloudflare, and Cloudflare describes it as privacy-first analytics that does not collect or use visitors' personal data. Read [Cloudflare's product description](https://developers.cloudflare.com/web-analytics/about/) before enabling it.

Create a site in the Cloudflare Web Analytics dashboard, copy its site token, and add it outside the managed configuration block:

```yaml
website:
  analytics:
    provider: cloudflare
    token: SITE_TOKEN
```

The production site loads Cloudflare's official beacon once. Cloudflare automatically tracks the History API used by the Docs theme, including `pushState` and `popstate` navigation. See [Cloudflare's single-page application guidance](https://developers.cloudflare.com/web-analytics/get-started/web-analytics-spa/).

## Use Google Analytics

Choose Google when the site already uses a Google Analytics 4 property. Copy the web data stream's measurement ID and add this configuration:

```yaml
website:
  analytics:
    provider: google
    measurement_id: G-XXXXXXXXXX
```

In Google Analytics, open the web stream's Enhanced Measurement settings and keep both Page loads and Page changes based on browser history events enabled. The site loads `gtag.js` and configures the property once; it does not send a second custom `page_view` when Docs changes pages. See [Google's single-page application guidance](https://developers.google.com/analytics/devguides/collection/ga4/single-page-applications).

Google Analytics can use cookies such as `_ga` and identifiers to distinguish visitors. Review [Google's data collection description](https://support.google.com/analytics/answer/11593727?hl=en) and the rules that apply to the site's audience before enabling it.

## Configuration and security

`provider` accepts only `cloudflare` or `google`. Cloudflare requires `token`; Google requires `measurement_id`. Provider fields cannot be mixed, and unknown keys or incorrectly typed values fail the build. Remove the complete `analytics` mapping to turn tracking off.

The compiler adds only the Content Security Policy sources required by the selected provider. Cloudflare pages allow its beacon and reporting endpoint. Google pages allow Google Tag Manager and the GA4 collection endpoints. The configuration does not enable Google Ads, DoubleClick, inline scripts, or evaluation of generated code.

Both options make third-party network requests from the visitor's browser. Jekyll Obsidian does not provide a consent banner, advertising features, custom events, dual-provider tracking, a server-side proxy, or an analytics dashboard. Add any consent flow required by the site's jurisdiction and audience before enabling analytics.

## Troubleshoot analytics

| Symptom | Check |
| --- | --- |
| No analytics request appears during local preview | This is expected. Analytics clients load only from production output. |
| The build rejects the mapping | Use exactly one provider and its matching string ID. Remove fields for the other provider and unknown keys. |
| Cloudflare shows no visits | Confirm that the token belongs to this site and inspect the browser for a blocked beacon request. |
| Google misses Docs page changes | Enable both page-load and browser-history events in the GA4 web stream's Enhanced Measurement settings. |
| Google counts a page twice | Remove separately installed analytics snippets or tag-manager page-view rules. Jekyll Obsidian initializes its client once. |

See [[Customization#Analytics|Customization]] for the configuration's place in the complete site file and [[Deployment|Deployment]] for production builds.
