import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const siteRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const hostRoot = path.dirname(siteRoot);

function managedValue(config, key) {
  const block = config.match(
    /^  # jekyll-obsidian:managed-start\n(?<body>[\s\S]*?)^  # jekyll-obsidian:managed-end$/m,
  );
  assert.ok(block, "host configuration must contain one managed block");
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = block.groups.body.match(new RegExp(`^  ${escaped}: '(?<value>(?:[^']|'')*)'$`, "m"));
  assert.ok(match, `managed ${key} must use the generated single-quoted form`);
  return match.groups.value.replaceAll("''", "'");
}

function yamlSingleQuoted(value) {
  return value.replaceAll("'", "''");
}

function workflowGlob(value) {
  return `${value.replaceAll(/[*?+\[\]!]/g, "\\$&")}/**`;
}

test("checked-in host integration follows the distributed contract", async () => {
  const [config, configTemplate, workflow, workflowTemplate] = await Promise.all([
    readFile(path.join(hostRoot, ".github/jekyll-obsidian.yml"), "utf8"),
    readFile(path.join(siteRoot, "scripts/templates/host-config.yml"), "utf8"),
    readFile(path.join(hostRoot, ".github/workflows/pages.yml"), "utf8"),
    readFile(path.join(siteRoot, "scripts/templates/pages.yml"), "utf8"),
  ]);

  const source = managedValue(config, "source");
  const theme = managedValue(config, "theme");
  const expectedWorkflow = workflowTemplate.replaceAll(
    "__JEKYLL_WEBSITE_SOURCE_GLOB__",
    yamlSingleQuoted(workflowGlob(source)),
  );

  assert.equal(workflow, expectedWorkflow);
  const restoreExecutables = workflow.indexOf("- name: Restore executable scripts");
  const checkIntegration = workflow.indexOf("- name: Check host integration");
  assert.ok(restoreExecutables >= 0, "workflow must restore shell executable bits after Windows copies");
  assert.ok(restoreExecutables < checkIntegration, "workflow must restore executable bits before invoking scripts");
  assert.match(configTemplate, /^title: My Project Documentation$/m);
  assert.match(configTemplate, /source: '__JEKYLL_WEBSITE_SOURCE__'/);
  assert.match(configTemplate, /theme: '__JEKYLL_WEBSITE_THEME__'/);
  assert.equal(config.charCodeAt(0), "#".charCodeAt(0), "host config must not contain a BOM");
  assert.equal(workflow.charCodeAt(0), "#".charCodeAt(0), "workflow must not contain a BOM");
  assert.ok(!config.includes("\r"));
  assert.ok(!workflow.includes("\r"));
});
