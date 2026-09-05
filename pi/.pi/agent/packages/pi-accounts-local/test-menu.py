"""Bundled Pi RPC smoke test. Fake accounts, isolated storage, blocked networking."""
import base64, json, os, pathlib, queue, subprocess, tempfile, threading, time
ROOT = pathlib.Path(__file__).resolve().parent
PI = os.environ.get('PI_TEST_BIN', 'pi')

def jwt(account):
    claims = {'exp': int(time.time()) + 7200, 'https://api.openai.com/auth': {'chatgpt_account_id': account}}
    return 'fake.' + base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip('=') + '.fake'

def credential(account):
    return {'type': 'oauth', 'access': jwt(account), 'refresh': 'fake-refresh', 'expires': (int(time.time()) + 7200) * 1000, 'accountId': account}

with tempfile.TemporaryDirectory(prefix='pi-accounts-menu-test-') as d:
    root = pathlib.Path(d)
    (root / 'auth.json').write_text(json.dumps({'openai-codex': credential('one')}))
    store = {'version': 1, 'providers': {'openai-codex': {'accounts': {'work': credential('one'), 'personal': credential('two')}}}}
    (root / 'pi-accounts.json').write_text(json.dumps(store))
    (root / 'network-fixture.ts').write_text('''export default function () {
      globalThis.fetch = async (url) => {
        if (String(url) !== 'https://chatgpt.com/backend-api/wham/usage') throw new Error('Network blocked by test');
        return new Response(JSON.stringify({rate_limit: {
          primary_window: {used_percent: 20, reset_at: Math.floor(Date.now()/1000)+3600, limit_window_seconds: 18000},
          secondary_window: {used_percent: 60, reset_at: Math.floor(Date.now()/1000)+86400, limit_window_seconds: 604800}
        }}));
      };
    }''')
    env = {**os.environ, 'PI_CODING_AGENT_DIR': d, 'CODEX_HOME': d}
    p = subprocess.Popen([PI, '--no-extensions', '-e', str(root / 'network-fixture.ts'), '-e', str(ROOT), '--mode', 'rpc', '--no-session', '--provider', 'openai-codex', '--model', 'gpt-5.4'], cwd=d, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    events = queue.Queue()
    def reader():
        for line in p.stdout:
            try: events.put(json.loads(line))
            except ValueError: pass
    threading.Thread(target=reader, daemon=True).start()
    def send(obj):
        p.stdin.write(json.dumps(obj)+'\n'); p.stdin.flush()
    def wait(predicate):
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            try: event = events.get(timeout=1)
            except queue.Empty: continue
            if predicate(event): return event
        raise AssertionError('Expected RPC event was not received')
    try:
        send({'id':'commands','type':'get_commands'})
        reply = wait(lambda e: e.get('id') == 'commands')
        assert any(c['name'] == 'accounts' for c in reply.get('data',{}).get('commands',[])), 'accounts command missing'
        send({'id':'menu','type':'prompt','message':'/accounts'})
        menu = wait(lambda e: e.get('type') == 'extension_ui_request' and e.get('method') == 'select')
        text = json.dumps(menu)
        assert 'default' in text and 'work' in text, 'Default account identity missing'
        assert '80% left' in text and '40% left' in text and 'resets' in text, 'Main menu quota/reset details missing'
        options = menu['options']
        switch = next(o for o in options if 'Switch OpenAI Codex account' in o)
        send({'type':'extension_ui_response','id':menu['id'],'value':switch})
        picker = wait(lambda e: e.get('type') == 'extension_ui_request' and e.get('method') == 'select')
        text = json.dumps(picker)
        assert 'active' in text and 'work' in text, 'Switch picker active account missing'
        assert '80% left' in text and '40% left' in text, 'Switch picker quotas missing: ' + text
        assert 'resets' in text, 'Switch reset times missing in RPC'
        # Switch only fake credentials in the isolated session, then verify its identity.
        send({'type':'extension_ui_response','id':picker['id'],'value':'personal'})
        wait(lambda e: e.get('type') == 'extension_ui_request' and e.get('method') == 'notify' and 'personal' in e.get('message',''))
        send({'id':'menu-again','type':'prompt','message':'/accounts'})
        again = wait(lambda e: e.get('type') == 'extension_ui_request' and e.get('method') == 'select')
        assert 'OpenAI Codex: personal' in json.dumps(again), 'Named selection not shown after switch'
        send({'type':'extension_ui_response','id':again['id'],'cancelled':True})
        print('PASS: bundled Pi loads local source; main/switch menus show default identity, active marker, quotas and reset times; switching fake accounts updates the displayed identity.')
    finally:
        p.terminate()
        try: p.wait(timeout=5)
        except subprocess.TimeoutExpired: p.kill(); p.wait()
