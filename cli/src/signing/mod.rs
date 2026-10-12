// Purpose: Agent message signing — local P-256 keys, enrollment, and signed request bodies.
// Exports: AgentSigner, enroll, load_signer, remove_signer, sign_send, sign_action, encode.
// Dependencies: ring, serde_json, reqwest; see docs/agent-message-signing.md.

mod enroll;
mod jws;
mod payload;
mod store;
#[cfg(test)]
mod tests;

pub use enroll::{Enrollment, enroll};
pub use jws::encode;
pub use payload::{sign_action, sign_send};
pub use store::{AgentSigner, key_file, load_signer, remove_signer};
