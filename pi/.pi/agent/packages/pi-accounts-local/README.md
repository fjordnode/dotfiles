# pi-accounts — local identity and quota display

Based on `@narumitw/pi-accounts` 0.51.0 (MIT). The upstream `src/` is retained;
local changes are confined to `src/account-menu.ts` and `src/codex-usage.ts`.
Pi loads source directly through Jiti. This local package replaces, rather than
co-loads with, the npm package. Account storage and session-selection format are
unchanged (`~/.pi/agent/pi-accounts.json`). No account data belongs in this folder.

## Install on another host

After pulling dotfiles, link the Pi config and install this package's dependencies:

```sh
cd ~/dotfiles
stow -t ~ pi
cd ~/.pi/agent/packages/pi-accounts-local
npm ci --ignore-scripts
pi install ./
```

Use a Node version supported by Pi (the bundled Node is suitable). If Stow reports
conflicts, preserve the existing local files and reconcile them; do not use
`--adopt` on account or authentication files. `pi install ./` registers the package
even when the host has its own regular `settings.json`. Restart Pi or `/reload`,
then use `/accounts` (plural). Log in separately on each host.

Only source, manifests, license, documentation, and fake-credential tests belong
in Git. Never copy `auth.json`, `pi-accounts.json`, sessions, `.env` files, or
`node_modules` into the repository. Account storage remains outside this package.

## UI

- `/accounts` shows the named active account, or `default → <matching saved name>`.
  Unmatched default logins show their email or a shortened account identifier.
  Identity is obtained from Pi's effective provider authentication, not Codex CLI.
- OpenAI Codex main-menu status shows remaining quota and absolute reset times
  in the local timezone, with a countdown.
- Switch-account rows show an explicit active marker and remaining limits.
  Highlight a row in the TUI to see its reset details. RPC includes those details
  in the selector title because RPC choices do not transmit item descriptions.
- Other providers retain upstream behavior; only OpenAI Codex has quota data.

## Usage requests

Opening the menu queries `https://chatgpt.com/backend-api/wham/usage` with the
account's access token and ChatGPT account ID, just as codex-auth's API mode does.
Requests have a six-second deadline, disable redirects, and use at most three
concurrent requests. Results are cached for 30 seconds within that menu only;
close and reopen to refresh. No background polling, token output, or disk cache.
The usage endpoint is unofficial and may change or fail.

Inactive accounts are **not** refreshed merely to read quota; rejected/expired
logins show an error and can be selected for Pi's normal refresh, or logged in
again. The effective default login is resolved by Pi's normal authentication
logic, which may refresh it. No credentials are read from or written to Codex CLI.
Missing limits and HTTP/network failures are explicitly unavailable, not 0% or
100%. Reset countdowns that have elapsed tell you to reopen and refresh.

## Validation

```sh
node --experimental-strip-types \
  ~/.pi/agent/packages/pi-accounts-local/test-usage.mjs
python3 ~/.pi/agent/packages/pi-accounts-local/test-menu.py
```

Tests use only fake credentials. Unit checks cover parsing, remaining quota,
reset formatting, errors, concurrency, caching and cancellation. The bundled-Pi
RPC test verifies menu content, default-account matching and real command-based
switching of fake accounts in isolated storage with network requests mocked.
Live OpenAI responses and a manual TUI session are not covered by that test.

## Updating / reverting

This is a maintained local copy, not an npm-file patch. Pi package updates will
not update this fork. Compare future upstream changes before updating its base.
To revert, remove the local package using `pi remove` and reinstall
`npm:@narumitw/pi-accounts`, then `/reload`. Do not load both implementations at
once. The shared account file and session selections remain compatible with the
0.51.0 base.
