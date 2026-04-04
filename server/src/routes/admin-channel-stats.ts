// Channel delivery stats helpers for admin diagnostics endpoints.
// Exports getChannelStatsResponse() for default and verbose channel health payloads.
// Depends on the worker Env binding and message/channel tables.

import type { Env } from '../types';

type ChannelAggregateRow = {
  channel: string;
  total_sent: number | string | null;
  total_delivered: number | string | null;
  total_failed: number | string | null;
  last_delivery_at: string | null;
};

type DeliveryErrorRow = {
  channel: string;
  message_id?: string;
  last_error: string | null;
  last_error_at: string | null;
};

type DirectionCountRow = {
  channel: string;
  direction: string;
  total: number | string | null;
};

type TableInfoRow = {
  name: string;
};

export async function getChannelStatsResponse(env: Env, agentId: string, verbose: boolean): Promise<Record<string, unknown>> {
  const channels = await listTrackedChannels(env, agentId);
  const aggregates = await loadChannelAggregates(env, agentId);
  const errors = await loadLastErrors(env, agentId);
  const stats = channels.map((channel) => {
    const aggregate = aggregates.get(channel);
    const error = errors.get(channel);
    return {
      channel,
      total_sent: aggregate?.total_sent ?? 0,
      total_delivered: aggregate?.total_delivered ?? 0,
      total_failed: aggregate?.total_failed ?? 0,
      last_delivery_at: aggregate?.last_delivery_at ?? null,
      last_error: error?.last_error ?? null,
      last_error_at: error?.last_error_at ?? null,
    };
  });
  if (!verbose) {
    return { channels: stats };
  }
  return {
    channels: stats,
    recent_errors: await loadRecentErrors(env, agentId),
    delivery_queue: await loadDeliveryQueue(env, agentId),
    direction_counts: await loadDirectionCounts(env, agentId),
  };
}

async function listTrackedChannels(env: Env, agentId: string): Promise<string[]> {
  const rows = await env.DB
    .prepare(
      `SELECT channel FROM channel_configs WHERE agent_id = ?
       UNION
       SELECT DISTINCT channel FROM messages WHERE agent_id = ? AND channel IS NOT NULL AND channel != 'api'
       ORDER BY channel`
    )
    .bind(agentId, agentId)
    .all<{ channel: string }>();
  return (rows.results ?? []).map((row) => row.channel);
}

async function loadChannelAggregates(env: Env, agentId: string): Promise<Map<string, ChannelAggregateRow>> {
  const rows = await env.DB
    .prepare(
      `SELECT
         channel,
         COUNT(*) AS total_sent,
         SUM(CASE WHEN status IN ('delivered', 'read', 'replied') THEN 1 ELSE 0 END) AS total_delivered,
         SUM(CASE WHEN json_extract(metadata, '$.delivery_error') IS NOT NULL THEN 1 ELSE 0 END) AS total_failed,
         MAX(CASE WHEN status IN ('delivered', 'read', 'replied') THEN strftime('%Y-%m-%dT%H:%M:%SZ', updated_at) END) AS last_delivery_at
       FROM messages
       WHERE agent_id = ? AND channel IS NOT NULL AND channel != 'api'
       GROUP BY channel`
    )
    .bind(agentId)
    .all<ChannelAggregateRow>();
  return new Map(
    (rows.results ?? []).map((row) => [
      row.channel,
      {
        ...row,
        total_sent: toNumber(row.total_sent),
        total_delivered: toNumber(row.total_delivered),
        total_failed: toNumber(row.total_failed),
      },
    ])
  );
}

