import { copyFile, cp, mkdir, mkdtemp, rename, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const buildEnvironment = {
  ...process.env,
  GITHUB_REPOSITORY: "example/jekyll-obsidian",
  JEKYLL_ENV: "production",
};

function build(script, arguments_) {
  const result = spawnSync("sh", [script, ...arguments_], {
    cwd: projectRoot,
    env: buildEnvironment,
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`browser fixture build exited with ${result.status ?? result.signal}`);
  }
}

for (const theme of ["minimal", "docs"]) {
  build(path.join(projectRoot, "bin/build"), [
    "--example",
    "--theme", theme,
    "--url", "http://127.0.0.1:4173",
    "--baseurl", `/__site__/${theme}`,
    "--destination", `_site-browser-${theme}`,
    "--skip-assets",
  ]);
}

const fixtureHost = await mkdtemp(path.join(tmpdir(), "jekyll-obsidian-browser-"));
let stagedDestination;
try {
  const fixtureWebsite = path.join(fixtureHost, "website");
  const excludedEntries = new Set([
    ".jekyll-cache",
    ".jekyll-obsidian-cache",
    "node_modules",
    "playwright-report",
    "test-results",
    "vendor",
  ]);
  await cp(projectRoot, fixtureWebsite, {
    recursive: true,
    filter(source) {
      const relative = path.relative(projectRoot, source);
      if (!relative) return true;
      const topLevel = relative.split(path.sep, 1)[0];
      return !excludedEntries.has(topLevel) && !/^_site(?:-|$)/.test(topLevel);
    },
  });
  await mkdir(path.join(fixtureHost, ".github"));
  await copyFile(
    path.join(projectRoot, "tests/browser/fixtures/i18n-host.yml"),
    path.join(fixtureHost, ".github/jekyll-obsidian.yml"),
  );
  await symlink(path.join(projectRoot, "vendor"), path.join(fixtureWebsite, "vendor"), "dir");
  await mkdir(path.join(fixtureWebsite, ".jekyll-obsidian-cache"));
  await cp(
    path.join(projectRoot, ".jekyll-obsidian-cache/assets"),
    path.join(fixtureWebsite, ".jekyll-obsidian-cache/assets"),
    { recursive: true },
  );
  build(path.join(fixtureWebsite, "bin/build"), [
    "--url", "http://127.0.0.1:4173",
    "--baseurl", "/__site__/docs-i18n",
    "--destination", "_site-browser-docs-i18n",
    "--skip-assets",
  ]);
  const destination = path.join(projectRoot, "_site-browser-docs-i18n");
  stagedDestination = path.join(
    projectRoot,
    ".jekyll-obsidian-cache",
    `${path.basename(fixtureHost)}.site`,
  );
  await cp(path.join(fixtureWebsite, "_site-browser-docs-i18n"), stagedDestination, {
    recursive: true,
  });
  await rm(destination, { force: true, recursive: true });
  await rename(stagedDestination, destination);
} finally {
  if (stagedDestination) {
    await rm(stagedDestination, { force: true, recursive: true });
  }
  await rm(fixtureHost, { force: true, recursive: true });
}
