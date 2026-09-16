import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

// Pass the active Pi package directory; no live credentials or network are used.
const root = process.argv[2];
if (!root) throw new Error('Usage: node test.mjs /path/to/pi-coding-agent');
const require = createRequire(join(root, 'package.json'));
const { createJiti } = require('jiti');
const jiti = createJiti(import.meta.url, { alias: { '@earendil-works/pi-coding-agent': join(root, 'dist/config.js') } });
const extension = await jiti.import(new URL('./index.ts', import.meta.url).pathname);
const { AuthStorage } = await import(pathToFileURL(join(root, 'dist/core/auth-storage.js')).href);
const { ModelRuntime } = await import(pathToFileURL(join(root, 'dist/core/model-runtime.js')).href);
const makeRaw = (account = 'test-account', exp = Math.floor(Date.now() / 1000) + 3600) => JSON.stringify({
  auth_mode: 'chatgpt', tokens: {
    access_token: `fake.${Buffer.from(JSON.stringify({ exp, 'https://api.openai.com/auth': { chatgpt_account_id: account } })).toString('base64url')}.fake`,
    refresh_token: 'fake-refresh', account_id: account,
  },
});
const raw = makeRaw();
const credential = extension.convertCredentials(raw);
assert.equal(credential.type, 'oauth');
assert.equal(credential.accountId, 'test-account');
assert.equal(extension.convertCredentials(makeRaw('expired', 1)).expires, 1000);
for (const invalid of ['token-secret-not-json', '{}', JSON.stringify({ OPENAI_API_KEY: 'fake-secret' }), raw.replace('chatgpt', 'api'), raw.replace('test-account', 'mismatch')]) {
  assert.throws(() => extension.convertCredentials(invalid), /^Error: Codex auth is not a valid ChatGPT OAuth login/);
}
const dir = await mkdtemp(join(tmpdir(), 'pi-codex-auth-test-'));
try {
  const authPath = join(dir, 'auth.json');
  const storage = AuthStorage.create(authPath);
  await storage.modify('another-provider', () => ({ type: 'api_key', key: 'fake-other-key' }));
  const runtime = await ModelRuntime.create({ authPath, modelsPath: null, modelsStorePath: join(dir, 'models-cache.json'), refreshOnCreate: false });
  await extension.syncCredentials(raw, storage);
  assert.equal((await runtime.getAuth('openai-codex')).auth.apiKey, credential.access);
  const next = makeRaw('second-account');
  await extension.syncCredentials(next, storage);
  assert.equal((await runtime.getAuth('openai-codex')).auth.apiKey, extension.convertCredentials(next).access);
  assert.equal((await storage.read('another-provider')).key, 'fake-other-key');
  const before = await readFile(authPath, 'utf8');
  await assert.rejects(extension.syncCredentials('{}', storage));
  assert.equal(await readFile(authPath, 'utf8'), before);
  assert.equal((await stat(authPath)).mode & 0o777, 0o600);
  let command;
  extension.default({ registerCommand(name, options) { assert.equal(name, 'codex-auth'); command = options; } });
  const notices = [];
  const ctx = { isIdle: () => false, ui: { notify: message => notices.push(message) } };
  await command.handler('', ctx);
  assert.match(notices.pop(), /idle/);
  ctx.isIdle = () => true;
  await command.handler('remove --all', ctx);
  assert.match(notices.pop(), /Usage/);
  ctx.mode = 'rpc';
  await command.handler('', ctx);
  assert.match(notices.pop(), /terminal UI/);
  console.log('PASS: credential validation, expired tokens, locked merge, 0600 permissions, live runtime account changes, invalid-input preservation, command registration, busy/argument/RPC guards.');
} finally {
  await rm(dir, { recursive: true, force: true });
}
