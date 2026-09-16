// One-time importer for pi-accounts 0.51's v1 store. No secret-bearing errors/output.
// Default is dry-run. Use --apply to merge without selecting an account.
import { createRequire } from 'node:module';
import { createHash, randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import { open, readdir, mkdir, rename, rm, lstat } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(new URL('../packages/pi-accounts-local/package.json', import.meta.url));
const lockfile = require('proper-lockfile');
const record = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const digest = text => createHash('sha256').update(text).digest('hex');
async function readPrivate(path) {
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    if (!(await file.stat()).isFile()) throw new Error();
    return await file.readFile('utf8');
  } finally { await file.close(); }
}
function claims(token) {
  return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
}
export function convert(raw) {
  const data = JSON.parse(raw), t = data.tokens;
  if (!record(t) || (data.auth_mode && data.auth_mode !== 'chatgpt')) throw new Error();
  if (!['access_token', 'refresh_token', 'account_id'].every(k => typeof t[k] === 'string' && t[k].trim())) throw new Error();
  const access = claims(t.access_token);
  if (access['https://api.openai.com/auth']?.chatgpt_account_id !== t.account_id || !Number.isFinite(access.exp) || access.exp <= 0) throw new Error();
  let email = '';
  try { email = claims(t.id_token).email; } catch { /* Optional label only. */ }
  const prefix = typeof email === 'string' ? email.replace(/[^A-Za-z0-9._-]/g, '-').slice(0, 43) : '';
  const name = `${prefix || 'codex'}-${digest(t.account_id).slice(0, 12)}`;
  return { name, credential: { type: 'oauth', access: t.access_token, refresh: t.refresh_token, accountId: t.account_id, expires: access.exp * 1000 } };
}
export function merge(current, incoming) {
  if (!record(current) || current.version !== 1 || !record(current.providers)) throw new Error();
  const providers = { ...current.providers };
  const state = providers['openai-codex'] ?? { accounts: {} };
  if (!record(state) || !record(state.accounts)) throw new Error();
  const accounts = { ...state.accounts };
  let added = 0, skipped = 0;
  for (const { name, credential } of incoming) {
    if (Object.hasOwn(accounts, name) || Object.values(accounts).some(c => c?.accountId === credential.accountId)) { skipped++; continue; }
    accounts[name] = credential;
    added++;
  }
  providers['openai-codex'] = { ...state, accounts };
  return { next: { ...current, providers }, added, skipped };
}
export async function run({ source, target, apply = false }) {
  const files = (await readdir(source)).filter(n => n.endsWith('.auth.json')).sort();
  const incoming = [];
  let invalid = 0;
  for (const file of files) {
    try { incoming.push(convert(await readPrivate(join(source, file)))); }
    catch { invalid++; }
  }
  // Fail as a batch rather than silently importing a partial set of credentials.
  if (invalid || !incoming.length) throw new Error();
  if (apply) await mkdir(dirname(target), { recursive: true, mode: 0o700 });
  // Use the same lock path/options as pi-accounts, not flock or a separate lock.
  let compromised = false;
  const release = await lockfile.lock(target, { realpath: false, stale: 30000, retries: { retries: 10, minTimeout: 100, maxTimeout: 1000 }, onCompromised() { compromised = true; } });
  let temporary;
  try {
    let raw;
    try { raw = await readPrivate(target); }
    catch (e) { if (e.code !== 'ENOENT') throw e; }
    if (!raw) {
      for (const name of ['pi-codex-accounts.json', 'codex-accounts.json']) {
        try { await lstat(join(dirname(target), name)); throw new Error('Legacy store requires migration'); }
        catch (e) { if (e.code !== 'ENOENT') throw e; }
      }
    }
    const result = merge(raw === undefined ? { version: 1, providers: {} } : JSON.parse(raw), incoming);
    if (apply && result.added) {
      temporary = `${target}.${randomUUID()}.tmp`;
      const file = await open(temporary, 'wx', 0o600);
      try { await file.writeFile(JSON.stringify(result.next, null, 2) + '\n'); await file.sync(); }
      finally { await file.close(); }
      if (compromised) throw new Error();
      await rename(temporary, target);
      const directory = await open(dirname(target), 'r');
      try { await directory.sync(); } finally { await directory.close(); }
    }
    return { mode: apply ? 'applied' : 'dry-run', found: files.length, added: result.added, preservedOrDuplicate: result.skipped };
  } finally {
    if (temporary) await rm(temporary, { force: true });
    await release();
  }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.slice(2).some(a => !['--apply', '--dry-run'].includes(a))) throw new Error();
    const agentDir = process.env.PI_CODING_AGENT_DIR || join(homedir(), '.pi/agent');
    const codexDir = process.env.CODEX_HOME || join(homedir(), '.codex');
    console.log(JSON.stringify(await run({ source: join(codexDir, 'accounts'), target: join(agentDir, 'pi-accounts.json'), apply: process.argv.includes('--apply') })));
  } catch {
    console.error('Import failed; diagnostic details withheld to protect credentials. Check source files, v1 target schema, legacy migration, and permissions. No Codex files are modified.');
    process.exitCode = 1;
  }
}
