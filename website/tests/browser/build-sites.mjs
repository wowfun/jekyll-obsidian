import { copyFile, cp, mkdir, mkdtemp, rm } from "node:fs/promises";
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
  const result = spawnSync("bundle", ["exec", "ruby", "-e", code, host, config,
    path.join(projectRoot, ".jekyll-obsidian-cache/assets"), `site-browser-${name}`, theme, `/__site__/${name}`], {
    cwd: projectRoot, env: environment, stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`browser fixture build exited with ${result.status ?? result.signal}`);
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
  for (const theme of ["docs", "minimal"]) {
    const name = `${theme}-i18n`;
    build(fixtureHost, theme, name, path.join(fixtureHost, ".github/jekyll-obsidian.yml"));
    const destination = path.join(workspaceRoot, `.jekyll-obsidian-cache/site-browser-${name}`);
    await rm(destination, { force: true, recursive: true });
    await cp(path.join(fixtureHost, `.jekyll-obsidian-cache/site-browser-${name}`), destination, { recursive: true });
  }
} finally {
  await rm(fixtureHost, { force: true, recursive: true });
}
