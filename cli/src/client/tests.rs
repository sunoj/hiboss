// Tests HTTP error rendering shared by the CLI client.
// Depends on the parent client error formatter and reqwest status codes.
use super::http_error;

#[test]
fn http_error_includes_non_empty_request_id() {
    let message = http_error(
        "request failed",
        reqwest::StatusCode::BAD_GATEWAY,
        Some("req-123".to_owned()),
        "bad gateway".to_owned(),
    );
    assert_eq!(
        message.to_string(),
        "request failed (502 Bad Gateway): bad gateway [req-id=req-123]"
    );
}

#[test]
fn http_error_omits_empty_request_id() {
    let message = http_error(
        "request failed",
        reqwest::StatusCode::BAD_GATEWAY,
        Some(String::new()),
        "bad gateway".to_owned(),
    );
    assert_eq!(message.to_string(), "request failed (502 Bad Gateway): bad gateway");
}
