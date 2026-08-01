import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { resetGeneratedCache } from "../../scripts/cache-boundary.mjs";

test("refuses a symlinked cache parent without touching its target", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "garden-cache-root-"));
  const outside = await mkdtemp(path.join(os.tmpdir(), "garden-cache-outside-"));
  try {
    await writeFile(path.join(outside, "canary.txt"), "preserve me");
    await symlink(outside, path.join(root, ".jekyll-obsidian-cache"));

    await assert.rejects(
      resetGeneratedCache(root, path.join(root, ".jekyll-obsidian-cache", "assets")),
      /symbolic link/
    );
    assert.equal(await readFile(path.join(outside, "canary.txt"), "utf8"), "preserve me");
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});
test("refuses symlinks inside an existing generated tree", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "garden-cache-root-"));
  const outside = await mkdtemp(path.join(os.tmpdir(), "garden-cache-outside-"));
  try {
    const output = path.join(root, ".jekyll-obsidian-cache", "assets");
    await mkdir(output, { recursive: true });
    await writeFile(path.join(outside, "canary.txt"), "preserve me");
    await symlink(outside, path.join(output, "redirect"));

    await assert.rejects(resetGeneratedCache(root, output), /symbolic link/);
    assert.equal(await readFile(path.join(outside, "canary.txt"), "utf8"), "preserve me");
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});
