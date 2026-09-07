/**
 * Bundled display-only chart leaf for the native panel seam.
 * Exports: no public module API; installs window.__hibossBridge.receive.
 * Dependencies: React, protocol.ts, and styles.css.
 */
import { useEffect, useLayoutEffect, useState, type Dispatch, type ReactElement, type SetStateAction } from "react";
import { createRoot } from "react-dom/client";
import { isHostMessage, sendViewMessage, type HostMessage, type JsonObject } from "./protocol";
import "./styles.css";

type MountState = { panelId: string; definition: JsonObject; chartHeight: number; sequence: number };

function numberProp(definition: JsonObject, key: string, fallback: number): number {
  const value = definition[key];
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function textProp(definition: JsonObject, key: string, fallback: string): string {
  const value = definition[key];
  return typeof value === "string" ? value : fallback;
}

function Chart({ mount }: { mount: MountState }): ReactElement {
  const values = mount.definition.values;
  const numbers = Array.isArray(values) ? values.filter((value): value is number => typeof value === "number" && Number.isFinite(value)) : [];
  useLayoutEffect(() => {
    requestAnimationFrame(() => sendViewMessage({ kind: "contentSizeChanged", panelId: mount.panelId, contentHeight: document.body.scrollHeight, observedSequence: mount.sequence, observedAtMs: performance.now() }));
  }, [mount]);
  return <figure className="panel-chart" style={{ height: `${mount.chartHeight}px` }} role="img" aria-label={`${textProp(mount.definition, "label", "Line chart")}: ${numbers.join(", ") || "No values"}`}>
    <figcaption>{textProp(mount.definition, "label", "Line chart")}</figcaption>
    <div className="chart-bars">{numbers.map((value, index) => <i key={`${index}-${value}`} style={{ height: `${Math.max(4, Math.min(100, value))}%` }} />)}</div>
    <p className="sr-only">Values: {numbers.join(", ") || "No values"}</p>
  </figure>;
}

function App(): ReactElement {
  const [mount, setMount] = useState<MountState | null>(null);
  useEffect(() => {
    window.__hibossBridge = { receive: (raw: unknown) => {
      if (!isHostMessage(raw)) { sendViewMessage({ kind: "renderFailed", panelId: "unknown", message: "Malformed host message" }); return; }
      applyHostMessage(raw, setMount);
    } };
    return () => { delete window.__hibossBridge; };
  }, []);
  return <main className="panel-root">{mount ? <Chart mount={mount} /> : <p>Waiting for a display mount.</p>}</main>;
}

function applyHostMessage(message: HostMessage, setMount: Dispatch<SetStateAction<MountState | null>>): void {
  if (message.kind === "mount") { setMount({ panelId: message.panelId, definition: message.definition, chartHeight: numberProp(message.state, "chartHeight", 240), sequence: message.sequence }); return; }
  setMount((current) => current && current.panelId === message.panelId ? { ...current, chartHeight: numberProp(message.state, "chartHeight", current.chartHeight), sequence: message.sequence } : current);
}

createRoot(document.getElementById("root") as HTMLElement).render(<App />);
