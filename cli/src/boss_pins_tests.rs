// Verification against pinned boss keys: the pinned bytes rule, unknown and revoked keys are refused
// once this machine pins anything, and the key text round-trips. Uses the shared signed fixture.

use crate::boss_key_text::{parse, render, BossKeyText};
use crate::boss_pins::{tests_support::set_pins, BossPins, PinnedKey};
use crate::message_security::verify_message;
use crate::message_security_tests::signed_message_for_pins;

fn key_of(message: &crate::types::Message) -> (String, String) {
    let signature = &message.metadata.as_ref().unwrap()["provenance"]["signature"];
    (signature["key_id"].as_str().unwrap().to_owned(), signature["public_key"].as_str().unwrap().to_owned())
}

fn pins(key_id: &str, public_key: &str) -> BossPins {
    let mut pins = BossPins::new("boss-1", None);
    pins.pin(PinnedKey { key_id: key_id.to_owned(), public_key: public_key.to_owned(), client_kind: "ios".to_owned(),
        label: None, via: "manual".to_owned(), pinned_at: "2026-11-28T00:00:00Z".to_owned() });
    pins
}

#[test]
fn a_pinned_key_verifies_and_an_unpinned_one_is_refused_once_anything_is_pinned() {
    let message = signed_message_for_pins();
    let (key_id, public_key) = key_of(&message);
    set_pins(Some(vec![pins(&key_id, &public_key)]));
    assert!(verify_message(&message).is_ok(), "signed by the pinned key");
    let other = signed_message_for_pins();
    let error = verify_message(&other).expect_err("a fresh key the server could have minted");
    assert!(error.to_string().contains("not pinned"), "{error}");
    set_pins(None);
    assert!(verify_message(&other).is_ok(), "no pins yet: the offered key is still used");
}

#[test]
fn a_revoked_key_is_refused_whatever_time_its_signature_claims() {
    let message = signed_message_for_pins();
    let (key_id, public_key) = key_of(&message);
    let mut revoked = pins(&key_id, &public_key);
    revoked.revoke(&key_id, "2026-11-28 00:00:00");
    set_pins(Some(vec![revoked]));
    assert!(verify_message(&message).expect_err("revoked").to_string().contains("revoked"));
    set_pins(None);
}

#[test]
fn a_damaged_pin_store_never_falls_back_to_the_offered_key() {
    set_pins(Some(Vec::new()));
    crate::boss_pins::tests_support::set_damaged(true);
    let error = verify_message(&signed_message_for_pins()).expect_err("unreadable pins count as pinned");
    assert!(error.to_string().contains("not pinned"), "{error}");
    crate::boss_pins::tests_support::set_damaged(false);
    set_pins(None);
}

#[test]
fn key_text_round_trips_and_rejects_a_mismatched_key_id() {
    let message = signed_message_for_pins();
    let (key_id, public_key) = key_of(&message);
    let key = BossKeyText { boss_id: "boss-1".into(), key_id: key_id.clone(), public_key: public_key.clone(),
        client_kind: "ios".into(), label: Some("Ming's iPhone".into()) };
    assert_eq!(parse(&render(&key)).unwrap(), key);
    let forged = BossKeyText { key_id: "AAAA".into(), ..key };
    assert!(parse(&render(&forged)).is_err());
    assert!(parse("hiboss-boss-key:not-json").is_err());
}
