// Durable Object that maintains a WebSocket connection to Discord Gateway.
// Receives MESSAGE_CREATE events and inserts boss messages into D1.
// Depends on Discord Gateway v10 protocol, DO storage for session state, and webhook-helpers.

import type { Env, MessageRow } from './types';
import { insertBossDiscordMessage } from './routes/webhook-helpers';
import { notifyAgentCallback } from './notify';

const GATEWAY_URL = 'wss://gateway.discord.gg/?v=10&encoding=json';
const INTENTS = (1 << 9) | (1 << 15); // GUILD_MESSAGES + MESSAGE_CONTENT

interface GatewayPayload {
  op: number;
  d: unknown;
  s: number | null;
  t: string | null;
}

interface ReadyData {
  session_id: string;
  resume_gateway_url: string;
}

interface MessageCreateData {
  id: string;
  channel_id: string;
  content: string;
  author: { id: string; bot?: boolean };
  message_reference?: { message_id?: string };
}

export class DiscordGateway implements DurableObject {
  private state: DurableObjectState;
  private env: Env;
  private ws: WebSocket | null = null;
  private heartbeatInterval = 0;
  private ackReceived = true;
  private botToken = '';

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === 'POST' && url.pathname === '/connect') {
      const body = await request.json<{ bot_token?: string }>();
      const token = body.bot_token ?? await this.findBotToken();
      if (!token) return new Response('no bot_token available', { status: 400 });
      this.botToken = token;
      await this.state.storage.put('bot_token', token);
      try {
        await this.connect();
        return new Response(JSON.stringify({ status: 'connected' }), { headers: { 'Content-Type': 'application/json' } });
      } catch (error) {
        console.error('[discord-gw] connect failed:', error);
        return new Response(JSON.stringify({ status: 'error', message: String(error) }), { status: 502, headers: { 'Content-Type': 'application/json' } });
      }
    }
    if (request.method === 'POST' && url.pathname === '/disconnect') {
      await this.disconnect();
      return new Response(JSON.stringify({ status: 'disconnected' }), { headers: { 'Content-Type': 'application/json' } });
    }
    if (request.method === 'GET' && url.pathname === '/status') {
      const sessionId = await this.state.storage.get<string>('session_id');
      const connected = !!sessionId;
      return new Response(JSON.stringify({ connected, session_id: sessionId ?? null }), { headers: { 'Content-Type': 'application/json' } });
    }
    return new Response('not found', { status: 404 });
  }

  async alarm(): Promise<void> {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      // Try to reconnect
      const token = await this.state.storage.get<string>('bot_token');
      if (token) {
        this.botToken = token;
        await this.connect();
      }
      return;
    }
    if (!this.ackReceived) {
      // Zombie connection — close and reconnect
      console.log('[discord-gw] no heartbeat ACK, reconnecting');
      this.ws.close(4000, 'zombie');
      this.ws = null;
      await this.connect();
      return;
    }
    this.ackReceived = false;
    const seq = await this.state.storage.get<number>('sequence');
    this.ws.send(JSON.stringify({ op: 1, d: seq ?? null }));
    await this.state.storage.setAlarm(Date.now() + this.heartbeatInterval);
  }

  private async connect(): Promise<void> {
    if (this.ws) {
      try { this.ws.close(); } catch { /* ignore */ }
      this.ws = null;
    }
    const resumeUrl = await this.state.storage.get<string>('resume_gateway_url');
    const url = resumeUrl ?? GATEWAY_URL;
    const ws = new WebSocket(url);
    this.ws = ws;
    // Set a short keepalive alarm to keep DO alive for HELLO/IDENTIFY/READY
    await this.state.storage.setAlarm(Date.now() + 1000);
    await this.state.storage.put('connecting', true);
    console.log(`[discord-gw] opening WebSocket to ${url}`);
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => { reject(new Error('WebSocket open timeout')); }, 10000);
      const onOpen = () => { clearTimeout(timeout); ws.removeEventListener('error', onError); console.log('[discord-gw] WebSocket opened'); resolve(); };
      const onError = (e: Event) => { clearTimeout(timeout); ws.removeEventListener('open', onOpen); console.error('[discord-gw] WebSocket open error', e); reject(e); };
      ws.addEventListener('open', onOpen, { once: true });
      ws.addEventListener('error', onError, { once: true });
    });
    await this.state.storage.delete('connecting');
    ws.addEventListener('message', (event) => void this.onMessage(event));
    ws.addEventListener('close', () => void this.onClose());
    ws.addEventListener('error', (e) => console.error('[discord-gw] ws error', e));
  }

  private async disconnect(): Promise<void> {
    await this.state.storage.deleteAlarm();
    if (this.ws) {
      try { this.ws.close(1000, 'requested'); } catch { /* ignore */ }
      this.ws = null;
    }
    await this.state.storage.delete('session_id');
    await this.state.storage.delete('sequence');
    await this.state.storage.delete('resume_gateway_url');
  }

  private async onMessage(event: MessageEvent): Promise<void> {
    let payload: GatewayPayload;
    try {
      const raw = typeof event.data === 'string' ? event.data : new TextDecoder().decode(event.data as ArrayBuffer);
      payload = JSON.parse(raw) as GatewayPayload;
      console.log(`[discord-gw] recv op=${payload.op} t=${payload.t}`);
    } catch (e) { console.error('[discord-gw] parse error', e); return; }

    if (payload.s !== null) {
      await this.state.storage.put('sequence', payload.s);
    }

    switch (payload.op) {
      case 10: // HELLO
        await this.handleHello(payload.d as { heartbeat_interval: number });
        break;
      case 0: // DISPATCH
        await this.handleDispatch(payload.t, payload.d);
        break;
      case 11: // HEARTBEAT_ACK
        this.ackReceived = true;
        break;
      case 7: // RECONNECT
        console.log('[discord-gw] reconnect requested');
        this.ws?.close(4000, 'reconnect');
        this.ws = null;
        await this.connect();
        break;
      case 9: { // INVALID_SESSION
        const resumable = payload.d as boolean;
        console.log(`[discord-gw] invalid session, resumable=${resumable}`);
        if (!resumable) {
          await this.state.storage.delete('session_id');
          await this.state.storage.delete('sequence');
        }
        this.ws?.close(4000, 'invalid_session');
        this.ws = null;
        // Brief delay before reconnecting
        await this.state.storage.setAlarm(Date.now() + 3000);
        break;
      }
      case 1: // HEARTBEAT request from server
        this.ws?.send(JSON.stringify({ op: 1, d: await this.state.storage.get<number>('sequence') ?? null }));
        break;
    }
  }

  private async handleHello(data: { heartbeat_interval: number }): Promise<void> {
    this.heartbeatInterval = data.heartbeat_interval;
    this.ackReceived = true;
    // Send initial heartbeat with jitter
    const jitter = Math.random() * this.heartbeatInterval;
    await this.state.storage.setAlarm(Date.now() + jitter);
    // Try RESUME first, fall back to IDENTIFY
    const sessionId = await this.state.storage.get<string>('session_id');
    const seq = await this.state.storage.get<number>('sequence');
    if (sessionId && seq !== undefined) {
      this.ws?.send(JSON.stringify({ op: 6, d: { token: this.botToken, session_id: sessionId, seq } }));
    } else {
      this.ws?.send(JSON.stringify({ op: 2, d: { token: this.botToken, intents: INTENTS, properties: { os: 'cloudflare', browser: 'hiboss', device: 'hiboss' } } }));
    }
  }

  private async handleDispatch(eventName: string | null, data: unknown): Promise<void> {
    if (eventName === 'READY') {
      const ready = data as ReadyData;
      await this.state.storage.put('session_id', ready.session_id);
      await this.state.storage.put('resume_gateway_url', ready.resume_gateway_url);
      console.log(`[discord-gw] connected, session=${ready.session_id}`);
    } else if (eventName === 'MESSAGE_CREATE') {
      await this.handleMessageCreate(data as MessageCreateData);
    }
  }

  private async handleMessageCreate(msg: MessageCreateData): Promise<void> {
    if (msg.author.bot) return; // Ignore bot messages
    if (!msg.content) return;
    const replyToDiscordMsgId = msg.message_reference?.message_id;
    try {
      const inserted = await insertBossDiscordMessage(
        this.env, msg.channel_id, msg.content, msg.author.id,
        replyToDiscordMsgId, msg.id, { discord_msg: msg }
      );
      if (inserted) {
        await notifyAgentCallback(this.env, inserted.agent_id, inserted);
      }
    } catch (error) {
      console.error(`[discord-gw] message insert failed: ${error}`);
    }
  }

  private async onClose(): Promise<void> {
    this.ws = null;
    console.log('[discord-gw] connection closed');
    // Schedule reconnect via alarm
    if (this.heartbeatInterval > 0) {
      await this.state.storage.setAlarm(Date.now() + 5000);
    }
  }

  private async findBotToken(): Promise<string | undefined> {
    const row = await this.env.DB
      .prepare("SELECT config FROM channel_configs WHERE channel = 'discord' AND enabled = 1 LIMIT 1")
      .first<{ config: string }>();
    if (!row) return undefined;
    try {
      const config = JSON.parse(row.config) as Record<string, unknown>;
      return typeof config['bot_token'] === 'string' ? config['bot_token'] : undefined;
    } catch { return undefined; }
  }
}
