// HTTP routes for "Sign in with iPhone". signinRouter (/api/signin) serves the signed-out
// Mac: open a request, poll it, complete it with the code. bossSigninRouter
// (/api/boss/signin-requests) lets a signed-in admin or manager review, approve or reject.

import { Hono, type Context } from 'hono';
import type { Env } from '../types';
import { bossAuth, getBossId, getBossRole, getBossTokenId, hashApiKey } from '../middleware/auth';
import { issueBossToken } from '../boss-token';
import { logAudit } from '../audit';
import { parseSigningRegistration, verifySigninRegistration } from '../message-security';
import {
  approveRequest, completeRequest, findById, findByPollToken, openRequest, recordIssuedToken, rejectRequest, toView,
} from '../signin/store';

const SIGNIN_ROLES = ['admin', 'manager'];
const MAX_DEVICE_LABEL_LENGTH = 100;
const POLL_HEADER = 'X-Signin-Token';
const REQUEST_ID = /^[0-9a-f]{32}$/;
const POLL_TOKEN = /^st_[0-9a-f]{64}$/;
const CODE = /^[0-9]{6}$/;

type AppContext = Context<{ Bindings: Env }>;

export const signinRouter = createSigninRouter();
export const bossSigninRouter = createBossSigninRouter();

function parseDeviceLabel(value: unknown): string | null {
  const label = typeof value === 'string' ? value.trim() : '';
  // The approver reads this label, so no markup, controls, format (bidi, zero-width), line/paragraph separators, private-use or lone surrogates.
  if (!label || label.length > MAX_DEVICE_LABEL_LENGTH || /[<>&\p{Cc}\p{Cf}\p{Zl}\p{Zp}\p{Co}\p{Cs}]/u.test(label)) return null;
  return label;
}

/** Coarse "country · city" from Cloudflare's request metadata, shown to the approver. */
function originHint(c: AppContext): string | null {
  const cf = (c.req.raw as Request & { cf?: { country?: unknown; city?: unknown } }).cf;
  const parts = [cf?.country, cf?.city].filter((part): part is string => typeof part === 'string' && part.length > 0);
  return parts.length ? parts.join(' · ').slice(0, 100) : null;
}

/** The network an address belongs to: an IPv4 address itself, an IPv6 address's /64 prefix. */
export function originNetwork(ip: string): string {
  if (!ip.includes(':')) return ip;
  const [head, tail = ''] = ip.toLowerCase().split('::');
  const left = head ? head.split(':') : [];
  const right = tail ? tail.split(':') : [];
  const groups = ip.includes('::') ? [...left, ...Array(Math.max(0, 8 - left.length - right.length)).fill('0'), ...right] : left;
  return groups.slice(0, 4).map(group => group.replace(/^0+(?=.)/, '')).join(':') + '::/64';
}

/** A hash of the opener's network, used only to cap open requests per network; null off Cloudflare. */
async function originKey(c: AppContext): Promise<string | null> {
  const ip = c.req.header('CF-Connecting-IP')?.trim();
  return ip ? hashApiKey(`signin-origin:${originNetwork(ip)}`) : null;
}

async function readJson(c: AppContext): Promise<Record<string, unknown> | null> {
  const body = await c.req.json<unknown>().catch(() => null);
  return body && typeof body === 'object' && !Array.isArray(body) ? body as Record<string, unknown> : null;
}

async function polledRequest(c: AppContext) {
  const token = c.req.header(POLL_HEADER)?.trim() ?? '';
  return POLL_TOKEN.test(token) ? findByPollToken(c.env.DB, token) : null;
}

function createSigninRouter(): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>({});
  routes.post('/requests', async (c) => {
    // A JSON content type keeps a cross-site form or text/plain POST from opening requests.
    if (!c.req.header('Content-Type')?.toLowerCase().startsWith('application/json')) {
      return c.text('content type must be application/json', 415);
    }
    const label = parseDeviceLabel((await readJson(c))?.device_label);
    if (!label) return c.text('device_label is required', 400);
    const opened = await openRequest(c.env.DB, label, originHint(c), await originKey(c));
    if (!opened) return c.text('too many open sign-in requests', 429);
    return c.json(opened, 201);
  });
  routes.get('/status', async (c) => {
    const row = await polledRequest(c);
    if (!row) return c.text('sign-in request not found', 404);
    const { status, expires_at } = toView(row, new Date().toISOString());
    return c.json({ status, expires_at });
  });
  routes.post('/complete', completeHandler);
  return routes;
}

async function completeHandler(c: AppContext): Promise<Response> {
  const row = await polledRequest(c);
  if (!row) return c.text('sign-in request not found', 404);
  const body = await readJson(c);
  const code = typeof body?.code === 'string' ? body.code.trim() : '';
  if (!CODE.test(code)) return c.text('a 6-digit code is required', 400);
  const signing = parseSigningRegistration(body?.signing);
  if (body?.signing !== undefined && !signing) return c.text('invalid signing registration', 400);
  const signingKey = signing ? await verifySigninRegistration(row.id, signing) : null;
  if (signing && !signingKey) return c.text('invalid signing proof', 400);
  const bossId = await completeRequest(c.env.DB, row, code);
  if (!bossId) return c.text('incorrect code or request no longer valid', 400);
  const boss = await c.env.DB.prepare('SELECT id, name, role FROM bosses WHERE id = ? AND archived_at IS NULL')
    .bind(bossId).first<{ id: string; name: string; role: string }>();
  if (!boss) return c.text('incorrect code or request no longer valid', 400);
  const grant = await issueBossToken(c.env, boss.id, row.device_label, signingKey ?? undefined, {
    kind: signingKey?.clientKind ?? 'web', label: row.device_label,
  });
  // The token already exists; a failed bookkeeping write must not withhold it.
  await recordIssuedToken(c.env.DB, row.id, grant.tokenId).catch(() => console.error('signin: issued token not recorded'));
  await logAudit(c.env, 'boss', boss.id, 'signin.complete', 'boss_token', grant.tokenId, row.id);
  return c.json({ token: grant.token, boss, ...(signingKey ? { signing_key_id: signingKey.id } : {}) });
}

function createBossSigninRouter(): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>({});
  routes.use('*', bossAuth);
  // Approval mints a token for the approving boss, so it never grants more than the approver holds.
  routes.use('*', async (c, next) => {
    if (!SIGNIN_ROLES.includes(getBossRole(c))) return c.json({ error: 'admin or manager required' }, 403);
    await next();
  });
  routes.get('/:id', async (c) => {
    const id = c.req.param('id');
    const row = REQUEST_ID.test(id) ? await findById(c.env.DB, id) : null;
    if (!row) return c.text('sign-in request not found', 404);
    return c.json(toView(row, new Date().toISOString()));
  });
  routes.post('/:id/approve', async (c) => {
    const id = c.req.param('id');
    const code = REQUEST_ID.test(id) ? await approveRequest(c.env.DB, id, getBossId(c), getBossTokenId(c)) : null;
    if (!code) return c.text('sign-in request is not pending', 409);
    await logAudit(c.env, 'boss', getBossId(c), 'signin.approve', 'signin_request', id);
    const row = await findById(c.env.DB, id);
    return c.json({ code, expires_at: row?.expires_at ?? null, device_label: row?.device_label ?? null });
  });
  routes.post('/:id/reject', async (c) => {
    const id = c.req.param('id');
    const rejected = REQUEST_ID.test(id) && await rejectRequest(c.env.DB, id, getBossId(c));
    return rejected ? c.json({ ok: true }) : c.text('sign-in request is not open', 409);
  });
  return routes;
}
