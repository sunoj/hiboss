/**
 * Offline React entry point and typed WKWebView bridge adapter.
 * Exports: no public module API; installs window.__hibossBridge.receive.
 * Dependencies: React, json-render React, registry.tsx, and protocol.ts.
 */
import { useEffect, useLayoutEffect, useState, type Dispatch, type ReactElement, type SetStateAction } from "react";
import { createRoot } from "react-dom/client";
import { createStateStore, JSONUIProvider, Renderer, type Spec, type StateStore } from "@json-render/react";
import { registry } from "./registry";
import { isHostMessage, type HostMessage, type JsonObject, type JsonValue, sendViewMessage, type ViewMessage } from "./protocol";
import "./styles.css";

type PanelDefinition = JsonObject & { spec?: JsonValue; formSpec?: JsonValue };
type MountState = { panelId: string; fixture: string; definition: PanelDefinition; store: StateStore; sequence: number };

declare global { interface Window { __hibossBridge?: { receive: (message: unknown) => void }; webkit?: { messageHandlers?: { hiboss?: { postMessage: (message: ViewMessage) => void } } } } }

const sender = (message: ViewMessage): void => window.webkit?.messageHandlers?.hiboss?.postMessage(message);

function toSpec(value: JsonValue | undefined): Spec | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  return value as unknown as Spec;
}

function draftChanges(state: JsonObject): Array<{ path: string; value: JsonValue }> {
  const form = state.form;
  if (typeof form !== "object" || form === null || Array.isArray(form)) return [];
  return Object.entries(form).filter(([path]) => path === "strategy" || path === "trafficPercent").map(([path, value]) => ({ path: `/form/${path}`, value }));
}

function PanelView({ mount }: { mount: MountState }): ReactElement {
  const [renderTick, setRenderTick] = useState(0);
  useEffect(() => mount.store.subscribe(() => {
    const current = mount.store.getSnapshot() as JsonObject;
    const changes = draftChanges(current);
    if (changes.length > 0) sendViewMessage(sender, { kind: "draftChanged", panelId: mount.panelId, changes });
    setRenderTick((value) => value + 1);
  }), [mount]);
  useLayoutEffect(() => {
    requestAnimationFrame(() => sendViewMessage(sender, { kind: "contentSizeChanged", panelId: mount.panelId, contentHeight: Math.min(2000, Math.max(48, document.body.scrollHeight)), observedSequence: mount.sequence, observedAtMs: performance.now() }));
  }, [mount, renderTick]);
  const spec = toSpec(mount.definition.spec ?? mount.definition.formSpec);
  if (!spec) return <p role="alert">This panel has no renderable specification.</p>;
  const handlers = { submitRequest: async (_arguments: Record<string, unknown>): Promise<void> => sendViewMessage(sender, { kind: "actionRequested", panelId: mount.panelId, action: "submitRequest", arguments: {} }) };
  return <JSONUIProvider registry={registry} store={mount.store} handlers={handlers}><Renderer spec={spec} registry={registry} /></JSONUIProvider>;
}

function App(): ReactElement {
  const [mount, setMount] = useState<MountState | null>(null);
  useEffect(() => {
    window.__hibossBridge = { receive: (message: unknown) => {
      if (!isHostMessage(message)) { sendViewMessage(sender, { kind: "renderFailed", panelId: "unknown", classification: "runtime", message: "Malformed host message" }); return; }
      handleHostMessage(message, setMount);
    } };
    return () => { delete window.__hibossBridge; };
  }, []);
  return <div className="panel-root">{mount ? <PanelView mount={mount} /> : <p>Waiting for a panel mount.</p>}</div>;
}

function handleHostMessage(message: HostMessage, setMount: Dispatch<SetStateAction<MountState | null>>): void {
  if (message.kind === "mount") { setMount({ panelId: message.panelId, fixture: message.fixture, definition: message.definition, store: createStateStore(message.state), sequence: 0 }); return; }
  setMount((current) => {
    if (!current || current.panelId !== message.panelId) return current;
    if (message.kind === "applyTaskState") { const task = message.state.task; if (task !== undefined) current.store.set("/task", task); return { ...current, sequence: message.sequence }; }
    return current;
  });
}

createRoot(document.getElementById("root") as HTMLElement).render(<App />);
