import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";

const root = path.resolve(import.meta.dirname, "../..");
const assets = path.join(root, ".jekyll-obsidian-cache", "assets");

async function closureBytes(files) {
  const sizes = await Promise.all(files.map(async (file) => (await stat(path.join(assets, file))).size));
  return sizes.reduce((total, size) => total + size, 0);
}

test("publishes independent theme and feature asset closures", async () => {
  const manifest = JSON.parse(
    await readFile(path.join(assets, "manifest.json"), "utf8")
  );

  assert.equal(manifest.schema_version, 1);
  assert.deepEqual(Object.keys(manifest.entries).sort(), [
    "docs",
    "minimal"
  ]);
  assert.deepEqual(Object.keys(manifest.features).sort(), [
    "graph",
    "math",
    "mermaid",
    "previews",
    "search"
  ]);

  for (const [theme, entry] of Object.entries(manifest.entries)) {
    assert.match(entry.js, new RegExp(`^${theme}-[A-Z0-9]+\\.js$`));
    assert.match(entry.color_scheme, /^color-scheme-bootstrap-[A-Z0-9]+\.js$/);
    assert.match(entry.css, new RegExp(`^${theme}-[A-Z0-9]+\\.css$`));
    assert.ok(entry.files.includes(entry.js), `${theme} closure includes its script`);
    assert.ok(entry.files.includes(entry.color_scheme), `${theme} closure includes its color scheme bootstrap`);
    assert.ok(entry.files.includes(entry.css), `${theme} closure includes its stylesheet`);
    assert.deepEqual(entry.files, [...entry.files].sort());
    assert.ok(await closureBytes(entry.files) < 1_000_000, `${theme} core stays below 1 MB`);
    for (const lazy of ["archive-filters", "favorite-controls"]) {
      assert.ok(entry.files.some((file) => file.startsWith(`${lazy}-`)), `${theme} ships ${lazy}`);
    }
  }

  const bootstrap = manifest.entries.docs.color_scheme;
  const bootstrapSource = await readFile(path.join(assets, bootstrap), "utf8");
  assert.doesNotMatch(bootstrapSource, /\b(?:import|export)\b/, "bootstrap remains a blocking classic script");

  const docsNavigation = manifest.files.find((file) => /(?:^|\/)docs-navigation-[A-Z0-9]+\.js$/.test(file));
  assert.ok(docsNavigation, "docs navigation has a generated chunk");
  assert.ok(manifest.entries.docs.files.includes(docsNavigation), "docs owns its navigation chunk");
  assert.ok(manifest.entries.minimal.files.includes(docsNavigation), "minimal owns its documentation navigation chunk");

  for (const [feature, descriptor] of Object.entries(manifest.features)) {
    assert.ok(descriptor.files.length > 0, `${feature} has a publishable closure`);
    assert.deepEqual(descriptor.files, [...descriptor.files].sort());
  }
  assert.match(manifest.features.search.worker, /^search-worker-[A-Z0-9]+\.js$/);
  assert.ok(manifest.features.search.files.includes(manifest.features.search.worker));
  assert.ok(await closureBytes(manifest.features.search.files) < 50_000, "search stays below 50 KB");
  assert.ok(await closureBytes(manifest.features.graph.files) < 200_000, "graph stays below 200 KB");
  assert.ok(await closureBytes(manifest.features.math.files) < 2_000_000, "math stays below 2 MB");
  // Mermaid 12 includes the lazy ELK engine; this budget covers every optional
  // diagram and layout chunk, not just the scripts fetched for one diagram.
  const mermaidBytes = await closureBytes(manifest.features.mermaid.files);
  assert.ok(mermaidBytes < 6_000_000, `mermaid stays below 6 MB (${mermaidBytes} bytes)`);

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

test("both themes keep their synchronous JavaScript within the initial-load budget", async () => {
  const statistics = JSON.parse(await readFile(path.join(root, ".jekyll-obsidian-cache", "asset-statistics.json"), "utf8"));
  const sha256 = bytes => createHash("sha256").update(bytes).digest("hex");
  const stale = "Asset statistics are stale; run npm run build before test:prepared.";
  assert.ok(statistics.inputs && statistics.themes, stale);
  assert.equal(sha256(await readFile(path.join(assets, "manifest.json"))), statistics.manifest_sha256, stale);
  assert.ok(Object.hasOwn(statistics.inputs, "src/frontend/main.ts"), stale);
  await Promise.all(Object.entries(statistics.inputs).map(async ([file, digest]) => {
    assert.equal(sha256(await readFile(path.resolve(root, file))), digest, `${file}: ${stale}`);
  }));
  assert.deepEqual(Object.keys(statistics.themes).sort(), ["docs", "minimal"]);
  for (const [theme, summary] of Object.entries(statistics.themes)) {
    let bytes = 0, gzipBytes = 0;
    for (const dependency of summary.dependencies) {
      const content = await readFile(path.join(assets, dependency.file));
      assert.equal(sha256(content), dependency.sha256, stale);
      bytes += content.length;
      gzipBytes += gzipSync(content).length;
    }
    assert.equal(summary.bytes, bytes, stale);
    assert.equal(summary.gzip_bytes, gzipBytes, stale);
    assert.ok(summary.bytes <= 45_000, `${theme}: ${summary.bytes} raw bytes`);
    assert.ok(summary.gzip_bytes <= 18_000, `${theme}: ${summary.gzip_bytes} gzip bytes`);
    assert.ok(summary.dependencies.every(({ file }) => !/^(archive-filters|favorite-controls)-/.test(file)));
  }
});
