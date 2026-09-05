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
    auth = {'openai-codex': credential('one')}
    (root / 'auth.json').write_text(json.dumps(auth))
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
    def launch():
        process = subprocess.Popen([PI, '--no-extensions', '-e', str(root / 'network-fixture.ts'), '-e', str(ROOT), '--mode', 'rpc', '--no-session', '--provider', 'openai-codex', '--model', 'gpt-5.4'], cwd=d, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        output = queue.Queue()
        def reader():
            for line in process.stdout:
                try: output.put(json.loads(line))
                except ValueError: pass
        threading.Thread(target=reader, daemon=True).start()
        return process, output
    def stop(process):
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
    p, events = launch()
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
        saved = json.loads((root / 'pi-accounts.json').read_text())
        assert saved['providers']['openai-codex']['active'] == 'personal', 'Selection not remembered on disk'
        assert saved['providers']['openai-codex']['accounts'] == store['providers']['openai-codex']['accounts'], 'Credentials changed'
        stop(p)
        p, events = launch()
        send({'id':'fresh-menu','type':'prompt','message':'/accounts'})
        fresh = wait(lambda e: e.get('type') == 'extension_ui_request' and e.get('method') == 'select')
        assert 'OpenAI Codex: personal' in json.dumps(fresh), 'Fresh process did not inherit last selection'
        switch = next(o for o in fresh['options'] if 'Switch OpenAI Codex account' in o)
        send({'type':'extension_ui_response','id':fresh['id'],'value':switch})
        picker = wait(lambda e: e.get('type') == 'extension_ui_request' and e.get('method') == 'select')
        default_option = next(o for o in picker['options'] if o.startswith('default'))
        send({'type':'extension_ui_response','id':picker['id'],'value':default_option})
        wait(lambda e: e.get('method') == 'notify' and 'Using default Pi' in e.get('message',''))
        saved = json.loads((root / 'pi-accounts.json').read_text())
        assert 'active' not in saved['providers']['openai-codex'], 'Default selection not remembered'
        stop(p)
        p, events = launch()
        send({'id':'default-menu','type':'prompt','message':'/accounts'})
        fresh = wait(lambda e: e.get('type') == 'extension_ui_request' and e.get('method') == 'select')
        assert 'default' in json.dumps(fresh) and 'work' in json.dumps(fresh), 'Fresh process did not inherit default login'
        send({'type':'extension_ui_response','id':fresh['id'],'cancelled':True})
        assert json.loads((root / 'auth.json').read_text()) == auth, 'Built-in auth changed'
        print('PASS: menus show identity and quotas; named and default selections survive fresh Pi processes; credentials preserved.')
    finally:
        stop(p)
