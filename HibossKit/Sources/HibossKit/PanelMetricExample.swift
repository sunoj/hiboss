// Three budget metrics and a table for native panel layout previews.
// Exports PanelMetricExample.load, shared by demo services and render tests.
// Dependencies: Foundation and PanelFixture.

import Foundation

public enum PanelMetricExample {
    public static func load() throws -> PanelFixture {
        try PanelFixture(name: "metric-layout", data: Data(json.utf8))
    }

    private static let json = """
    {"title":"Mae Hia house · work in progress","initialState":{"task":{}},
     "spec":{"root":"main","elements":{
      "main":{"type":"Stack","props":{},"children":["metrics","work"]},
      "metrics":{"type":"Grid","props":{"columns":3},
       "children":["construction","house","systems"]},
      "construction":{"type":"Metric","props":{"label":"Construction P50",
       "value":"8,438,950","unit":"THB"},"children":[]},
      "house":{"type":"Metric","props":{"label":"House P50 (target)",
       "value":"4,554,994","unit":"THB"},"children":[]},
      "systems":{"type":"Metric","props":{"label":"Systems P50",
       "value":"1,068,560","unit":"THB"},"children":[]},
      "work":{"type":"Table","props":{"label":"Work items",
       "columns":[{"id":"item","label":"Item"},{"id":"status","label":"Status"}],
       "rows":[{"item":"Foundation","status":"Running"}]},"children":[]}}}}
    """
}
