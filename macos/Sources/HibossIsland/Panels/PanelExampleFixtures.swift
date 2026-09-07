// Source-owned copies of the five reference panel-runtime examples.
// Exports: PanelExampleFixtures.load().
// Dependencies: Foundation and PanelFixture.

import Foundation

enum PanelExampleFixtures {
    static func load() throws -> [PanelFixture] {
        try [
            PanelFixture(name: "download-progress.json", data: Data(downloadProgressJSON.utf8)),
            PanelFixture(name: "e2e-test-run.json", data: Data(e2eTestRunJSON.utf8)),
            PanelFixture(name: "benchmark-sweep.json", data: Data(benchmarkSweepJSON.utf8)),
            PanelFixture(name: "service-monitor.json", data: Data(serviceMonitorJSON.utf8)),
            PanelFixture(name: "research-intake.json", data: Data(researchIntakeJSON.utf8)),
        ]
    }

    private static let downloadProgressJSON = #"{"protocolVersion":1,"catalogId":"hiboss.panel","catalogVersion":1,"spec":{"root":"main","elements":{"main":{"type":"Stack","props":{"direction":"vertical","gap":16},"children":["stage","progress","throughput","details"]},"stage":{"type":"Status","props":{"label":"Stage","status":"active","message":"Downloading signed release artifacts"},"children":[]},"progress":{"type":"Progress","props":{"label":"Artifact transfer","value":{"$state":"/task/fraction"},"min":0,"max":1},"children":[]},"throughput":{"type":"LineChart","props":{"label":"Transfer throughput over the last 10 minutes","values":[142,156,171,null,184,179,191,188,196,202],"unit":"MB/s"},"children":[]},"details":{"type":"Grid","props":{"columns":3,"gap":12},"children":["downloaded","remaining","eta"]},"downloaded":{"type":"Metric","props":{"label":"Downloaded","value":{"$state":"/task/downloadedGiB"},"unit":"GiB"},"children":[]},"remaining":{"type":"Metric","props":{"label":"Remaining","value":{"$state":"/task/remainingGiB"},"unit":"GiB"},"children":[]},"eta":{"type":"Metric","props":{"label":"Estimated time left","value":{"$state":"/task/etaMinutes"},"unit":"min"},"children":[]}}},"stateSchema":{"type":"object","properties":{"task":{"type":"object","properties":{"stage":{"type":"string"},"fraction":{"type":"number","minimum":0,"maximum":1},"downloadedGiB":{"type":"number","minimum":0},"remainingGiB":{"type":"number","minimum":0},"etaMinutes":{"type":"number","minimum":0}},"required":["stage","fraction","downloadedGiB","remainingGiB","etaMinutes"],"additionalProperties":false}},"required":["task"],"additionalProperties":false},"initialState":{"task":{"stage":"Downloading signed release artifacts","fraction":0.68,"downloadedGiB":6.8,"remainingGiB":3.2,"etaMinutes":4.5}}}"#
    private static let e2eTestRunJSON = #"{"protocolVersion":1,"catalogId":"hiboss.panel","catalogVersion":1,"spec":{"root":"main","elements":{"main":{"type":"Stack","props":{"direction":"vertical","gap":16},"children":["stage","counts","tests"]},"stage":{"type":"Status","props":{"label":"Stage","status":"active","message":"Running checkout and recovery journeys"},"children":[]},"counts":{"type":"Grid","props":{"columns":4,"gap":10},"children":["passed","failed","running","total"]},"passed":{"type":"Metric","props":{"label":"Passed","value":{"$state":"/task/passed"}},"children":[]},"failed":{"type":"Metric","props":{"label":"Failed","value":{"$state":"/task/failed"}},"children":[]},"running":{"type":"Metric","props":{"label":"Running","value":{"$state":"/task/running"}},"children":[]},"total":{"type":"Metric","props":{"label":"Total","value":{"$state":"/task/total"}},"children":[]},"tests":{"type":"Table","props":{"label":"End-to-end test status","columns":[{"id":"test","label":"Test"},{"id":"status","label":"Status"},{"id":"duration","label":"Duration"}],"rows":[{"test":"Guest checkout","status":"passed","duration":"42s"},{"test":"Saved payment method","status":"passed","duration":"38s"},{"test":"Declined card recovery","status":"failed","duration":"19s"},{"test":"Refund confirmation","status":"running","duration":"—"}]},"children":[]}}},"stateSchema":{"type":"object","properties":{"task":{"type":"object","properties":{"stage":{"type":"string"},"passed":{"type":"integer","minimum":0},"failed":{"type":"integer","minimum":0},"running":{"type":"integer","minimum":0},"total":{"type":"integer","minimum":1}},"required":["stage","passed","failed","running","total"],"additionalProperties":false}},"required":["task"],"additionalProperties":false},"initialState":{"task":{"stage":"Running checkout and recovery journeys","passed":2,"failed":1,"running":1,"total":4}}}"#
    private static let benchmarkSweepJSON = #"{"protocolVersion":1,"catalogId":"hiboss.panel","catalogVersion":1,"spec":{"root":"main","elements":{"main":{"type":"Stack","props":{"direction":"vertical","gap":16},"children":["stage","summary","comparison"]},"stage":{"type":"Status","props":{"label":"Stage","status":"active","message":"Sweeping worker counts for the image pipeline"},"children":[]},"summary":{"type":"Grid","props":{"columns":3,"gap":12},"children":["best","latency","completed"]},"best":{"type":"Metric","props":{"label":"Best configuration","value":{"$state":"/task/bestConfiguration"}},"children":[]},"latency":{"type":"Metric","props":{"label":"Best median latency","value":{"$state":"/task/bestLatencyMs"},"unit":"ms"},"children":[]},"completed":{"type":"Metric","props":{"label":"Configurations tested","value":{"$state":"/task/completed"},"unit":"of 4"},"children":[]},"comparison":{"type":"BarChart","props":{"label":"Images processed per second — 1, 2, 4, and 8 workers","values":[1320,1485,1710,1642],"unit":"images/s"},"children":[]}}},"stateSchema":{"type":"object","properties":{"task":{"type":"object","properties":{"stage":{"type":"string"},"bestConfiguration":{"type":"string"},"bestLatencyMs":{"type":"number","minimum":0},"completed":{"type":"integer","minimum":0,"maximum":4}},"required":["stage","bestConfiguration","bestLatencyMs","completed"],"additionalProperties":false}},"required":["task"],"additionalProperties":false},"initialState":{"task":{"stage":"Sweeping worker counts for the image pipeline","bestConfiguration":"4 workers","bestLatencyMs":58.4,"completed":4}}}"#
    private static let serviceMonitorJSON = #"{"protocolVersion":1,"catalogId":"hiboss.panel","catalogVersion":1,"spec":{"root":"main","elements":{"main":{"type":"Stack","props":{"direction":"vertical","gap":16},"children":["stage","freshness","observed","trend"]},"stage":{"type":"Status","props":{"label":"Stage","status":"active","message":"Watching production image API"},"children":[]},"freshness":{"type":"Status","props":{"label":"Freshness","status":"success","message":"Updated 12 seconds ago"},"children":[]},"observed":{"type":"Grid","props":{"columns":3,"gap":12},"children":["duration","throughput","errors"]},"duration":{"type":"Metric","props":{"label":"Monitoring duration","value":{"$state":"/task/durationHours"},"unit":"hours"},"children":[]},"throughput":{"type":"Metric","props":{"label":"Requests observed","value":{"$state":"/task/requestsPerMinute"},"unit":"req/min"},"children":[]},"errors":{"type":"Metric","props":{"label":"Error rate","value":{"$state":"/task/errorRatePercent"},"unit":"%"},"children":[]},"trend":{"type":"LineChart","props":{"label":"Observed p95 latency over the last hour","values":[184,191,188,null,203,197,201,196,189,193],"unit":"ms"},"children":[]}}},"stateSchema":{"type":"object","properties":{"task":{"type":"object","properties":{"stage":{"type":"string"},"durationHours":{"type":"number","minimum":0},"requestsPerMinute":{"type":"number","minimum":0},"errorRatePercent":{"type":"number","minimum":0,"maximum":100}},"required":["stage","durationHours","requestsPerMinute","errorRatePercent"],"additionalProperties":false}},"required":["task"],"additionalProperties":false},"initialState":{"task":{"stage":"Watching production image API","durationHours":19.4,"requestsPerMinute":842.0,"errorRatePercent":0.18}}}"#

