import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { getPackageDir, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Pi 0.85 no longer exports AuthStorage at the package root. Resolve it from
// the active installation rather than hardcoding a Node or Pi version path.
async function openAuthStorage() {
  const module = await import(pathToFileURL(join(getPackageDir(), "dist/core/auth-storage.js")).href);
  return module.AuthStorage.create();
}

// Never include raw JSON, tokens, or parser errors in UI/session output.
export function convertCredentials(raw: string) {
  try {
    const data = JSON.parse(raw);
    const tokens = data.tokens;
    if (!tokens || (data.auth_mode && data.auth_mode !== "chatgpt")) throw new Error();
    for (const key of ["access_token", "refresh_token", "account_id"]) {
      if (typeof tokens[key] !== "string" || !tokens[key].trim()) throw new Error();
    }
    const claims = JSON.parse(Buffer.from(tokens.access_token.split(".")[1], "base64url").toString("utf8"));
    const accountId = claims["https://api.openai.com/auth"]?.chatgpt_account_id;
    if (accountId !== tokens.account_id || typeof claims.exp !== "number" || !Number.isFinite(claims.exp) || claims.exp <= 0) throw new Error();
    return {
      type: "oauth" as const,
      access: tokens.access_token,
      refresh: tokens.refresh_token,
      accountId: tokens.account_id as string,
      // Let Pi refresh expired credentials normally; do not invent a new lifetime.
      expires: claims.exp * 1000,
    };
  } catch {
    throw new Error("Codex auth is not a valid ChatGPT OAuth login. Run codex-auth login in a terminal first.");
  }
}

export async function syncCredentials(raw: string, storage: { modify: (provider: string, update: () => ReturnType<typeof convertCredentials>) => Promise<unknown> }) {
  const credential = convertCredentials(raw);
  await storage.modify("openai-codex", () => credential);
}

async function readCodexAuth() {
  try {
    return await readFile(join(process.env.CODEX_HOME?.trim() || join(homedir(), ".codex"), "auth.json"), "utf8");
  } catch {
    throw new Error("Cannot read Codex auth.json. Check CODEX_HOME and log in with codex-auth first.");
  }
}

export default function (pi: ExtensionAPI) {
  let busy = false;
  pi.registerCommand("codex-auth", {
    description: "Switch Codex accounts and sync Pi: /codex-auth [switch [query] | sync]",
    handler: async (args, ctx) => {
      if (busy || !ctx.isIdle()) {
        ctx.ui.notify("Wait until Pi is idle before switching accounts.", "warning");
        return;
      }
      const input = args.trim();
      const syncOnly = input === "sync";
      if (input && !syncOnly && input !== "switch" && !input.startsWith("switch ")) {
        ctx.ui.notify("Usage: /codex-auth [switch [email or alias] | sync]", "info");
        return;
      }
      if (!syncOnly && (ctx.mode !== "tui" || !process.stdin.isTTY || !process.stdout.isTTY)) {
        ctx.ui.notify("The picker requires Pi's terminal UI. Run codex-auth switch in a terminal, then /codex-auth sync here.", "warning");
        return;
      }
      busy = true;
      try {
        let raw: string;
        if (syncOnly) {
          raw = await readCodexAuth();
        } else {
          const before = await readCodexAuth().catch(() => undefined);
          const query = input.startsWith("switch ") ? input.slice(7).trim() : "";
          if (query.startsWith("-")) {
            ctx.ui.notify("Use an email or alias, not command-line flags.", "warning");
            return;
          }
          // Same terminal handoff as Pi's interactive-shell example. No shell interpolation.
          const code = await ctx.ui.custom<number | null>((tui, _theme, _kb, done) => {
            let status: number | null = null;
            tui.stop();
            try {
              process.stdout.write("\x1b[2J\x1b[H");
              const result = spawnSync("codex-auth", ["switch", ...(query ? [query] : [])], {
                stdio: "inherit", cwd: ctx.cwd, env: process.env,
              });
              status = result.error ? null : result.status;
            } finally {
              tui.start();
              tui.requestRender(true);
            }
            done(status);
            return { render: () => [], invalidate() {} };
          });
          if (code !== 0) {
            ctx.ui.notify("codex-auth did not complete. Pi credentials were not changed. Check that codex-auth is on PATH.", "warning");
            return;
          }
          raw = await readCodexAuth();
          // codex-auth can exit successfully on q. Never silently import on cancellation.
          let unchanged = raw === before;
          if (before) {
            try { unchanged ||= convertCredentials(before).accountId === convertCredentials(raw).accountId; } catch { /* Validate selected credentials below. */ }
          }
          if (unchanged && !await ctx.ui.confirm("Codex account unchanged", "Sync the current Codex account into Pi anyway?")) return;
        }
        const credential = convertCredentials(raw);
        try {
          // Pi's own store locks and merges with other providers. Its readers detect file changes.
          const storage = await openAuthStorage();
          await storage.modify("openai-codex", () => credential);
        } catch {
          ctx.ui.notify("Could not save Pi credentials. Codex may have switched; retry /codex-auth sync.", "error");
          return;
        }
        ctx.ui.notify("Pi's OpenAI Codex account is synced. The next Codex request will use it; the selected model is unchanged.", "info");
      } catch {
        ctx.ui.notify("Could not import a valid Codex ChatGPT login. Check CODEX_HOME and run codex-auth login in a terminal, then retry /codex-auth sync.", "error");
      } finally {
        busy = false;
      }
    },
  });
}
