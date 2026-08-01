import { lstat, mkdir, readdir, realpath, rm } from "node:fs/promises";
import path from "node:path";

async function optionalLstat(candidate) {
  try {
    return await lstat(candidate);
  } catch (error) {
    if (error && typeof error === "object" && error.code === "ENOENT") return undefined;
    throw error;
  }
}

async function rejectSymlinkTree(candidate) {
  const stat = await optionalLstat(candidate);
  if (!stat) return;
  if (stat.isSymbolicLink()) {
    throw new Error(`refusing to clean a cache containing a symbolic link: ${candidate}`);
  }
  if (!stat.isDirectory()) return;

  const entries = await readdir(candidate);
  for (const entry of entries.sort()) {
    await rejectSymlinkTree(path.join(candidate, entry));
  }
}

export async function resetGeneratedCache(projectRoot, outputDirectory) {
  const declaredRoot = path.resolve(projectRoot);
  const target = path.resolve(outputDirectory);
  const relative = path.relative(declaredRoot, target);
  if (relative === "" || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
    throw new Error("refusing to clean a cache outside the project root");
  }

  let cursor = declaredRoot;
  for (const component of relative.split(path.sep)) {
    cursor = path.join(cursor, component);
    const stat = await optionalLstat(cursor);
    if (!stat) break;
    if (stat.isSymbolicLink()) {
      throw new Error(`refusing to clean a cache through a symbolic link: ${cursor}`);
    }
  }

  const rootRealPath = await realpath(declaredRoot);
  const targetStat = await optionalLstat(target);
  if (targetStat) {
    const targetRealPath = await realpath(target);
    if (!targetRealPath.startsWith(`${rootRealPath}${path.sep}`)) {
      throw new Error("refusing to clean a cache that resolves outside the project root");
    }
    await rejectSymlinkTree(target);
  }

  await rm(target, { recursive: true, force: true });
  await mkdir(target, { recursive: true });
}
