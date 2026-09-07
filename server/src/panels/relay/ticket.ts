// Connection ticket encoding and scope types shared by the panel route and DO.
// Exports ticket envelopes, roles, operations, and internal issuance contracts.
// Dependencies: Web Crypto and Web Platform base64/text codecs.

export type PanelRole = 'producer' | 'subscriber';
export type PanelOperation = 'subscribe' | 'lease.claim' | 'state.update';

export interface TicketEnvelope {
  readonly roomId: string;
  readonly ticketId: string;
  readonly secret: string;
}

export interface IssuedTicket {
  readonly ticket: string;
  readonly roomId: string;
  readonly identity: string;
  readonly role: PanelRole;
  readonly panelId: string;
  readonly operations: readonly PanelOperation[];
  readonly expiresAt: number;
}

export interface IssueTicketRequest {
  readonly roomId: string;
  readonly identity: string;
  readonly role: PanelRole;
  readonly panelId: string;
  readonly operations: readonly PanelOperation[];
  readonly expiresAt: number;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function isPanelRole(value: unknown): value is PanelRole {
  return value === 'producer' || value === 'subscriber';
}

export function isPanelOperation(value: unknown): value is PanelOperation {
  return value === 'subscribe' || value === 'lease.claim' || value === 'state.update';
}

function toBase64Url(value: string): string {
  const bytes = new TextEncoder().encode(value);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function fromBase64Url(value: string): string | null {
  try {
    const binary = atob(value.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - (value.length % 4)) % 4));
    const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
    return new TextDecoder().decode(bytes);
  } catch {
    return null;
  }
}

export function createTicketSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

export function encodeTicketEnvelope(envelope: TicketEnvelope): string {
  return toBase64Url(JSON.stringify(envelope));
}

export function decodeTicketEnvelope(value: string | null): TicketEnvelope | null {
  if (!value) return null;
  const decoded = fromBase64Url(value);
  if (!decoded) return null;
  try {
    const parsed = JSON.parse(decoded) as unknown;
    if (!isRecord(parsed)) return null;
    if (typeof parsed.roomId !== 'string' || !parsed.roomId) return null;
    if (typeof parsed.ticketId !== 'string' || !parsed.ticketId) return null;
    if (typeof parsed.secret !== 'string' || !parsed.secret) return null;
    return { roomId: parsed.roomId, ticketId: parsed.ticketId, secret: parsed.secret };
  } catch {
    return null;
  }
}

export function parseIssueTicketRequest(value: unknown): IssueTicketRequest | null {
  if (!isRecord(value) || typeof value.roomId !== 'string' || !value.roomId) return null;
  if (typeof value.identity !== 'string' || !value.identity || typeof value.panelId !== 'string' || !value.panelId) return null;
  if (!isPanelRole(value.role) || !Array.isArray(value.operations) || !value.operations.every(isPanelOperation)) return null;
  if (typeof value.expiresAt !== 'number' || !Number.isInteger(value.expiresAt)) return null;
  return {
    roomId: value.roomId,
    identity: value.identity,
    role: value.role,
    panelId: value.panelId,
    operations: value.operations,
    expiresAt: value.expiresAt,
  };
}
