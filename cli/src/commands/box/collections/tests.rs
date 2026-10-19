// Purpose: Collection resolution, formatting and older-server decoding regression tests.
// Depends on collection helpers and the shared Box item fixture.
use super::super::{output, tests::item};
use super::*;

pub(super) fn page() -> CollectionPage {
    serde_json::from_value(serde_json::json!({"collections": [{
        "id": "bc_one", "boss_id": "boss", "boss_name": "Boss Name", "name": "References",
        "item_count": 3, "cover_item_id": null, "created_at": "now", "updated_at": "now"
    }]}))
    .unwrap()
}

#[test]
fn resolves_case_insensitive_names_ids_and_duplicates_with_boss_scope() {
    let page = page();
    assert_eq!(
        resolve(&page, &["REFERENCES".into(), "bc_one".into()], Some("Boss Name")).unwrap(),
        ["bc_one"]
    );
    assert_eq!(
        resolve(&page, &["References".into()], Some("boss")).unwrap(),
        ["bc_one"]
    );
    assert!(resolve(&page, &["References".into()], Some("other")).is_err());
}

#[test]
fn unknown_name_lists_valid_names() {
    let error = resolve(&page(), &["missing".into()], None)
        .unwrap_err()
        .to_string();
    assert!(error.contains("Unknown collection missing"));
    assert!(error.contains("valid names: References"));
}

#[test]
fn ambiguous_name_lists_bosses_and_ids_but_id_wins() {
    let mut page = page();
    let mut other: Collection =
        serde_json::from_value(serde_json::to_value(&page.collections[0]).unwrap()).unwrap();
    other.id = "bc_two".into();
    other.boss_id = "other".into();
    other.boss_name = "Other Boss".into();
    page.collections.push(other);
    let error = resolve(&page, &["references".into()], None)
        .unwrap_err()
        .to_string();
    assert!(error.contains("Ambiguous"));
    assert!(error.contains("Boss Name, bc_one"));
    assert!(error.contains("Other Boss, bc_two"));
    assert_eq!(resolve(&page, &["bc_two".into()], None).unwrap(), ["bc_two"]);
    assert_eq!(
        resolve(&page, &["References".into()], Some("other")).unwrap(),
        ["bc_two"]
    );
}

#[test]
fn renders_counts_json_and_escaped_collection_names() {
    let mut page = page();
    page.collections[0].name = "References\nforged".into();
    let text = render(&page, false).unwrap();
    assert!(text.contains("bc_one  References\\nforged  3  boss: Boss Name (boss)"));
    assert_eq!(text.lines().count(), 1);
    let json: serde_json::Value = serde_json::from_str(&render(&page, true).unwrap()).unwrap();
    assert_eq!(json["collections"][0]["item_count"], 3);
}

#[test]
fn item_output_marks_likes_and_collection_names_on_metadata_line() {
    let mut item = item(false);
    item.liked = true;
    item.liked_at = Some("2026-01-01T00:00:00Z".into());
    item.collection_ids = vec!["bc_one".into(), "bc_unknown".into()];
    let text = output::render(&item, None, false, &page().collections).unwrap();
    assert!(text.lines().next().unwrap().contains('♥'));
    assert!(text.contains("boss: Boss Name (boss)  collections: References, bc_unknown"));
    let json: serde_json::Value =
        serde_json::from_str(&output::render(&item, None, true, &[]).unwrap()).unwrap();
    assert_eq!(json["liked"], true);
    assert_eq!(
        json["collection_ids"],
        serde_json::json!(["bc_one", "bc_unknown"])
    );
}

#[test]
fn absent_item_fields_default_for_older_servers() {
    let item = item(false);
    assert!(!item.liked);
    assert!(item.liked_at.is_none());
    assert!(item.collection_ids.is_empty());
    let text = output::render(&item, None, false, &[]).unwrap();
    assert!(!text.contains('♥'));
    assert!(!text.contains("collections:"));
}
