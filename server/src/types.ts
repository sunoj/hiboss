// Shared domain types for hiboss server bindings, responses, and exports.
// Exports Env, message shapes, channel config contracts, and metadata helpers.
// Depends only on Cloudflare D1 typings for the binding.

import type { D1Database } from '@cloudflare/workers-types';

export type Env = {
  DB: D1Database;
};

export type Direction = 'agent_to_boss' | 'boss_to_agent';
export type Mode = 'async' | 'blocking';
export type Channel = 'discord' | 'telegram' | 'email';
export type Priority = 'critical' | 'high' | 'normal' | 'low';
export type Status = 'sent' | 'delivered' | 'read' | 'replied';

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
  channel_id: string;
  bot_token: string;
}

export interface TelegramChannelConfig {
  chat_id: string;
  bot_token: string;
}
