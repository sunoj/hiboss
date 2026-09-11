// Runs production questionnaire command handlers against an isolated E2E Worker.
// Exports a test driver with explicit credentials, without changing CLI configuration.
// Dependencies: clap, tokio, and the hiboss request/client modules.

use clap::Parser;
use hiboss::{client::HiBossClient, commands::request};

#[derive(Parser)]
struct Arguments {
    #[arg(long)] server: String,
    #[arg(long)] key: String,
    #[command(flatten)] request: request::RequestArgs,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Arguments::parse();
    request::run(&args.request, &HiBossClient::new(&args.server, &args.key)).await
}
