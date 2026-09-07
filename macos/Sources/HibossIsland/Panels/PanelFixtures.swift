// Source-owned copies of the two approved panel-runtime fixtures for the demo surface.
// Exports: PanelFixtures.load() and PanelFixtureSet.
// Dependencies: Foundation Data/JSONDecoder and PanelFixture models.

import Foundation

struct PanelFixtureSet: Sendable {
    let mixed: PanelFixture
    let metric: PanelFixture
}

enum PanelFixtures {
    static func load() throws -> PanelFixtureSet {
        PanelFixtureSet(
            mixed: try PanelFixture(name: "mixed-panel.json", data: Data(mixedJSON.utf8)),
            metric: try PanelFixture(name: "metric-panel.json", data: Data(metricJSON.utf8))
        )
    }

    private static let mixedJSON = #"""
    {
      "kind": "decision",
      "title": "Choose the test rollout",
      "blocking": true,
      "priority": "normal",
      "catalogId": "hiboss.panel",
      "catalogVersion": 1,
      "defaults": { "strategy": "canary", "trafficPercent": 10 },
      "answerSchema": {
        "type": "object",
        "properties": {
          "strategy": { "type": "string", "enum": ["canary", "full"] },
          "trafficPercent": { "type": "integer", "minimum": 1, "maximum": 100 }
        },
        "required": ["strategy", "trafficPercent"],
        "additionalProperties": false
      },
      "formSpec": {
        "root": "form",
        "elements": {
          "form": { "type": "Stack", "props": { "direction": "vertical", "gap": 18 }, "children": ["strategy", "chart", "traffic", "submit"] },
          "strategy": { "type": "Select", "props": { "label": "Strategy", "value": { "$bindState": "/form/strategy" }, "options": [{ "id": "canary", "label": "Canary" }, { "id": "full", "label": "Full rollout" }] }, "children": [] },
          "chart": { "type": "LineChart", "props": { "label": "Observed rollout health", "values": [28, 42, 36, null, 54, 66, 61, 74, 82, 78], "unit": "%" }, "children": [] },
          "traffic": { "type": "NumberInput", "props": { "label": "Traffic percentage", "value": { "$bindState": "/form/trafficPercent" }, "min": 1, "max": 100, "step": 1 }, "children": [] },
          "submit": { "type": "Button", "props": { "label": "Submit selection", "variant": "primary" }, "on": { "press": { "action": "submitRequest" } }, "children": [] }
        }
      }
    }
    """#

    private static let metricJSON = #"""
    {
      "protocolVersion": 1,
      "catalogId": "hiboss.panel",
      "catalogVersion": 1,
      "spec": {
        "root": "main",
        "elements": {
          "main": { "type": "Stack", "props": { "direction": "vertical" }, "children": ["completed"] },
          "completed": { "type": "Metric", "props": { "label": "Completed tests", "value": { "$state": "/task/completed" } }, "children": [] }
        }
      },
      "stateSchema": { "type": "object", "properties": { "task": { "type": "object", "properties": { "completed": { "type": "integer", "minimum": 0 }, "label": { "type": "string" } }, "required": ["completed"], "additionalProperties": false } }, "required": ["task"], "additionalProperties": false },
      "initialState": { "task": { "completed": 0, "label": "Preparing" } }
    }
    """#
}
