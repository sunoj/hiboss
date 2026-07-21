// Purpose: Aggregate hiboss CLI command modules for easier imports.
// Exports: submodules for send, ask, inbox, read, reply, status, config.
// Dependencies: none beyond the command modules themselves.

pub mod agent;
pub mod ask;
pub mod boss;
pub mod bot;
pub mod channel;
pub mod config;
pub mod daemon;
pub mod doctor;
pub mod edit;
pub mod forward;
pub mod group;
pub mod hook;
pub(crate) mod hook_helpers;
pub mod inbox;
pub mod init;
pub mod react;
pub mod read;
pub mod reply;
pub mod route;
pub mod send;
pub mod setup;
pub mod setup_hooks;
pub mod ss;
pub mod status;
pub mod watch;
