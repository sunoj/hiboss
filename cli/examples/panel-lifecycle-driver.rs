// Runs the actual panel CLI handlers against an explicitly selected test server.
// Exports an isolated integration driver without changing the user's CLI config.
// Dependencies: clap, tokio, and the hiboss library command/client modules.

use hiboss::commands::SubcommandArgs;
use clap::Parser;
use hiboss::{client::HiBossClient, commands::panel};

#[derive(Parser)]
struct Arguments {
    #[arg(long)]
    server: String,
    #[arg(long)]
    key: String,
    #[command(flatten)]
    panel: SubcommandArgs<panel::PanelCommand>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Arguments::parse();
    panel::run(&args.panel, &HiBossClient::new(&args.server, &args.key)).await
}
