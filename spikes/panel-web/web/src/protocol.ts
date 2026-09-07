/**
 * Typed host/view bridge contracts for the panel renderer.
 * Exports: JSON values, host messages, view messages, and decoding helpers.
 * Dependencies: browser window messaging only.
 */
export type JsonPrimitive = null | boolean | number | string;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };

export type HostMessage =
  | { kind: "mount"; panelId: string; fixture: string; definition: JsonObject; state: JsonObject; appearance: "system" }
  | { kind: "applyTaskState"; panelId: string; sequence: number; state: JsonObject }
  | { kind: "requestStatus"; panelId: string; status: "open" | "replaced" | "resolved" };

export type ViewMessage =
  | { kind: "draftChanged"; panelId: string; changes: Array<{ path: string; value: JsonValue }> }
  | { kind: "actionRequested"; panelId: string; action: "submitRequest"; arguments: JsonObject }
  | { kind: "contentSizeChanged"; panelId: string; contentHeight: number; observedSequence: number; observedAtMs: number }
  | { kind: "renderFailed"; panelId: string; classification: "invalidSpec" | "unknownComponent" | "runtime"; message: string };

export type BridgeSender = (message: ViewMessage) => void;

export function isJsonObject(value: JsonValue | unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function isHostMessage(value: unknown): value is HostMessage {
  if (!isJsonObject(value) || typeof value.kind !== "string") return false;
  if (value.kind === "mount") return typeof value.panelId === "string" && typeof value.fixture === "string" && isJsonObject(value.definition) && isJsonObject(value.state);
  if (value.kind === "applyTaskState") return typeof value.panelId === "string" && typeof value.sequence === "number" && isJsonObject(value.state);
  return value.kind === "requestStatus" && typeof value.panelId === "string" && ["open", "replaced", "resolved"].includes(value.status as string);
}

export function sendViewMessage(sender: BridgeSender, message: ViewMessage): void {
  sender(message);
}
