import { copyFile, cp, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const workspaceRoot = path.dirname(projectRoot);
const environment = {
  ...process.env,
  BUNDLE_GEMFILE: path.join(projectRoot, "Gemfile"),
  GITHUB_REPOSITORY: "example/jekyll-obsidian",
  JEKYLL_ENV: "production",
  JEKYLL_OBSIDIAN_GITHUB_MARKDOWN_MANIFEST_IN: ".jekyll-obsidian-cache/github-markdown-browser.json",
};

function build(host, theme, name, config) {
  const code = `require "jekyll_obsidian/runtime"; runtime = JekyllObsidian::Runtime.new(root: ARGV[0], config_path: ARGV[1], assets_root: ARGV[2], destination_name: ARGV[3]); runtime.build(theme: ARGV[4], url: "http://127.0.0.1:4173", baseurl: ARGV[5], quiet: true)`;
  const result = spawnSync("ruby", ["-S", "bundle", "exec", "ruby", "-e", code, host, config,
    path.join(projectRoot, ".jekyll-obsidian-cache/assets"), `site-browser-${name}`, theme, `/__site__/${name}`], {
    cwd: projectRoot, env: environment, stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`browser fixture build exited with ${result.status ?? result.signal}`);
}

async function buildFixtureSites(host, suffix, config) {
  for (const theme of ["minimal", "docs"]) {
    const name = `${theme}-${suffix}`;
    build(host, theme, name, config);
    const destination = path.join(workspaceRoot, `.jekyll-obsidian-cache/site-browser-${name}`);
    await rm(destination, { force: true, recursive: true });
    await cp(path.join(host, `.jekyll-obsidian-cache/site-browser-${name}`), destination, { recursive: true });
  }
}

await mkdir(path.join(workspaceRoot, ".jekyll-obsidian-cache"), { recursive: true });
await copyFile(path.join(projectRoot, "tests/browser/fixtures/github-markdown-default.json"),
  path.join(workspaceRoot, ".jekyll-obsidian-cache/github-markdown-browser.json"));
for (const theme of ["minimal", "docs"]) {
  build(workspaceRoot, theme, theme, path.join(projectRoot, "scripts/example-config.yml"));
}

const fixtureHost = await mkdtemp(path.join(tmpdir(), "jekyll-obsidian-browser-"));
try {
  await mkdir(path.join(fixtureHost, "website"));
  await cp(path.join(projectRoot, "jekyll-obsidian-docs"), path.join(fixtureHost, "website/jekyll-obsidian-docs"), { recursive: true });
  await mkdir(path.join(fixtureHost, ".github"));
  await copyFile(path.join(projectRoot, "tests/browser/fixtures/i18n-host.yml"), path.join(fixtureHost, ".github/jekyll-obsidian.yml"));
  await mkdir(path.join(fixtureHost, ".jekyll-obsidian-cache"));
  await copyFile(path.join(projectRoot, "tests/browser/fixtures/github-markdown-i18n.json"),
    path.join(fixtureHost, ".jekyll-obsidian-cache/github-markdown-browser.json"));
  await buildFixtureSites(fixtureHost, "i18n", path.join(fixtureHost, ".github/jekyll-obsidian.yml"));
} finally {
  await rm(fixtureHost, { force: true, recursive: true });
}

const propertiesHost = await mkdtemp(path.join(tmpdir(), "jekyll-obsidian-properties-"));
try {
  await cp(path.join(projectRoot, "tests/browser/fixtures/note-properties"), propertiesHost, { recursive: true });
  await mkdir(path.join(propertiesHost, ".jekyll-obsidian-cache"));
  await writeFile(path.join(propertiesHost, ".jekyll-obsidian-cache/github-markdown-browser.json"),
    JSON.stringify({ version: 1, documents: [] }));
  await buildFixtureSites(propertiesHost, "properties", path.join(propertiesHost, "host.yml"));
} finally {
  await rm(propertiesHost, { force: true, recursive: true });
}

const mediaHost = await mkdtemp(path.join(tmpdir(), "jekyll-obsidian-media-"));
try {
  await mkdir(path.join(mediaHost, "vault/_translations/zh-CN"), { recursive: true });
  await mkdir(path.join(mediaHost, ".jekyll-obsidian-cache"));
  await writeFile(path.join(mediaHost, ".jekyll-obsidian-cache/github-markdown-browser.json"), JSON.stringify({ version: 1, documents: [] }));
  await writeFile(path.join(mediaHost, "host.yml"), "title: Media fixture with a long site name\nwebsite:\n  source: vault\n  repository: example/media\n  contacts: []\n  features:\n    search: true\n  i18n:\n    enabled: true\n    locales: [en, zh-CN]\n");
  await writeFile(path.join(mediaHost, "vault/_locale.yml"), "name: English\n");
  await copyFile(path.join(projectRoot, "jekyll-obsidian-docs/_translations/zh-CN/_locale.yml"), path.join(mediaHost, "vault/_translations/zh-CN/_locale.yml"));
  const body = "![Figure](https://media.example/figure.svg)\n\n![Interview](https://media.example/interview.wav)\n\n![Demo](https://media.example/demo.mp4)\n\n![Paper](https://papers.example/paper.pdf#page=3&height=560)\n\n![Video](https://youtu.be/NnTvZWp5Q7o)\n";
  for (const [prefix, title] of [["", "Media"], ["_translations/zh-CN/", "媒体"]]) {
    await writeFile(path.join(mediaHost, `vault/${prefix}index.md`), `---\npublish: true\n---\n# ${title}\n` + body);
  }
  await buildFixtureSites(mediaHost, "media", path.join(mediaHost, "host.yml"));
} finally {
  await rm(mediaHost, { force: true, recursive: true });
}

const archiveHost = await mkdtemp(path.join(tmpdir(), "jekyll-obsidian-archive-"));
try {
  await mkdir(path.join(archiveHost, "vault/items"), { recursive: true });
  await mkdir(path.join(archiveHost, "vault/_translations/zh-CN"), { recursive: true });
  await mkdir(path.join(archiveHost, ".jekyll-obsidian-cache"));
  await writeFile(path.join(archiveHost, ".jekyll-obsidian-cache/github-markdown-browser.json"),
    JSON.stringify({ version: 1, documents: [] }));
  const archiveConfig = { title: "Archive fixture", website: {
    source: "vault", theme: "minimal", repository: "example/archive", contacts: [],
    home: { layout: "archive" },
    blog: { page_size: 2, utc_offset: "+08:00", timeline_granularity: "day", ledger_group_by: "day" },
    features: { favorites: true }, i18n: { enabled: true, locales: ["en", "zh-CN"] }
  } };
  await writeFile(path.join(archiveHost, "host.yml"), JSON.stringify(archiveConfig));
  await writeFile(path.join(archiveHost, "vault/_locale.yml"), "name: English\n");
  await copyFile(path.join(projectRoot, "jekyll-obsidian-docs/_translations/zh-CN/_locale.yml"), path.join(archiveHost, "vault/_translations/zh-CN/_locale.yml"));
  await writeFile(path.join(archiveHost, "vault/index.md"), "---\npublish: true\n---\n# Archive\n");
  for (const [id, introduction] of [["plain", ""], ["plain-intro", "An authored introduction."]]) {
    await mkdir(path.join(archiveHost, `vault/${id}`), { recursive: true });
    await writeFile(path.join(archiveHost, `vault/${id}/index.md`),
      `---\npublish: true\ncontent_type: page\ntitle: Collection${introduction ? " with introduction" : ""}\ntab:\n  id: ${id}\n---\n# **Collect**ion${introduction ? " with introduction" : ""}\n\n${introduction}\n`);
    await writeFile(path.join(archiveHost, `vault/${id}/member.md`),
      "---\npublish: true\ncontent_type: page\n---\n# A deliberately long collection title that must wrap before the copy actions\n");
  }
  for (const [id, title, label, source] of [["news", "News", "新闻", "hn"], ["tools", "Tools", "工具", "dsh"]]) {
    await mkdir(path.join(archiveHost, `vault/${id}`), { recursive: true });
    await mkdir(path.join(archiveHost, `vault/_translations/zh-CN/${id}`), { recursive: true });
    await writeFile(path.join(archiveHost, `vault/${id}/index.md`),
      `---\npublish: true\ncontent_type: page\ntab:\n  id: ${id}\n  layout: archive\n  topics: [source/${source}]\n---\n# ${title}\n`);
    await writeFile(path.join(archiveHost, `vault/_translations/zh-CN/${id}/index.md`),
      `---\npublish: true\ntab:\n  label: ${label}\n---\n# ${label}\n`);
  }
  for (const [id, title, date, source, topic] of [
    ["a", "Newest", "2026-10-10", "hn", "agents"],
    ["b", "Middle", "2026-10-09", "dsh", "tools"],
    ["c", "Oldest", "2025-12-31", "hn", "agents"]
  ]) {
    await writeFile(path.join(archiveHost, `vault/items/${id}.md`),
      `---\npublish: true\ncontent_type: post\ntitle: ${title}\ndescription: Description of ${title}\nsource_url: https://example.com/${id}\ndate: ${date}\ntags: [source/${source}, topics/${topic}]\n---\nFirst paragraph of ${title}.\n\nSecond paragraph with a [link](https://example.com/${id}).\n`);
  }
  build(archiveHost, "minimal", "minimal-archive", path.join(archiveHost, "host.yml"));
  const destination = path.join(workspaceRoot, ".jekyll-obsidian-cache/site-browser-minimal-archive");
  await rm(destination, { force: true, recursive: true });
  await cp(path.join(archiveHost, ".jekyll-obsidian-cache/site-browser-minimal-archive"), destination, { recursive: true });
  // A separate collection crosses the page-size boundary without changing the
  // compact fixture used for pagination and reading assertions.
  await mkdir(path.join(archiveHost, "vault/_translations/zh-CN/items"), { recursive: true });
  for (let i = 0; i < 57; i++) {
    const id = `bulk-${String(i).padStart(2, "0")}`;
    const metadata = `---\npublish: true\ncontent_type: post\ntitle: Export ${id}\ndescription: Short description\ndate: 2026-10-09T${String(i % 16).padStart(2, "0")}:00:00Z\nsource_url: https://example.com/${id}\ntags: [source/hn, topics/agents, topics/topic-${i % 20}]\n---\n`;
    const body = `## Article\n\nComplete body of ${id}.\n\n- A list item\n\n> Source quote\n\n\`\`\`md\n# Code heading\n---\n\`\`\`\n\n## HN discussion\n\nDiscussion of ${id}.\n\n[Comments](https://news.ycombinator.com/item?id=123)\n\n![Image](https://example.com/image.png)\n`;
    await writeFile(path.join(archiveHost, `vault/items/${id}.md`), metadata + body);
    await writeFile(path.join(archiveHost, `vault/_translations/zh-CN/items/${id}.md`), metadata + `中文完整正文 ${id}。\n\n` + body);
  }
  build(archiveHost, "minimal", "minimal-export", path.join(archiveHost, "host.yml"));
  const exportDestination = path.join(workspaceRoot, ".jekyll-obsidian-cache/site-browser-minimal-export");
  await rm(exportDestination, { force: true, recursive: true });
  await cp(path.join(archiveHost, ".jekyll-obsidian-cache/site-browser-minimal-export"), exportDestination, { recursive: true });
} finally {
  await rm(archiveHost, { force: true, recursive: true });
}

// Independent of the pagination/export vault and its bulk item count.
const governanceHost = await mkdtemp(path.join(tmpdir(), "jekyll-obsidian-governance-"));
try {
  const fixture = JSON.parse(await readFile(new URL("./fixtures/archive-governance.json", import.meta.url), "utf8"));
  await mkdir(path.join(governanceHost, "vault/items"), { recursive: true });
  await mkdir(path.join(governanceHost, "vault/_translations/zh-CN"), { recursive: true });
  await mkdir(path.join(governanceHost, ".jekyll-obsidian-cache"));
  await writeFile(path.join(governanceHost, ".jekyll-obsidian-cache/github-markdown-browser.json"), JSON.stringify({ version: 1, documents: [] }));
  const configFile = path.join(governanceHost, "host.yml");
  await writeFile(configFile, JSON.stringify({ title: "Governance fixture", website: {
    source: "vault", repository: "example/governance", contacts: [],
    home: { layout: "archive", hide_tab_sources: true },
    blog: { page_size: fixture.pageSize, utc_offset: "+08:00", timeline_granularity: "day", ledger_group_by: "day" },
    features: { favorites: true }, i18n: { enabled: true, locales: ["en", "zh-CN"] }
  } }));
  await writeFile(path.join(governanceHost, "vault/_locale.yml"), "name: English\n");
  await copyFile(path.join(projectRoot, "jekyll-obsidian-docs/_translations/zh-CN/_locale.yml"), path.join(governanceHost, "vault/_translations/zh-CN/_locale.yml"));
  await writeFile(path.join(governanceHost, "vault/index.md"), "---\npublish: true\n---\n# Archive\n");
  for (const prefix of ["", "_translations/zh-CN/"]) {
    const localeFile = path.join(governanceHost, `vault/${prefix}_locale.yml`);
    // Different spellings deliberately exercise cross-locale alias canonicalization.
    await writeFile(localeFile, (await readFile(localeFile, "utf8")) +
      `\ntag_aliases: {topics/old-agents: topics/agents}\nhidden_tags: [topics/${prefix ? "agents" : "old-agents"}, source/regular]\n`);
  }
  for (const [id, source] of [["news", "hn"], ["tools", "dsh"], ["arxiv", "arxiv"]]) {
    await mkdir(path.join(governanceHost, `vault/${id}`));
    await writeFile(path.join(governanceHost, `vault/${id}/index.md`), `---\npublish: true\ntab:\n  id: ${id}\n  layout: archive\n  topics: [source/${source}]\n---\n# ${id}\n`);
  }
  for (const { id, source, topic, date } of fixture.posts) {
    await writeFile(path.join(governanceHost, `vault/items/${id}.md`), `---\npublish: true\ncontent_type: post\ntitle: ${id}\ndate: ${date}\ntags: [source/${source}, topics/${topic}]\n---\nArticle body ${id}.\n`);
  }
  build(governanceHost, "minimal", "minimal-governance", configFile);
  const governanceDestination = path.join(workspaceRoot, ".jekyll-obsidian-cache/site-browser-minimal-governance");
  await rm(governanceDestination, { force: true, recursive: true });
  await cp(path.join(governanceHost, ".jekyll-obsidian-cache/site-browser-minimal-governance"), governanceDestination, { recursive: true });
} finally {
  await rm(governanceHost, { force: true, recursive: true });
}
