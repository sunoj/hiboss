// Purpose: Ship publication examples for agents outside this repository.
// Exports: render, returning the example list or a fixture's original JSON.
// Dependencies: compile-time panel-runtime fixtures and the publication validator in tests.

use std::error::Error;

const EXAMPLES: [(&str, &str, &str); 4] = [
    ("download-progress", "Known-total transfer with progress and throughput", include_str!("../../../../../panel-runtime/fixtures/examples/download-progress.json")),
    ("e2e-test-run", "Test counts and per-test outcomes in a table", include_str!("../../../../../panel-runtime/fixtures/examples/e2e-test-run.json")),
    ("benchmark-sweep", "Bounded sweep with winner metrics and a bar chart", include_str!("../../../../../panel-runtime/fixtures/examples/benchmark-sweep.json")),
    ("service-monitor", "Continuous health and observations without completion", include_str!("../../../../../panel-runtime/fixtures/examples/service-monitor.json")),
];

pub fn render(name: Option<&str>) -> Result<String, Box<dyn Error>> {
    let Some(name) = name else {
        return Ok(EXAMPLES.iter().map(|(name, description, _)| format!("{name}: {description}\n")).collect());
    };
    let (_, _, document) = EXAMPLES.iter().find(|(candidate, _, _)| *candidate == name)
        .ok_or_else(|| format!("unknown panel example \"{name}\"; list names with `hiboss panel example`"))?;
    Ok((*document).to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_descriptions_and_rejects_unknown_names() {
        let listing = render(None).expect("example list");
        assert_eq!(listing.lines().count(), EXAMPLES.len());
        for (name, description, _) in EXAMPLES {
            assert!(listing.contains(&format!("{name}: {description}\n")));
        }
        assert!(render(Some("unknown")).expect_err("unknown name").to_string().contains("hiboss panel example"));
    }

    #[test]
    fn every_embedded_example_validates_with_publication_identities() {
        for (name, _, document) in EXAMPLES {
            assert_eq!(render(Some(name)).expect("export"), document);
            let mut value: serde_json::Value = serde_json::from_str(document).expect("fixture JSON");
            for (key, identity) in [("taskKey", "example-test"), ("sessionId", "session_test"), ("targetBossId", "boss_test")] {
                value[key] = serde_json::json!(identity);
            }
            assert_eq!(super::super::validation::validate_publication(&value), Ok(()), "{name}");
        }
    }

    #[test]
    fn guide_download_and_full_series_update_validate() {
        let guide = crate::commands::setup_agents::PANEL_GUIDE;
        assert!(guide.lines().count() <= 300);
        let document = guide.split("```json\n").nth(1).expect("worked JSON").split("```").next().expect("JSON end");
        let mut value: serde_json::Value = serde_json::from_str(document).expect("download JSON");
        assert_eq!(super::super::validation::validate_publication(&value), Ok(()));
        assert_eq!(value["spec"]["elements"]["throughput"]["props"]["values"]["$state"], "/task/rateSeries");
        let initial = value["initialState"]["task"]["rateSeries"].as_array().expect("series").clone();
        assert!(initial.iter().any(serde_json::Value::is_null));
        let update = guide.lines().find_map(|line| line.strip_prefix("hiboss panel update PANEL_ID '")).expect("update");
        let update: serde_json::Value = serde_json::from_str(update.trim_end_matches('\'')).expect("update JSON");
        let series = update["rateSeries"].as_array().expect("updated series");
        assert_eq!(&series[..initial.len()], initial.as_slice());
        assert_eq!(series.len(), initial.len() + 1);
        assert!(update["fraction"].as_f64() > value["initialState"]["task"]["fraction"].as_f64());
        for (key, observation) in update.as_object().expect("task update") {
            value["initialState"]["task"][key] = observation.clone();
        }
        assert_eq!(super::super::validation::validate_publication(&value), Ok(()));
    }
}
