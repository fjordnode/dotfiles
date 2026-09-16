# Codex Auth for Pi

Load with `/reload`, then:

- `/codex-auth` — hand the terminal to the installed `codex-auth switch` picker, then import the selected account into Pi.
- `/codex-auth switch work` — pass an email/alias query to the same picker.
- `/codex-auth sync` — import the currently selected Codex account without opening the picker. Also works via RPC.

Only run while Pi is idle. The selected model and conversation stay unchanged. The next `openai-codex` request reads the updated account; other providers are not changed. Credentials are shared across Pi processes using the same agent directory, not scoped to this conversation.

The picker requires Pi's terminal UI and `codex-auth` on PATH. Use a terminal for `codex-auth login`, adding/removing accounts, and configuration. If the account stays unchanged (including quitting the picker), Pi asks before syncing it.

Do not load a second account manager for `openai-codex` at the same time. In
particular, `pi-accounts` applies its selected OAuth account through Pi's runtime
API-key override. That makes `/logout` appear to leave an API key configured and
causes a later `/login` credential to be shadowed until the account manager is
switched back to its default Pi login.

## Storage and security

Reads `$CODEX_HOME/auth.json`, falling back to `~/.codex/auth.json`. Imports only ChatGPT OAuth access/refresh tokens, account ID, and the access token's actual expiry. Rejects API-key logins and mismatched token/account IDs. Pi can refresh expired tokens using its normal OAuth flow.

Uses Pi's own locked auth store to merge `openai-codex` into the active agent directory's `auth.json`. No tokens are logged or put into conversation messages. CLI picker output goes directly to the terminal. No automatic synchronization or background watcher is installed. Switching with the standalone CLI requires `/codex-auth sync` afterward. Other running Codex clients may need restarting.

Pi and Codex can refresh their copied credentials independently. If a copied refresh token becomes invalid, log in again with Codex and sync again. This extension does not write Pi-refreshed tokens back into Codex account snapshots.

## Compatibility and tests

Tested with Pi 0.85.0 and codex-auth 0.2.4. Pi 0.85 removed the public `AuthStorage` export; the extension resolves `dist/core/auth-storage.js` through the active installation's `getPackageDir()`. This internal dependency may need updating after a Pi upgrade. No installed Pi files are patched.

Run with Pi's bundled Node 22:

```sh
/home/hugo/.local/share/pi-node/current/bin/node \
  ~/.pi/agent/extensions/codex-auth/test.mjs \
  /home/hugo/.local/share/pi-node/current/lib/node_modules/@earendil-works/pi-coding-agent
```

Tests use fake tokens and temporary files, checking conversion, invalid input, expired tokens, preservation of other providers, 0600 file permissions, live runtime credential changes, and command guards. A bundled Pi RPC smoke test also verified command discovery and sync using isolated fake credentials. The real interactive picker must be checked manually in Pi's TUI; no live account switch was performed during installation.
