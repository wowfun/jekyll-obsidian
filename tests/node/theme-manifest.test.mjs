import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "../..");
const assets = path.join(root, ".jekyll-obsidian-cache", "assets");

test("publishes independent theme and feature asset closures", async () => {
  const manifest = JSON.parse(
    await readFile(path.join(assets, "manifest.json"), "utf8")
  );

  assert.equal(manifest.schema_version, 1);
  assert.deepEqual(Object.keys(manifest.entries).sort(), [
    "blog",
    "digital-garden",
    "docs"
  ]);
  assert.deepEqual(Object.keys(manifest.features).sort(), [
    "graph",
    "math",
    "mermaid",
    "preview",
    "search"
  ]);

  for (const [theme, entry] of Object.entries(manifest.entries)) {
    assert.match(entry.js, new RegExp(`^${theme}-[A-Z0-9]+\\.js$`));
    assert.match(entry.css, new RegExp(`^${theme}-[A-Z0-9]+\\.css$`));
    assert.ok(entry.files.includes(entry.js), `${theme} closure includes its script`);
    assert.ok(entry.files.includes(entry.css), `${theme} closure includes its stylesheet`);
    assert.deepEqual(entry.files, [...entry.files].sort());
  }

  for (const [feature, descriptor] of Object.entries(manifest.features)) {
    assert.ok(descriptor.files.length > 0, `${feature} has a publishable closure`);
    assert.deepEqual(descriptor.files, [...descriptor.files].sort());
  }

  const coreFiles = new Set(
    Object.values(manifest.entries).flatMap((entry) => entry.files)
  );
  for (const feature of ["graph", "math", "mermaid", "search"]) {
    const entryFile = manifest.features[feature].files.find((file) =>
      new RegExp(`^${feature}-[A-Z0-9]+\\.js$`).test(file)
    );
    assert.ok(entryFile, `${feature} exposes its independently loadable script`);
    assert.ok(!coreFiles.has(entryFile), `${feature} stays out of every theme core`);
  }
});
