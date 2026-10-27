# Imported project fixture

This host keeps the former public Jekyll Obsidian project available only to browser tests. The two manifests pin its English and Chinese README bodies without network access. The related posts exercise the three-node local graph and keyboard navigation.

`build-sites.mjs` builds both themes with and without localization. It copies the documentation site's locale messages into the localized host so source-action translations stay current. The nonlocalized host retains the theme's default Portfolio and Projects labels.

The published documentation uses authored Showcase cases instead. Its builds receive an empty import manifest, so these fixture documents cannot enter public search, Markdown or sitemap output.
