// Read-only quota requests. No token refresh, auth-file writes, or credential logging.
export type UsageCredential = { access: string; accountId: string };
export type Window = { remaining: number; resetAt?: number; seconds?: number };
export type Usage = { windows: Window[]; error?: string; checkedAt: number };
export type UsageDisplay = { summary: string; details: string[] };

export function tokenIdentity(access: string): { accountId: string; email?: string } | undefined {
  try {
    const claims = JSON.parse(Buffer.from(access.split('.')[1], 'base64url').toString('utf8'));
    const accountId = claims['https://api.openai.com/auth']?.chatgpt_account_id;
    const email = claims['https://api.openai.com/profile']?.email ?? claims.email;
    if (typeof accountId !== 'string' || !accountId) return;
    return { accountId, email: typeof email === 'string' ? email : undefined };
  } catch { return; }
}
export function usageCredential(value: { access?: unknown; accountId?: unknown } | undefined): UsageCredential | undefined {
  if (typeof value?.access !== 'string') return;
  const identity = tokenIdentity(value.access);
  if (!identity || (value.accountId !== undefined && identity.accountId !== value.accountId)) return;
  return { access: value.access, accountId: identity.accountId };
}
export function parseUsage(value: unknown, now = Date.now()): Usage {
  const data = value as { rate_limit?: { primary_window?: unknown; secondary_window?: unknown } } | null;
  const windows: Window[] = [];
  for (const raw of [data?.rate_limit?.primary_window, data?.rate_limit?.secondary_window]) {
    const w = raw as { used_percent?: unknown; reset_at?: unknown; limit_window_seconds?: unknown } | null;
    if (typeof w?.used_percent !== 'number' || !Number.isFinite(w.used_percent)) continue;
    windows.push({
      remaining: Math.max(0, Math.min(100, 100 - w.used_percent)),
      resetAt: typeof w.reset_at === 'number' && Number.isFinite(w.reset_at) && w.reset_at > 0 && w.reset_at < 8.64e12 ? w.reset_at * 1000 : undefined,
      seconds: typeof w.limit_window_seconds === 'number' && Number.isFinite(w.limit_window_seconds) && w.limit_window_seconds > 0 ? w.limit_window_seconds : undefined,
    });
  }
  return { windows, checkedAt: now, ...(!windows.length ? { error: 'Limits unavailable' } : {}) };
}
export async function fetchUsage(credential: UsageCredential, signal: AbortSignal, fetcher: typeof fetch = fetch): Promise<Usage> {
  try {
    const response = await fetcher('https://chatgpt.com/backend-api/wham/usage', {
      headers: { Authorization: `Bearer ${credential.access}`, 'ChatGPT-Account-Id': credential.accountId, Accept: 'application/json' },
      signal: AbortSignal.any([signal, AbortSignal.timeout(6000)]),
      redirect: 'error',
    });
    if (!response.ok) {
      await response.body?.cancel();
      return { windows: [], checkedAt: Date.now(), error: response.status === 401 ? 'Login expired/rejected — select to refresh or log in again' : `Limits unavailable (HTTP ${response.status})` };
    }
    return parseUsage(await response.json());
  } catch {
    return { windows: [], checkedAt: Date.now(), error: signal.aborted ? 'Limits cancelled' : 'Limits unavailable (timeout/network)' };
  }
}
export function displayUsage(usage: Usage | undefined, now = Date.now()): UsageDisplay {
  if (!usage) return { summary: 'Limits unavailable (no OAuth credential)', details: [] };
  if (usage.error) return { summary: usage.error, details: [] };
  const names = usage.windows.map(w => w.seconds === 18000 ? '5h' : w.seconds === 604800 ? 'Weekly' : w.seconds ? `${Math.round(w.seconds / 3600)}h` : 'Window');
  return {
    summary: usage.windows.map((w, i) => `${names[i]} ${Math.round(w.remaining)}% left`).join(' · '),
    details: usage.windows.map((w, i) => {
      if (w.resetAt === undefined) return `${names[i]} reset: unavailable`;
      const minutes = Math.max(0, Math.ceil((w.resetAt - now) / 60000));
      const relative = minutes === 0 ? 'reset due; reopen to refresh' : `in ${Math.floor(minutes / 1440) ? `${Math.floor(minutes / 1440)}d ` : ''}${Math.floor(minutes % 1440 / 60)}h ${minutes % 60}m`;
      const date = new Date(w.resetAt).toLocaleString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', timeZoneName: 'short' });
      return `${names[i]} resets ${date} (${relative})`;
    }),
  };
}
// Lifetime: one menu invocation. Keys contain tokens only in memory; never persist this map.
export function createUsageLoader(fetcher: typeof fetch = fetch) {
  const cache = new Map<string, Usage>();
  const pending = new Map<string, Promise<Usage>>();
  return async (credentials: Map<string, UsageCredential>, signal: AbortSignal): Promise<Map<string, Usage>> => {
    const rows = [...credentials];
    const results = new Map<string, Usage>();
    let cursor = 0;
    await Promise.all(Array.from({ length: Math.min(3, rows.length) }, async () => {
      while (cursor < rows.length && !signal.aborted) {
        const [name, credential] = rows[cursor++];
        const key = `${credential.accountId}:${credential.access}`;
        let usage = cache.get(key);
        if (!usage || Date.now() - usage.checkedAt >= 30000) {
          let request = pending.get(key);
          if (!request) {
            request = fetchUsage(credential, signal, fetcher);
            pending.set(key, request);
          }
          try {
            usage = await request;
            cache.set(key, usage);
          } finally { pending.delete(key); }
        }
        results.set(name, usage);
      }
    }));
    return results;
  };
}
