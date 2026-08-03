import assert from "node:assert/strict";
import { copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const siteRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

test("distributed integration test accepts a standard generated host", async () => {
  const hostRoot = await mkdtemp(path.join(tmpdir(), "jekyll-obsidian-node-host-"));
  try {
    const copiedSite = path.join(hostRoot, "website");
    const copiedTest = path.join(copiedSite, "tests/node/integration-template.test.mjs");
    const copiedConfigTemplate = path.join(copiedSite, "scripts/templates/host-config.yml");
    const copiedWorkflowTemplate = path.join(copiedSite, "scripts/templates/pages.yml");
    await Promise.all([
      mkdir(path.dirname(copiedTest), { recursive: true }),
      mkdir(path.dirname(copiedConfigTemplate), { recursive: true }),
      mkdir(path.join(hostRoot, ".github/workflows"), { recursive: true }),
    ]);
    await Promise.all([
      copyFile(path.join(siteRoot, "tests/node/integration-template.test.mjs"), copiedTest),
      copyFile(path.join(siteRoot, "scripts/templates/host-config.yml"), copiedConfigTemplate),
      copyFile(path.join(siteRoot, "scripts/templates/pages.yml"), copiedWorkflowTemplate),
    ]);

    const [configTemplate, workflowTemplate] = await Promise.all([
      readFile(copiedConfigTemplate, "utf8"),
      readFile(copiedWorkflowTemplate, "utf8"),
    ]);
    await Promise.all([
      writeFile(
        path.join(hostRoot, ".github/jekyll-obsidian.yml"),
        configTemplate
          .replace("__JEKYLL_WEBSITE_SOURCE__", "docs")
          .replace("__JEKYLL_WEBSITE_THEME__", "docs"),
        "utf8",
      ),
      writeFile(
        path.join(hostRoot, ".github/workflows/pages.yml"),
        workflowTemplate.replaceAll("__JEKYLL_WEBSITE_SOURCE_GLOB__", "docs/**"),
        "utf8",
      ),
    ]);

    const childEnvironment = { ...process.env };
    delete childEnvironment.NODE_TEST_CONTEXT;
    const result = spawnSync(process.execPath, ["--test", copiedTest], {
      encoding: "utf8",
      env: childEnvironment,
    });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  } finally {
    await rm(hostRoot, { force: true, recursive: true });
  }
});
