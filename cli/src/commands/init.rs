// Purpose: Initialize the first API key by contacting the hiboss server.
// Exports InitArgs and run().
// Depends on clap, reqwest, and crate::config.

use crate::config::{save_config, Config};
use clap::Args;
use reqwest::{Client, StatusCode};
use serde::Deserialize;
use std::error::Error;

#[derive(Debug, Args)]
pub struct InitArgs {
  #[arg(value_name = "server")]
  pub server: String,
}

#[derive(Deserialize)]
struct BootstrapResponse {
  id: String,
  key: String,
}

pub async fn run(args: &InitArgs, config: &mut Config) -> Result<(), Box<dyn Error>> {
  let trimmed = args.server.trim_end_matches('/');
  let client = Client::new();
  let resp = client
    .post(format!("{}/api/bootstrap", trimmed))
    .send()
    .await?;

  if resp.status() == StatusCode::FORBIDDEN {
    println!("Server already initialized. Use hiboss config set key <key> to configure.");
    return Err("server already initialized".into());
  }
  if !resp.status().is_success() {
    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();
    return Err(format!("bootstrap failed ({}): {}", status, body).into());
  }

  let payload = resp.json::<BootstrapResponse>().await?;
  config.server = Some(trimmed.to_string());
  config.key = Some(payload.key.clone());
  save_config(config)?;
  println!("Initialized! Server: {}, Agent ID: {}", trimmed, payload.id);
  Ok(())
}
