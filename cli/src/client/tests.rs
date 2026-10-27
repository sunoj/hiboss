// Tests HTTP error rendering shared by the CLI client.
// Depends on the parent client error formatter and reqwest status codes.
use super::http_error;
use reqwest::StatusCode;

#[test]
fn http_error_includes_non_empty_request_id() {
    for (status, prefix, body, id, expected) in [
        (StatusCode::BAD_GATEWAY, "request failed", "bad gateway", "req-123",
         "request failed (502 Bad Gateway): bad gateway [req-id=req-123]"),
        (StatusCode::BAD_REQUEST, "upload failed", "bad\nbody", " ",
         "upload failed (400 Bad Request): bad\nbody [req-id= ]"),
        (StatusCode::NOT_FOUND, "lookup failed", "", "🦀",
         "lookup failed (404 Not Found):  [req-id=🦀]"),
    ] {
        let message = http_error(prefix, status, Some(id.to_owned()), body.to_owned());
        assert_eq!(message.to_string(), expected);
    }
}

#[test]
fn http_error_omits_empty_request_id() {
    for request_id in [None, Some(String::new())] {
        let message = http_error(
            "request failed", StatusCode::BAD_GATEWAY, request_id, "bad gateway".to_owned(),
        );
        assert_eq!(message.to_string(), "request failed (502 Bad Gateway): bad gateway");
    }
}

#[test]
fn shared_requests_preserve_methods_urls_headers_and_json() {
    let client = super::HiBossClient::new("https://example.test/base/", "fixture-key");
    for method in [reqwest::Method::GET, reqwest::Method::POST, reqwest::Method::DELETE] {
        let request = client.request(method.clone(), "/api/groups/group-one")
            .query(&[("search", "a & b")])
            .json(&serde_json::json!({"body": "message"}))
            .build().unwrap();
        assert_eq!(request.method(), method);
        assert_eq!(request.url().as_str(), "https://example.test/base/api/groups/group-one?search=a+%26+b");
        assert_eq!(request.headers()["authorization"], "Bearer fixture-key");
        assert_eq!(request.headers()["content-type"], "application/json");
        let body = request.body().unwrap().as_bytes().unwrap();
        assert_eq!(serde_json::from_slice::<serde_json::Value>(body).unwrap(),
                   serde_json::json!({"body": "message"}));
    }
}
