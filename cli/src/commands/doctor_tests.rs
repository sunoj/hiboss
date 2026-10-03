// Purpose: Verify doctor never prints a credential prefix.
// Exports: key masking regression test.
// Dependencies: super::mask_key.

use super::mask_key;

#[test]
fn key_mask_never_shows_prefix() {
    assert_eq!(mask_key("hb_secret"), "...cret");
    assert_eq!(mask_key("key"), "...");
}
