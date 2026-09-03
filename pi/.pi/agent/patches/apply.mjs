#!/usr/bin/env node
// Re-applies local patches to Pi's npm-installed packages.
//
// Patch files live next to this script and are named
//   <package name with "/" replaced by "+">+<version>.patch
// e.g. "@czottmann+pi-automode+1.15.0.patch". Each is a unified diff rooted at
// the installed package directory (a/... b/... paths).
//
// Invoked from the ~/.pi/agent/npm postinstall hook (after every `pi install`
// or `pi update`) and from the automode-patch Pi extension at startup, so the
// patches survive reinstalls and freshly stowed hosts without manual steps.

import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const DEFAULT_PATCHES_DIR = dirname(fileURLToPath(import.meta.url));
export const DEFAULT_NPM_ROOT = join(homedir(), ".pi", "agent", "npm");

export function parsePatchName(file) {
  const match = /^(.+)\+(\d+\.\d+\.\d+[^+]*)\.patch$/.exec(file);
  if (!match) return undefined;
  return { name: match[1].replace(/\+/g, "/"), version: match[2] };
}

function gitApply(pkgDir, patchPath, extraArgs) {
  execFileSync("git", ["apply", "-p1", ...extraArgs, patchPath], {
    cwd: pkgDir,
    stdio: ["ignore", "ignore", "pipe"],
    // Treat the package directory as plain files even if $HOME is a git repo.
    env: { ...process.env, GIT_CEILING_DIRECTORIES: pkgDir, GIT_DIR: join(pkgDir, ".nonexistent-git") },
  });
}

function tryGitApply(pkgDir, patchPath, extraArgs) {
  try {
    gitApply(pkgDir, patchPath, extraArgs);
    return undefined;
  } catch (error) {
    return String(error.stderr ?? error.message).trim();
  }
}

export function applyPatches(options = {}) {
  const patchesDir = options.patchesDir ?? DEFAULT_PATCHES_DIR;
  const npmRoot = options.npmRoot ?? DEFAULT_NPM_ROOT;
  const results = [];
  const files = existsSync(patchesDir)
    ? readdirSync(patchesDir).filter((file) => file.endsWith(".patch")).sort()
    : [];

  for (const file of files) {
    const parsed = parsePatchName(file);
    if (!parsed) {
      results.push({ file, status: "failed", detail: "unrecognised patch file name" });
      continue;
    }
    const { name, version } = parsed;
    const pkgDir = join(npmRoot, "node_modules", ...name.split("/"));
    const packageJsonPath = join(pkgDir, "package.json");
    const base = { file, name, version };

    if (!existsSync(packageJsonPath)) {
      results.push({ ...base, status: "missing-package", detail: `${name} is not installed under ${npmRoot}` });
      continue;
    }
    let installedVersion;
    try {
      installedVersion = JSON.parse(readFileSync(packageJsonPath, "utf8")).version;
    } catch (error) {
      results.push({ ...base, status: "failed", detail: `cannot read ${packageJsonPath}: ${error.message}` });
      continue;
    }
    if (installedVersion !== version) {
      results.push({
        ...base,
        status: "version-mismatch",
        detail: `${name}@${installedVersion} is installed but the patch targets ${version}; the fix is NOT applied`,
      });
      continue;
    }

    const patchPath = join(patchesDir, file);
    if (tryGitApply(pkgDir, patchPath, ["--check", "--reverse"]) === undefined) {
      results.push({ ...base, status: "already-applied" });
      continue;
    }
    const checkError = tryGitApply(pkgDir, patchPath, ["--check"]);
    if (checkError !== undefined) {
      results.push({ ...base, status: "failed", detail: `patch does not apply cleanly: ${checkError}` });
      continue;
    }
    const applyError = tryGitApply(pkgDir, patchPath, []);
    results.push(
      applyError === undefined
        ? { ...base, status: "applied" }
        : { ...base, status: "failed", detail: applyError },
    );
  }
  return results;
}

export function formatResult(result) {
  const target = result.name ? `${result.name}@${result.version}` : result.file;
  return result.detail ? `${target}: ${result.status} (${result.detail})` : `${target}: ${result.status}`;
}

function safeRealpath(path) {
  try {
    return realpathSync(path);
  } catch {
    return path;
  }
}

const invokedDirectly = process.argv[1] && safeRealpath(fileURLToPath(import.meta.url)) === safeRealpath(process.argv[1]);
if (invokedDirectly) {
  const npmRoot = process.env.PI_PATCH_NPM_ROOT || undefined;
  const results = applyPatches({ npmRoot });
  for (const result of results) {
    const line = `[pi-patches] ${formatResult(result)}`;
    if (result.status === "applied" || result.status === "already-applied") {
      console.log(line);
    } else {
      console.error(line);
    }
  }
  // Never fail the surrounding npm install; problems are surfaced in Pi at startup.
  process.exit(0);
}
