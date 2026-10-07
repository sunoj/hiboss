// Purpose: Library root for hiboss CLI, exposing modules for testing.
// Exports: client, commands, config, help, sse, types modules.
// Dependencies: all CLI module dependencies.

pub mod attribution;
pub mod box_types;
pub mod client;
pub mod commands;
pub mod config;
pub mod help;
pub mod helpers;
pub mod hiboss_dir;
pub mod message_security;
pub mod runtime;
pub mod session;
pub mod sse;
pub mod team;
pub mod types;

#[cfg(test)]
mod tests;
#[cfg(test)]
mod message_security_tests;
