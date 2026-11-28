// Parses send requests, strips server-owned metadata.
// Exports prepareSendInput and its inferred contract; depends on shared validators.
import type { Context } from 'hono';
import type { Env, Mode, Priority } from '../types';
import { getAgentId } from '../middleware/auth';
import { stripServerOwnedMetadata } from '../message-security';
import { checkRateLimit, validateOption, priorityOptions, parseOptions, normalizeMetadata, parseOptionMedia } from './message-helpers';
import { parseOptionDescriptions } from './option-descriptions';
import { parseAskForm } from './message-form';
import { getAttachmentKey } from './progress-helpers';
const modeOptions: Mode[] = ['async', 'blocking'];
export interface SendInput {
  agentId: string;
  payload: Record<string, unknown>;
  body: string;
  idempotencyKey: string | null;
  mode: Mode;
  priority: Priority;
  fileUrl: string | undefined;
  messageType: string;
  sessionId: string | null;
  toAgent: string | null;
  options: string[] | undefined;
  metadata: Record<string, unknown> | null;
  /** Client-owned metadata exactly as a signature must cover it. */
  clientMetadata: Record<string, unknown> | null;
  timeout: number | null;
  /** Set for webhook posts from an integration agent. */
  integration?: boolean;
}
export async function prepareSendInput(c: Context<{ Bindings: Env }>): Promise<Response | SendInput> {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) {
    return c.text('body is required', 400);
  }
  const idempotencyKey = typeof payload.idempotency_key === 'string' ? payload.idempotency_key.trim() || null : null;
  const agentConfig = await c.env.DB
    .prepare('SELECT default_priority, rate_limit FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ default_priority: string; rate_limit: number | null }>();
  const defaultPriority = (agentConfig?.default_priority ?? 'normal') as Priority;
  if (agentConfig?.rate_limit && await checkRateLimit(c.env, agentId, agentConfig.rate_limit)) {
    return c.text('rate limit exceeded', 429);
  }
  const mode = validateOption<Mode>(payload.mode, modeOptions, 'async') as Mode;
  const priority = validateOption<Priority>(payload.priority, priorityOptions, defaultPriority) as Priority;
  const fileUrl = typeof payload.file_url === 'string' ? payload.file_url.trim() : undefined;
  const messageType = typeof payload.type === 'string' ? payload.type.trim() : 'text';
  const sessionId = typeof payload.session_id === 'string' ? payload.session_id.trim() || null : null;
  const toAgent = typeof payload.to === 'string' ? payload.to.trim() || null : null;
  const optionsResult = parseOptions(payload.options);
  if (!optionsResult.ok) return c.text(optionsResult.error, 400);
  const options = optionsResult.value;
  const clientMetadata = stripServerOwnedMetadata(normalizeMetadata(payload.metadata));
  const rawMetadata: Record<string, unknown> = { ...clientMetadata };
  const descriptions = parseOptionDescriptions(rawMetadata['option_descriptions'], options);
  if (!descriptions.ok) return c.text(descriptions.error, 400);
  if (descriptions.value) rawMetadata['option_descriptions'] = descriptions.value;
  const formError = askFormError(rawMetadata, options, mode, toAgent);
  if (formError) return c.text(formError, 400);
  const timeout = typeof payload.timeout === 'number' ? payload.timeout : null;
  // Only the send timeout can grant a blocking caller its own deadline.
  if (mode === 'blocking' && typeof payload.timeout === 'number') rawMetadata['ask_deadline'] = true;
  const requestUrl = new URL(c.req.url);
  const optionMediaResult = parseOptionMedia(rawMetadata['option_media'], options, requestUrl);
  if (!optionMediaResult.ok) return c.text(optionMediaResult.error, 400);
  const thumbnailError = fileThumbnailError(rawMetadata['file_thumbnail_url'], fileUrl, requestUrl);
  if (thumbnailError) return c.text(thumbnailError, 400);
  if (fileUrl) (rawMetadata as Record<string, unknown>)['file_url'] = fileUrl;
  if (options) (rawMetadata as Record<string, unknown>)['options'] = options;
  if (optionMediaResult.value) (rawMetadata as Record<string, unknown>)['option_media'] = optionMediaResult.value;
  const metadata = Object.keys(rawMetadata as Record<string, unknown>).length > 0 ? rawMetadata : null;
  return { agentId, payload, body, idempotencyKey, mode, priority, fileUrl, messageType, sessionId, toAgent, options, metadata, clientMetadata, timeout };
}

/**
 * A form ask's question is its one v2 input: it offers no options, has no timeout default
 * (expiry never fills in a structured answer), and is always a blocking ask.
 */
function askFormError(metadata: Record<string, unknown>, options: string[] | undefined, mode: Mode,
  toAgent: string | null): string | null {
  if (metadata['form'] === undefined) return null;
  // Only the boss's apps validate and sign a form answer; an agent reply would close it with text.
  if (toAgent) return 'a form ask goes to the boss, not to another agent';
  const form = parseAskForm(metadata['form']);
  if (!form.ok) return form.error;
  if (options) return 'a form ask cannot also offer options';
  if (metadata['default_option'] !== undefined) return 'a form ask cannot have a default';
  if (mode !== 'blocking') return 'a form ask must be blocking';
  metadata['form'] = form.value;
  return null;
}

/** An optional `file_thumbnail_url` sits beside `file_url` and must be this worker's attachment. */
function fileThumbnailError(value: unknown, fileUrl: string | undefined, requestUrl: URL): string | null {
  if (value === undefined) return null;
  if (!fileUrl) return 'file_thumbnail_url requires file_url';
  if (typeof value !== 'string' || !getAttachmentKey(value, requestUrl)) {
    return 'file_thumbnail_url must point to this worker attachments path';
  }
  return null;
}
