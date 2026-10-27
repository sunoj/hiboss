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
