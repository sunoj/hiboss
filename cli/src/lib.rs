// Purpose: Library root for hiboss CLI, exposing modules for testing.
// Exports: client, commands, config, sse, types modules.
// Dependencies: all CLI module dependencies.

pub mod client;
pub mod commands;
pub mod config;
pub mod helpers;
pub mod session;
pub mod sse;
pub mod team;
pub mod types;

#[cfg(test)]
mod tests;