    private static let researchIntakeJSON = #"""
    {
      "title": "Research intake",
      "catalogId": "hiboss.panel",
      "catalogVersion": 1,
      "defaults": {
        "researchQuestion": "Which workflow reduces review time?",
        "background": "The team needs evidence for a focused tooling decision.",
        "evidenceTypes": ["literature-review"],
        "confidence": 0.6
      },
      "answerSchema": {
        "type": "object",
        "properties": {
          "researchQuestion": { "type": "string", "minLength": 1, "maxLength": 120 },
          "background": { "type": "string", "minLength": 20, "maxLength": 1200 },
          "evidenceTypes": {
            "type": "array",
            "items": { "type": "string", "enum": ["literature-review", "benchmarks", "interviews", "reproducibility"] },
            "minItems": 1,
            "uniqueItems": true
          },
          "confidence": { "type": "number", "minimum": 0, "maximum": 1 }
        },
        "required": ["researchQuestion", "background", "evidenceTypes", "confidence"],
        "additionalProperties": false
      },
      "formSpec": {
        "root": "form",
        "elements": {
          "form": { "type": "Stack", "props": { "direction": "vertical", "gap": 16 }, "children": ["intro", "question", "background", "evidence", "confidence", "submit"] },
          "intro": { "type": "Text", "props": { "text": "Shape the research brief before the first source is opened.", "tone": "muted" }, "children": [] },
          "question": { "type": "TextInput", "props": { "label": "Research question", "value": { "$bindState": "/form/researchQuestion" }, "placeholder": "What should this investigation explain?", "minLength": 1, "maxLength": 120 }, "children": [] },
          "background": { "type": "TextArea", "props": { "label": "Context and constraints", "value": { "$bindState": "/form/background" }, "placeholder": "Share the context, audience, and constraints.", "rows": 5, "minLength": 20, "maxLength": 1200 }, "children": [] },
          "evidence": { "type": "MultiSelect", "props": { "label": "Evidence to prioritize", "value": { "$bindState": "/form/evidenceTypes" }, "options": [{ "id": "literature-review", "label": "Literature review" }, { "id": "benchmarks", "label": "Benchmarks" }, { "id": "interviews", "label": "Interviews" }, { "id": "reproducibility", "label": "Reproducibility checks" }] }, "children": [] },
          "confidence": { "type": "Slider", "props": { "label": "Starting confidence", "value": { "$bindState": "/form/confidence" }, "min": 0, "max": 1, "step": 0.05 }, "children": [] },
          "submit": { "type": "Button", "props": { "label": "Submit research brief", "variant": "primary" }, "on": { "press": { "action": "submitRequest" } }, "children": [] }
        }
      }
    }
    """#
}
