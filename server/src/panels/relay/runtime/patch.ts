// Applies bounded JSON Pointer patches without prototype or array-path ambiguity.
// Exports applyTaskPatch; validation runs against the complete candidate afterward.
// Dependencies: definition JSON types and lifecycle faults.

import { isJsonValue, isRecord } from '../../definition/helpers';
import type { JsonValue } from '../../definition/types';
import { PanelFault } from '../../lifecycle/types';

export function applyTaskPatch(task: JsonValue, value: unknown): JsonValue {
  if (!Array.isArray(value) || value.length > 128) throw new PanelFault('invalid_state', 422);
  let root: JsonValue = structuredClone({ task });
  for (const operation of value) {
    if (!isRecord(operation) || !['add', 'replace', 'remove'].includes(String(operation.op)) || typeof operation.path !== 'string'
      || !(operation.path === '/task' || operation.path.startsWith('/task/'))) throw new PanelFault('invalid_state', 422);
    if (Object.keys(operation).some(k => !['op', 'path', 'value'].includes(k))) throw new PanelFault('invalid_state', 422);
    const parts = operation.path.slice(1).split('/').map(segment => {
      if (/~(?![01])/u.test(segment)) throw new PanelFault('invalid_state', 422);
      const key = segment.replaceAll('~1', '/').replaceAll('~0', '~');
      if (['__proto__', 'prototype', 'constructor'].includes(key)) throw new PanelFault('invalid_state', 422);
      return key;
    });
    root = apply(root, parts, String(operation.op), operation.value);
  }
  if (!isRecord(root) || !isJsonValue(root.task)) throw new PanelFault('invalid_state', 422);
  return root.task;
}
function apply(node: JsonValue, parts: string[], op: string, value: unknown): JsonValue {
  const [key, ...rest] = parts;
  if (Array.isArray(node)) {
    const index = key === '-' && op === 'add' && !rest.length ? node.length : /^(0|[1-9][0-9]*)$/u.test(key) ? Number(key) : -1;
    if (index < 0 || index > node.length || (index === node.length && (op !== 'add' || rest.length))) throw new PanelFault('invalid_state', 422);
    if (rest.length) node[index] = apply(node[index], rest, op, value);
    else if (op === 'remove') node.splice(index, 1);
    else { if (!isJsonValue(value)) throw new PanelFault('invalid_state', 422); if (op === 'add') node.splice(index, 0, value); else node[index] = value; }
    return node;
  }
  if (!isRecord(node) || (op !== 'add' && !Object.hasOwn(node, key)) || (rest.length && !Object.hasOwn(node, key))) throw new PanelFault('invalid_state', 422);
  const object = node as Record<string, JsonValue>;
  if (rest.length) object[key] = apply(object[key], rest, op, value);
  else if (op === 'remove') delete object[key];
  else { if (!isJsonValue(value)) throw new PanelFault('invalid_state', 422); object[key] = value; }
  return object;
}
