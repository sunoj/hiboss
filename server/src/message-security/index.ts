// Public API for boss message signing and source provenance.
// Exports parsing, verification, authentication, and metadata builders.
// Depends on focused modules within this feature directory.

export { authenticateBossReply } from './boss-message';
export { parseSigningRegistration, verifyPairingRegistration } from './crypto';
export {
  agentApiMetadata,
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
