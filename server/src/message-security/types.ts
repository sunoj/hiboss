// Domain contracts for optional boss-device signing and message provenance.
// Exports branded key IDs, signing registrations, stored keys, and auth results.
// Depends only on structural TypeScript types.

export type SigningKeyId = string & { readonly __brand: 'SigningKeyId' };
export type SigningClientKind = 'ios' | 'macos';

export interface SigningRegistration {
  readonly algorithm: 'ES256';
  readonly clientKind: SigningClientKind;
  readonly publicKey: string;
  readonly proof: string;
}

export interface RegisteredSigningKey {
  readonly id: SigningKeyId;
  readonly algorithm: 'ES256';
  readonly clientKind: SigningClientKind;
  readonly publicKey: string;
}

export interface StoredSigningKey {
  readonly id: string;
  readonly boss_id: string;
  readonly boss_token_id: string;
  readonly algorithm: 'ES256';
  readonly client_kind: SigningClientKind;
  readonly public_key: string;
}

export interface SignedBossPayload {
  readonly version: 1;
  readonly purpose: 'hiboss.boss-message';
  readonly message_id: string;
  readonly issued_at: number;
  readonly boss_id: string;
  readonly action: {
    readonly kind: 'reply';
    readonly message_id: string;
  };
  readonly body: string;
}

export interface AuthenticatedBossMessage {
  readonly body: string;
  readonly idempotencyKey: string | null;
  readonly provenance: Record<string, unknown>;
}

export type BossMessageAuthResult =
  | { readonly ok: true; readonly value: AuthenticatedBossMessage }
  | { readonly ok: false; readonly status: 400 | 401; readonly error: string };
