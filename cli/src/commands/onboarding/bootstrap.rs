// Creates the first boss and renders the short-lived app pairing information.
// Uses bounded HTTP and terminal QR rendering; bootstrap credentials are never displayed.
use super::{SetupArgs, api};
use qrcode::{Color, QrCode};
use serde::Deserialize;
use std::{
    error::Error,
    io::{self, IsTerminal, Write},
};

#[derive(Deserialize)]
struct Pairing {
    code: String,
    expires_at: String,
}

pub(super) async fn pair_boss(server: &str, args: &SetupArgs) -> Result<(), Box<dyn Error>> {
    let Some(secret) = args
        .bootstrap_secret
        .clone()
        .or_else(|| std::env::var("HIBOSS_BOOTSTRAP_SECRET").ok())
    else {
        return Ok(());
    };
    let name = boss_name(args)?;
    let response = api::http()?
        .post(format!("{server}/api/bootstrap/boss"))
        .header("X-Bootstrap-Secret", &secret)
        .json(&serde_json::json!({ "name": name }))
        .send()
        .await
        .map_err(|_| "Boss bootstrap request failed")?;
    if response.status() == reqwest::StatusCode::CONFLICT {
        return Ok(());
    }
    if !response.status().is_success() {
        return Err(format!("Boss bootstrap failed ({})", response.status()).into());
    }
    let pairing: Pairing = response
        .json()
        .await
        .map_err(|_| "Invalid boss pairing response")?;
    show_pairing(server, &pairing, &secret)
}

fn show_pairing(server: &str, pairing: &Pairing, secret: &str) -> Result<(), Box<dyn Error>> {
    if pairing.code.is_empty()
        || pairing.code.len() > 128
        || !pairing
            .code
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"_-".contains(&byte))
        || pairing.code.contains(secret)
        || pairing.expires_at.contains(secret)
        || time::OffsetDateTime::parse(
            &pairing.expires_at,
            &time::format_description::well_known::Rfc3339,
        )
        .is_err()
    {
        return Err("Invalid boss pairing response".into());
    }
    let mut link = reqwest::Url::parse("hiboss://pair")?;
    link.query_pairs_mut()
        .append_pair("server", server)
        .append_pair("code", &pairing.code);
    let link = link.as_str();
    let qr = QrCode::new(link.as_bytes()).map_err(|_| "Cannot render boss pairing QR")?;
    println!("{link}");
    print_qr(&qr);
    println!(
        "Pairing code: {}\nExpires: {}",
        pairing.code, pairing.expires_at
    );
    println!(
        "Scan with the HiBoss iPhone app, or open HiBoss on the Mac and choose Pair with code."
    );
    io::stdout().flush()?;
    Ok(())
}

fn print_qr(qr: &QrCode) {
    for y in -4..qr.width() as isize + 4 {
        let mut line = String::new();
        for x in -4..qr.width() as isize + 4 {
            let dark = x >= 0
                && y >= 0
                && x < qr.width() as isize
                && y < qr.width() as isize
                && qr[(x as usize, y as usize)] == Color::Dark;
            line.push_str(if dark { "  " } else { "██" });
        }
        println!("{line}");
    }
}

fn boss_name(args: &SetupArgs) -> Result<String, Box<dyn Error>> {
    if let Some(name) = &args.boss_name {
        return Ok(name.clone());
    }
    let default = std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .ok()
        .filter(|name| !name.trim().is_empty())
        .or_else(|| {
            std::process::Command::new("id")
                .arg("-un")
                .output()
                .ok()
                .filter(|output| output.status.success())
                .and_then(|output| String::from_utf8(output.stdout).ok())
                .map(|name| name.trim().to_owned())
        })
        .ok_or("Cannot determine login name; pass --boss-name")?;
    if !io::stdin().is_terminal() {
        return Ok(default);
    }
    eprint!("Boss name [{default}]: ");
    io::stderr().flush()?;
    let mut name = String::new();
    io::stdin().read_line(&mut name)?;
    Ok(if name.trim().is_empty() {
        default
    } else {
        name.trim().to_owned()
    })
}
