import { lstat, mkdir, mkdtemp, rename, rm } from "node:fs/promises";
import path from "node:path";

async function optionalLstat(candidate) {
  try {
    return await lstat(candidate);
  } catch (error) {
    if (error && typeof error === "object" && error.code === "ENOENT") return undefined;
    throw error;
  }
}

export async function stageGeneratedAssets(projectRoot, outputDirectory) {
  const declaredRoot = path.resolve(projectRoot);
  const target = path.resolve(outputDirectory);
  const cacheRoot = path.join(declaredRoot, ".jekyll-obsidian-cache");
  if (target !== path.join(cacheRoot, "assets")) {
    throw new Error("generated assets must use the fixed project cache location");
  }

  const cacheStat = await optionalLstat(cacheRoot);
  if (cacheStat?.isSymbolicLink()) {
    throw new Error(`refusing to publish assets through a symbolic link: ${cacheRoot}`);
  }
  if (cacheStat && !cacheStat.isDirectory()) throw new Error("project cache must be a directory");
  await mkdir(cacheRoot, { recursive: true });

  const targetStat = await optionalLstat(target);
  if (targetStat?.isSymbolicLink()) throw new Error("generated asset target must not be a symbolic link");
  if (targetStat && !targetStat.isDirectory()) throw new Error("generated asset target must be a directory");

  const stagingDirectory = await mkdtemp(path.join(cacheRoot, "assets-build-"));
  const backupDirectory = path.join(cacheRoot, `assets-backup-${process.pid}`);

  return {
    stagingDirectory,
    async commit() {
      const backupStat = await optionalLstat(backupDirectory);
      if (backupStat) throw new Error(`stale generated asset backup exists: ${backupDirectory}`);
      let movedPrevious = false;
      try {
        if (targetStat) {
          await rename(target, backupDirectory);
          movedPrevious = true;
        }
        await rename(stagingDirectory, target);
        if (movedPrevious) await rm(backupDirectory, { recursive: true });
      } catch (error) {
        if (movedPrevious && !(await optionalLstat(target)) && (await optionalLstat(backupDirectory))) {
          await rename(backupDirectory, target);
        }
        throw error;
      }
    },
    async discard() {
      await rm(stagingDirectory, { recursive: true, force: true });
    }
  };
}
