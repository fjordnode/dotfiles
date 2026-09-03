// Keeps local patches to npm-installed Pi packages applied.
//
// 1. Pi runs all npm operations through settings.json "npmCommand"; the
//    dotfiles set it to the `pi-npm` wrapper (scripts/.local/bin), which
//    re-runs ../patches/apply.mjs after every `pi install` / `pi update`.
//    This extension checks that wiring is in place and warns when it is not.
// 2. Ensures ~/.pi/agent/npm/package.json has a postinstall hook too, which
//    covers a bare `npm install` run by hand in that directory.
// 3. Applies the patches itself on every Pi start (and /reload), which
//    covers a freshly stowed host and packages reinstalled without the hook.
// 4. Reports the outcome in the UI; anything other than "already-applied"
//    needs attention (a version bump, or a /reload to pick up new code).
//
// Note: bash-confirm.ts imports pi-automode directly, so a patch applied
// during this start only takes effect after /reload.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";
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
const SETTINGS_PATH = join(AGENT_DIR, "settings.json");
const NPM_WRAPPER = "pi-npm";
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

export function checkNpmWrapper(
  settingsPath: string = SETTINGS_PATH,
  pathEnv: string = process.env.PATH ?? "",
): string[] {
  const problems: string[] = [];
  let npmCommand: unknown;
  try {
    npmCommand = (JSON.parse(readFileSync(settingsPath, "utf8")) as Record<string, unknown>).npmCommand;
  } catch (error) {
    return [`cannot read ${settingsPath}: ${(error as Error).message}`];
  }
  if (!Array.isArray(npmCommand) || npmCommand[0] !== NPM_WRAPPER) {
    problems.push(
      `settings.json npmCommand is not ["${NPM_WRAPPER}"]; pi install/update will drop the patches`,
    );
  }
  const onPath = pathEnv
    .split(delimiter)
    .filter(Boolean)
    .some((dir) => existsSync(join(dir, NPM_WRAPPER)));
  if (!onPath) {
    problems.push(`${NPM_WRAPPER} is not on PATH; stow the scripts dotfiles package`);
  }
  return problems;
}

export default function (pi: ExtensionAPI) {
  const problems: string[] = [];
  let applied: string[] = [];

  problems.push(...checkNpmWrapper());

  try {
    ensurePostinstallHook();
  } catch (error) {
    problems.push(`could not set npm postinstall hook: ${(error as Error).message}`);
  }

  if (existsSync(APPLY_SCRIPT)) {
    try {
      const results = applyPatches() as PatchResult[];
      applied = results.filter((r) => r.status === "applied").map(formatResult);
      problems.push(
        ...results
          .filter((r) => r.status !== "applied" && r.status !== "already-applied")
          .map(formatResult),
      );
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
