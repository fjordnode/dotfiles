// Keeps local patches to npm-installed Pi packages applied.
//
// 1. Applies the patches on every Pi start and /reload. This is the mechanism
//    that matters: `pi install` / `pi update` overwrite the package files, and
//    the patched code is only read when extensions load, so re-applying at
//    load time closes the gap.
// 2. Ensures ~/.pi/agent/npm/package.json has a postinstall hook, which covers
//    a bare `npm install` run by hand in that directory.
// 3. Reports version mismatches and failures in the UI. A patch that no longer
//    matches the installed version is skipped, never force-applied.
//
// Deliberately does not set settings.json "npmCommand". A wrapper named there
// must exist on PATH on every host that reads these dotfiles, and Pi dies with
// ENOENT when it does not.
//
// Note: bash-confirm.ts imports pi-automode directly, so a patch applied
// during this start only takes effect after /reload.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { applyPatches, formatResult } from "../patches/apply.mjs";

type PatchResult = {
  file: string;
  name?: string;
  version?: string;
  status: "applied" | "already-applied" | "missing-package" | "version-mismatch" | "failed";
  detail?: string;
};

const AGENT_DIR = join(homedir(), ".pi", "agent");
const NPM_ROOT = join(AGENT_DIR, "npm");
const APPLY_SCRIPT = join(AGENT_DIR, "patches", "apply.mjs");
const POSTINSTALL =
  `[ -f "$HOME/.pi/agent/patches/apply.mjs" ] && node "$HOME/.pi/agent/patches/apply.mjs" || true`;

export function ensurePostinstallHook(npmRoot: string = NPM_ROOT): "unchanged" | "updated" {
  const packageJsonPath = join(npmRoot, "package.json");
  let pkg: Record<string, unknown> = { name: "pi-extensions", private: true };
  if (existsSync(packageJsonPath)) {
    pkg = JSON.parse(readFileSync(packageJsonPath, "utf8")) as Record<string, unknown>;
  } else {
    mkdirSync(npmRoot, { recursive: true });
  }
  const scripts = (pkg.scripts ?? {}) as Record<string, string>;
  if (scripts.postinstall === POSTINSTALL) return "unchanged";
  pkg.scripts = { ...scripts, postinstall: POSTINSTALL };
  writeFileSync(packageJsonPath, `${JSON.stringify(pkg, null, 2)}\n`, "utf8");
  return "updated";
}

// A patch whose package is not installed on this host is not a problem; the
// host simply does not run that package.
export function isProblem(result: PatchResult): boolean {
  return result.status === "version-mismatch" || result.status === "failed";
}

export default function (pi: ExtensionAPI) {
  const problems: string[] = [];
  let applied: string[] = [];

  try {
    ensurePostinstallHook();
  } catch (error) {
    problems.push(`could not set npm postinstall hook: ${(error as Error).message}`);
  }

  if (existsSync(APPLY_SCRIPT)) {
    try {
      const results = applyPatches() as PatchResult[];
      applied = results.filter((r) => r.status === "applied").map(formatResult);
      problems.push(...results.filter(isProblem).map(formatResult));
    } catch (error) {
      problems.push(`patch run failed: ${(error as Error).message}`);
    }
  } else {
    problems.push(`${APPLY_SCRIPT} is missing; stow the pi dotfiles package`);
  }

  pi.on("session_start", (_event, ctx) => {
    if (!ctx.hasUI) return;
    if (applied.length > 0) {
      ctx.ui.notify(
        `Applied package patches, run /reload to load them:\n${applied.join("\n")}`,
        "warning",
      );
    }
    if (problems.length > 0) {
      ctx.ui.notify(`Package patches need attention:\n${problems.join("\n")}`, "error");
    }
  });
}