async function loadLastErrors(env: Env, agentId: string): Promise<Map<string, DeliveryErrorRow>> {
  const rows = await env.DB
    .prepare(
      `SELECT
         messages.channel,
         json_extract(messages.metadata, '$.delivery_error') AS last_error,
         strftime('%Y-%m-%dT%H:%M:%SZ', messages.updated_at) AS last_error_at
       FROM messages
       INNER JOIN (
         SELECT channel, MAX(updated_at) AS updated_at
         FROM messages
         WHERE agent_id = ? AND channel IS NOT NULL AND channel != 'api' AND json_extract(metadata, '$.delivery_error') IS NOT NULL
         GROUP BY channel
       ) latest
         ON latest.channel = messages.channel
        AND latest.updated_at = messages.updated_at
       WHERE messages.agent_id = ? AND json_extract(messages.metadata, '$.delivery_error') IS NOT NULL
       ORDER BY messages.updated_at DESC`
    )
    .bind(agentId, agentId)
    .all<DeliveryErrorRow>();
  return new Map((rows.results ?? []).map((row) => [row.channel, row]));
}

async function loadRecentErrors(env: Env, agentId: string): Promise<DeliveryErrorRow[]> {
  const rows = await env.DB
    .prepare(
      `SELECT
         id AS message_id,
         channel,
         json_extract(metadata, '$.delivery_error') AS last_error,
         strftime('%Y-%m-%dT%H:%M:%SZ', updated_at) AS last_error_at
       FROM messages
       WHERE agent_id = ? AND channel IS NOT NULL AND channel != 'api' AND json_extract(metadata, '$.delivery_error') IS NOT NULL
       ORDER BY updated_at DESC
       LIMIT 5`
    )
    .bind(agentId)
    .all<DeliveryErrorRow>();
  return rows.results ?? [];
}

async function loadDirectionCounts(env: Env, agentId: string): Promise<Array<{ channel: string; direction: string; total: number }>> {
  const rows = await env.DB
    .prepare(
      `SELECT channel, direction, COUNT(*) AS total
       FROM messages
       WHERE agent_id = ? AND channel IS NOT NULL AND channel != 'api'
       GROUP BY channel, direction
       ORDER BY channel, direction`
    )
    .bind(agentId)
    .all<DirectionCountRow>();
  return (rows.results ?? []).map((row) => ({
    channel: row.channel,
    direction: row.direction,
    total: toNumber(row.total),
  }));
}

async function loadDeliveryQueue(env: Env, agentId: string): Promise<Record<string, unknown> | null> {
  const table = await env.DB
    .prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'delivery_queue'")
    .first<{ name: string }>();
  if (!table) {
    return null;
  }
  const columns = await env.DB.prepare('PRAGMA table_info(delivery_queue)').all<TableInfoRow>();
  const names = new Set((columns.results ?? []).map((row) => row.name));
  const whereClause = names.has('agent_id') ? ' WHERE agent_id = ?' : '';
  const bindings = whereClause ? [agentId] : [];
  const total = await env.DB
    .prepare(`SELECT COUNT(*) AS total FROM delivery_queue${whereClause}`)
    .bind(...bindings)
    .first<{ total: number | string | null }>();
  const payload: Record<string, unknown> = { total: toNumber(total?.total ?? 0) };
  if (names.has('status')) {
    const rows = await env.DB
      .prepare(`SELECT status, COUNT(*) AS total FROM delivery_queue${whereClause} GROUP BY status ORDER BY status`)
      .bind(...bindings)
      .all<{ status: string; total: number | string | null }>();
    payload.by_status = (rows.results ?? []).map((row) => ({ status: row.status, total: toNumber(row.total) }));
  }
  const timestampColumn = names.has('created_at') ? 'created_at' : names.has('available_at') ? 'available_at' : names.has('run_at') ? 'run_at' : null;
  if (!timestampColumn) {
    return payload;
  }
  const oldest = await env.DB
    .prepare(`SELECT MIN(strftime('%Y-%m-%dT%H:%M:%SZ', ${timestampColumn})) AS oldest_at FROM delivery_queue${whereClause}`)
    .bind(...bindings)
    .first<{ oldest_at: string | null }>();
  payload.oldest_at = oldest?.oldest_at ?? null;
  return payload;
}

function toNumber(value: number | string | null): number {
  if (typeof value === 'number') {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}
