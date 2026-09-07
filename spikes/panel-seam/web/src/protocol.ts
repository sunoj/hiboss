/**
 * Typed display-only host/view bridge contracts for the seam renderer.
 * Exports: JSON values, host messages, view messages, and guards.
 * Dependencies: browser window messaging only.
 */
export type JsonPrimitive = null | boolean | number | string;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };

export type HostMessage =
  | { kind: "mount"; panelId: string; definition: JsonObject; state: JsonObject; sequence: number }
  | { kind: "applyTaskState"; panelId: string; state: JsonObject; sequence: number };

export type ViewMessage =
  | { kind: "contentSizeChanged"; panelId: string; contentHeight: number; observedSequence: number; observedAtMs: number }
  | { kind: "renderFailed"; panelId: string; message: string };

export function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function isHostMessage(value: unknown): value is HostMessage {
  if (!isJsonObject(value) || typeof value.kind !== "string" || typeof value.panelId !== "string" || typeof value.sequence !== "number") return false;
  if (value.kind === "mount") return isJsonObject(value.definition) && isJsonObject(value.state);
  return value.kind === "applyTaskState" && isJsonObject(value.state);
}

export function sendViewMessage(message: ViewMessage): void {
  window.webkit?.messageHandlers?.hiboss?.postMessage(message);
}

declare global {
  interface Window {
    __hibossBridge?: { receive: (message: unknown) => void };
    webkit?: { messageHandlers?: { hiboss?: { postMessage: (message: ViewMessage) => void } } };
  }
}
