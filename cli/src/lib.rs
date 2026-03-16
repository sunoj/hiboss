// Purpose: Library root for hiboss CLI, exposing modules for testing.
// Exports: client, commands, config, sse, types modules.
// Dependencies: all CLI module dependencies.

pub mod client;
pub mod commands;
pub mod config;
pub mod sse;
pub mod types;
pub mod helpers;

#[cfg(test)]
mod tests;
