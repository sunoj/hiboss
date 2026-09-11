// Client-instance contracts shared by token issuance, authentication, and routes.
// Exports branded ClientId, ClientKind, ClientRegistration, and BossClient.
// Dependencies: none.
export type ClientId = string & { readonly __brand: 'ClientId' };
export type ClientKind = 'ios' | 'macos' | 'web' | 'cli';
export interface ClientRegistration { kind: ClientKind; label: string }
export interface BossClient extends ClientRegistration {
  id: ClientId;
  created_at: string;
  last_seen_at: string | null;
  revoked_at: string | null;
  has_push_device: boolean;
  has_signing_key: boolean;
  is_current: boolean;
}
