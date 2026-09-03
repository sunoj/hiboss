// Server-owned provenance builders for native, provider, and system messages.
// Exports metadata composition without trusting client-supplied source labels.
// Depends on stored signing-key types only.

import type { StoredSigningKey } from './types';

interface BossActor {
  readonly id: string;
  readonly name: string;
}

export function signedApiMetadata(
  actor: BossActor,
  tokenId: string,
  key: StoredSigningKey,
  signedMessage: string,
): Record<string, unknown> {
  return addCompatibilityFields(actor, key.client_kind, {
    version: 1,
    source: key.client_kind,
    actor: { kind: 'boss', ...actor },
    authentication: { kind: 'device_signature', credential_id: tokenId },
    signature: {
      scheme: 'JWS-ES256',
      key_id: key.id,
      public_key: key.public_key,
      signed_message: signedMessage,
    },
  });
}

export function bearerApiMetadata(actor: BossActor, tokenId: string): Record<string, unknown> {
  return addCompatibilityFields(actor, 'api', {
    version: 1,
    source: 'api',
    actor: { kind: 'boss', ...actor },
    authentication: { kind: 'bearer_token', credential_id: tokenId },
    signature: { status: 'not_configured' },
  });
}

export function agentApiMetadata(agentId: string): Record<string, unknown> {
  return {
    source: 'api',
    provenance: {
      version: 1,
      source: 'api',
      actor: { kind: 'agent', id: agentId },
      authentication: { kind: 'api_key', credential_id: agentId },
      signature: { status: 'not_configured' },
    },
  };
}

export function channelMetadata(
  source: 'discord' | 'telegram',
  actor: BossActor | null,
  externalUserId?: string,
): Record<string, unknown> {
  const provenance = {
    version: 1,
    source,
    actor: actor ? { kind: 'boss', ...actor } : { kind: 'provider_user' },
    authentication: { kind: 'provider_account', credential_id: externalUserId ?? null },
    signature: { status: 'unsupported' },
  };
  return actor
    ? addCompatibilityFields(actor, source, provenance)
    : { source, provenance };
}

export function systemMetadata(base: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    ...base,
    source: 'system',
    provenance: {
      version: 1,
      source: 'system',
      actor: { kind: 'system' },
      authentication: { kind: 'system' },
      signature: { status: 'not_applicable' },
    },
  };
}

export function mergeProvenance(
  base: Record<string, unknown>,
  provenanceMetadata: Record<string, unknown>,
): Record<string, unknown> {
  return { ...base, ...provenanceMetadata };
}

function addCompatibilityFields(
  actor: BossActor,
  source: string,
  provenance: Record<string, unknown>,
): Record<string, unknown> {
  return {
    boss_id: actor.id,
    boss_name: actor.name,
    source,
    provenance,
  };
}
