// Shared domain types for hiboss server bindings, responses, and exports.
// Exports Env, message shapes, channel config contracts, and metadata helpers.
// Depends on Cloudflare D1 and R2 typings for bindings.

import type { D1Database, R2Bucket } from '@cloudflare/workers-types';

export type Env = {
  DB: D1Database;
  ATTACHMENTS: R2Bucket;
  BOOTSTRAP_SECRET?: string;
  DISCORD_PUBLIC_KEY?: string;
  DISCORD_GATEWAY?: DurableObjectNamespace;
};

export type Direction = 'agent_to_boss' | 'boss_to_agent' | 'agent_to_agent';
export type Mode = 'async' | 'blocking';
export type Channel = 'discord' | 'telegram' | 'email' | 'api';
export type Priority = 'critical' | 'high' | 'normal' | 'low';
export type Status = 'sent' | 'delivered' | 'read' | 'replied' | 'expired';

export type Metadata = Record<string, unknown> | null;

export interface MessageRow {
  id: string;
  agent_id: string;
  direction: Direction;
  mode: Mode;
  channel: Channel | null;
  body: string;
  status: Status;
  reply_to: string | null;
  priority: Priority;
  type: string | null;
  target_agent_id: string | null;
  target_session_id: string | null;
  session_id: string | null;
  idempotency_key: string | null;
  metadata: string | null;
  created_at: string;
  updated_at: string;
  agent_name?: string | null;
}

export interface MessageResponse {
  id: string;
  agent_id: string;
  direction: Direction;
  mode: Mode;
  channel: Channel | null;
  body: string;
  status: Status;
  reply_to: string | null;
  priority: Priority;
  type: string | null;
  target_agent_id?: string | null;
  target_session_id?: string | null;
  session_id?: string | null;
  idempotency_key?: string | null;
  metadata: Metadata;
  created_at: string;
  updated_at: string;
  replies?: MessageResponse[];
  agent_name?: string | null;
}

export interface ChannelConfigRow {
  id: string;
  agent_id: string;
  channel: Channel;
  config: string;
  enabled: 0 | 1;
  created_at: string;
}

export interface DiscordChannelConfig {
  channel_id?: string;
  bot_token?: string;
  webhook_url?: string;
  avatar_url?: string;
  use_threads?: boolean;
  thread_id?: string;
}

export interface TelegramChannelConfig {
  chat_id: string;
  bot_token: string;
  message_thread_id?: number;
  use_topics?: boolean;
}
