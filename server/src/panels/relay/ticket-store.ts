// Durable Object ticket persistence and atomic single-use consumption.
// Exports issueTicket and consumeTicket for PanelRoom's HTTP boundary.
// Dependencies: Durable Object SQLite storage and relay ticket codecs.

import {
  createTicketSecret,
  decodeTicketEnvelope,
  encodeTicketEnvelope,
  parseIssueTicketRequest,
  type IssueTicketRequest,
  type PanelOperation,
  type PanelRole,
} from './ticket';

export interface ConnectionAttachment {
  readonly ticketId: string;
  readonly roomId: string;
  readonly identity: string;
  readonly role: PanelRole;
  readonly panelId: string;
  readonly operations: readonly PanelOperation[];
  readonly subscribedPanelId?: string;
}

interface TicketRow extends Record<string, string | number | null> {
  ticket_id: string;
  secret: string;
  room_id: string;
  identity: string;
  role: PanelRole;
  panel_id: string;
  operations: string;
  expires_at: number;
  consumed_at: number | null;
}

export type ConsumedTicket =
  | { readonly ok: true; readonly ticket: ConnectionAttachment }
  | { readonly ok: false; readonly status: 401 | 410 };

export async function issueTicket(ctx: DurableObjectState, req: Request): Promise<Response> {
  let request: IssueTicketRequest | null = null;
  try {
    request = parseIssueTicketRequest(await req.json<unknown>());
  } catch {
    request = null;
  }
  if (!request || request.expiresAt <= Date.now()) return new Response('Invalid ticket request', { status: 400 });
  const ticketId = crypto.randomUUID();
  const secret = createTicketSecret();
  ctx.storage.sql.exec(
    'INSERT INTO connection_tickets (ticket_id, secret, room_id, identity, role, panel_id, operations, expires_at, consumed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)',
    ticketId, secret, request.roomId, request.identity, request.role, request.panelId, JSON.stringify(request.operations), request.expiresAt,
  );
  return Response.json({
    ticket: encodeTicketEnvelope({ roomId: request.roomId, ticketId, secret }),
    roomId: request.roomId,
    identity: request.identity,
    role: request.role,
    panelId: request.panelId,
    operations: request.operations,
    expiresAt: request.expiresAt,
  });
}

export function consumeTicket(ctx: DurableObjectState, rawTicket: string | null): ConsumedTicket {
  const envelope = decodeTicketEnvelope(rawTicket);
  if (!envelope) return { ok: false, status: 401 };
  return ctx.storage.transactionSync(() => {
    const row = [...ctx.storage.sql.exec<TicketRow>('SELECT * FROM connection_tickets WHERE ticket_id = ?', envelope.ticketId)][0];
    if (!row || row.secret !== envelope.secret || row.room_id !== envelope.roomId) return { ok: false, status: 401 };
    if (row.expires_at <= Date.now()) return { ok: false, status: 410 };
    if (row.consumed_at !== null) return { ok: false, status: 401 };
    const update = ctx.storage.sql.exec(
      'UPDATE connection_tickets SET consumed_at = ? WHERE ticket_id = ? AND secret = ? AND consumed_at IS NULL',
      Date.now(), envelope.ticketId, envelope.secret,
    );
    if (update.rowsWritten !== 1) return { ok: false, status: 401 };
    return { ok: true, ticket: attachmentFromRow(row) };
  });
}

function attachmentFromRow(row: TicketRow): ConnectionAttachment {
  const operations = JSON.parse(row.operations) as unknown;
  if (!Array.isArray(operations)) throw new Error('ticket operations are invalid');
  return {
    ticketId: row.ticket_id,
    roomId: row.room_id,
    identity: row.identity,
    role: row.role,
    panelId: row.panel_id,
    operations: operations as PanelOperation[],
  };
}
