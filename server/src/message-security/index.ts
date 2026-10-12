// Public API for boss and agent message signing and source provenance.
// Exports parsing, verification, authentication, and metadata builders.
// Depends on focused modules within this feature directory.

export { authenticateBossReply } from './boss-message';
export { actionContent, audienceOf, authenticateAgentMessage, signedIdempotencyKey } from './agent-message';
export type { AgentAction, AgentAudience, SignedAgentContent } from './agent-message';
export {
  agentRequiresSignature, enrollAgentSigningKey, listLiveAgentKeys, listUnresetAgentKeys, revokeAgentSigningKey,
} from './agent-keys';
export type { AgentSigningKey } from './agent-keys';
export { stripServerOwnedMetadata } from './metadata';
export { parseSigningRegistration, verifyPairingRegistration, verifySigninRegistration } from './crypto';
export {
  agentApiMetadata,
  agentBearerProvenance,
  agentSignedProvenance,
  bearerApiMetadata,
  channelMetadata,
  mergeProvenance,
  signedApiMetadata,
  systemMetadata,
} from './provenance';
export type {
  RegisteredSigningKey,
  SigningClientKind,
  SigningKeyId,
  SigningRegistration,
} from './types';
