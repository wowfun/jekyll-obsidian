import { writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import * as esbuild from "esbuild";
import { stageGeneratedAssets } from "./cache-boundary.mjs";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outputDirectory = path.join(projectRoot, ".jekyll-obsidian-cache", "assets");
const staged = await stageGeneratedAssets(projectRoot, outputDirectory);

try {

const result = await esbuild.build({
  absWorkingDir: projectRoot,
  entryPoints: {
    minimal: "src/frontend/entries/minimal.ts",
    docs: "src/frontend/entries/docs.ts",
    "color-scheme-bootstrap": "src/frontend/color-scheme-bootstrap.ts",
    "docs-navigation": "src/frontend/docs-navigation.ts",
    search: "src/frontend/search.ts",
    "search-worker": "src/frontend/search-worker.ts",
    graph: "src/frontend/graph.ts",
    previews: "src/frontend/preview.ts",
    math: "src/frontend/math.ts",
    mermaid: "src/frontend/mermaid.ts"
  },
  outdir: staged.stagingDirectory,
  bundle: true,
  splitting: true,
  format: "esm",
  platform: "browser",
  target: ["es2022"],
  entryNames: "[name]-[hash]",
  chunkNames: "chunks/[name]-[hash]",
  assetNames: "media/[name]-[hash]",
  loader: {
    ".woff": "file",
    ".woff2": "file"
  },
  metafile: true,
  sourcemap: false,
  minify: true,
  legalComments: "none",
  logLevel: "info"
});

const outputs = Object.entries(result.metafile.outputs)
  .map(([outputPath, metadata]) => ({
    outputPath: path.resolve(projectRoot, outputPath),
    metadata
  }))
  .sort((left, right) => left.outputPath.localeCompare(right.outputPath));

const files = outputs
  .map(({ outputPath }) => path.relative(staged.stagingDirectory, outputPath).split(path.sep).join("/"))
  .filter((outputPath) => outputPath !== "manifest.json")
  .sort();

const outputByPath = new Map(outputs.map((output) => [output.outputPath, output]));

function outputForEntryPoint(entryPoint) {
  const output = outputs.find(({ metadata }) => metadata.entryPoint === entryPoint);
  if (!output) throw new Error(`esbuild did not produce entry point ${entryPoint}`);
  return output;
}

function assetClosure(initialOutputs, { includeDynamicImports }) {
  const pending = initialOutputs.map((output) => output.outputPath);
  const seen = new Set();
  while (pending.length > 0) {
    const outputPath = pending.pop();
    if (!outputPath || seen.has(outputPath)) continue;
    const output = outputByPath.get(outputPath);
    if (!output) throw new Error(`esbuild referenced an unknown output: ${outputPath}`);
    seen.add(outputPath);

    if (output.metadata.cssBundle) {
      pending.push(path.resolve(projectRoot, output.metadata.cssBundle));
    }
    for (const imported of output.metadata.imports) {
      if (imported.external || (!includeDynamicImports && imported.kind === "dynamic-import")) continue;
      pending.push(path.resolve(projectRoot, imported.path));
    }
  }
  return [...seen]
    .map((outputPath) => path.relative(staged.stagingDirectory, outputPath).split(path.sep).join("/"))
    .sort();
}

const themeSources = {
  minimal: ["src/frontend/entries/minimal.ts", "src/frontend/docs-navigation.ts"],
  docs: ["src/frontend/entries/docs.ts", "src/frontend/docs-navigation.ts"]
};
const colorSchemeBootstrap = outputForEntryPoint("src/frontend/color-scheme-bootstrap.ts");
const colorSchemeBootstrapPath = path.relative(
  staged.stagingDirectory,
  colorSchemeBootstrap.outputPath
).split(path.sep).join("/");
const featureSources = {
  search: "src/frontend/search.ts",
  graph: "src/frontend/graph.ts",
  previews: "src/frontend/preview.ts",
  math: "src/frontend/math.ts",
  mermaid: "src/frontend/mermaid.ts"
};

const entries = Object.fromEntries(
  Object.entries(themeSources).map(([theme, sources]) => {
    const [entry, ...ownedEntries] = sources.map(outputForEntryPoint);
    const css = entry.metadata.cssBundle
      ? path.relative(staged.stagingDirectory, path.resolve(projectRoot, entry.metadata.cssBundle)).split(path.sep).join("/")
      : undefined;
    return [
      theme,
      {
        js: path.relative(staged.stagingDirectory, entry.outputPath).split(path.sep).join("/"),
        color_scheme: colorSchemeBootstrapPath,
        ...(css ? { css } : {}),
        files: assetClosure([entry, ...ownedEntries, colorSchemeBootstrap], { includeDynamicImports: false })
      }
    ];
  })
);

const features = Object.fromEntries(
  Object.entries(featureSources).map(([feature, source]) => {
    const entry = outputForEntryPoint(source);
    if (feature === "search") {
      const worker = outputForEntryPoint("src/frontend/search-worker.ts");
      return [feature, {
        files: assetClosure([entry, worker], { includeDynamicImports: true }),
        worker: path.relative(staged.stagingDirectory, worker.outputPath).split(path.sep).join("/")
      }];
    }
    return [feature, { files: assetClosure([entry], { includeDynamicImports: true }) }];
  })
);

const manifest = {
  schema_version: 1,
  entries,
  features,
  files
};

await writeFile(
  path.join(staged.stagingDirectory, "manifest.json"),
  `${JSON.stringify(manifest, null, 2)}\n`,
  "utf8"
);
await staged.commit();
} catch (error) {
  await staged.discard();
  throw error;
}
