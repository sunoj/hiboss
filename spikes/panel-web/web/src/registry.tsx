/**
 * HiBoss catalog and bundled component implementations.
 * Exports: the typed registry used by @json-render/react.
 * Dependencies: React, Zod, and pinned json-render packages.
 */
import type { ReactNode } from "react";
import { defineCatalog } from "@json-render/core";
import { BaseComponentProps, defineRegistry, useBoundProp } from "@json-render/react";
import { schema } from "@json-render/react/schema";
import { z } from "zod";

type PanelProps = Record<string, unknown>;
type PanelContext = BaseComponentProps<PanelProps>;

const props = z.record(z.string(), z.unknown());
const catalog = defineCatalog(schema, {
  components: {
    Stack: { props, slots: ["default"], description: "Vertical or horizontal layout" },
    Grid: { props, slots: ["default"], description: "Grid layout" },
    Section: { props, slots: ["default"], description: "Labeled section" },
    Text: { props, description: "Accessible text" },
    Metric: { props, description: "Labeled metric" },
    Progress: { props, description: "Progress indicator" },
    Status: { props, description: "Status label" },
    Table: { props, description: "Tabular data" },
    LineChart: { props, description: "Line chart with text alternative" },
    BarChart: { props, description: "Bar chart with text alternative" },
    TextInput: { props, description: "Single-line text input" },
    TextArea: { props, description: "Multiline text input" },
    NumberInput: { props, description: "Numeric input" },
    Select: { props, description: "Single selection input" },
    MultiSelect: { props, description: "Multiple selection input" },
    Toggle: { props, description: "Boolean input" },
    Slider: { props, description: "Bounded numeric input" },
    Button: { props, description: "Registered action button" },
  },
  actions: { submitRequest: { params: z.object({}), description: "Request host-owned submission" } },
});

function textProp(context: PanelProps, key: string, fallback = ""): string {
  const value = context[key];
  return typeof value === "string" ? value : fallback;
}

function numberProp(context: PanelProps, key: string, fallback = 0): number {
  const value = context[key];
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function layout({ props: input, children }: PanelContext): ReactNode {
  const direction = textProp(input, "direction", "vertical");
  return <div className={`panel-stack panel-stack-${direction}`}>{children}</div>;
}

function section({ props: input, children }: PanelContext): ReactNode {
  return <section className="panel-section"><h2>{textProp(input, "title", "Section")}</h2>{children}</section>;
}

function metric({ props: input }: PanelContext): ReactNode {
  return <div className="panel-metric"><span>{textProp(input, "label", "Metric")}</span><strong>{String(input.value ?? "—")}</strong></div>;
}

function text({ props: input }: PanelContext): ReactNode {
  return <p>{textProp(input, "value", textProp(input, "text"))}</p>;
}

function inputField({ props: input, bindings, children }: PanelContext): ReactNode {
  const [value, setValue] = useBoundProp(input.value, bindings?.value);
  const label = textProp(input, "label", "Value");
  return <label className="panel-field">{label}<input value={String(value ?? "")} onChange={(event) => setValue(event.target.value)} />{children}</label>;
}

function numberInput({ props: input, bindings }: PanelContext): ReactNode {
  const [value, setValue] = useBoundProp(input.value, bindings?.value);
  const label = textProp(input, "label", "Number");
  return <label className="panel-field">{label}<input type="number" min={numberProp(input, "min", 0)} max={numberProp(input, "max", 100)} value={String(value ?? "")} onChange={(event) => setValue(Number(event.target.value))} /></label>;
}

function select({ props: input, bindings }: PanelContext): ReactNode {
  const [value, setValue] = useBoundProp(input.value, bindings?.value);
  const options = Array.isArray(input.options) ? input.options.filter((option): option is PanelProps => typeof option === "object" && option !== null && !Array.isArray(option)) : [];
  return <label className="panel-field">{textProp(input, "label", "Select")}<select value={String(value ?? "")} onChange={(event) => setValue(event.target.value)}>{options.map((option) => <option key={textProp(option, "id")} value={textProp(option, "id")}>{textProp(option, "label")}</option>)}</select></label>;
}

function button({ props: input, emit }: PanelContext): ReactNode {
  return <button type="button" onClick={() => emit("press")}>{textProp(input, "label", "Continue")}</button>;
}

function chart({ props: input }: PanelContext): ReactNode {
  const label = textProp(input, "label", "Chart");
  const values = Array.isArray(input.values) ? input.values.filter((value): value is number => typeof value === "number" && Number.isFinite(value)) : [];
  return <figure className="panel-chart" role="img" aria-label={`${label}: ${values.join(", ") || "No values"}`}><figcaption>{label}</figcaption><div className="chart-bars">{values.map((value, index) => <i key={`${index}-${value}`} style={{ height: `${Math.max(4, Math.min(100, value))}%` }} />)}</div><p className="sr-only">Values: {values.join(", ") || "No values"}</p></figure>;
}

export const { registry } = defineRegistry(catalog, {
  components: {
    Stack: layout, Grid: layout, Section: section, Text: text, Metric: metric,
    Progress: metric, Status: text, Table: text, LineChart: chart, BarChart: chart,
    TextInput: inputField, TextArea: inputField, NumberInput: numberInput, Select: select,
    MultiSelect: select, Toggle: inputField, Slider: numberInput, Button: button,
  },
  actions: { submitRequest: async () => undefined },
});
