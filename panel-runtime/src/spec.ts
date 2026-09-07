// Validates catalog panel trees, bindings, actions, limits, and safe pointers.
// Exports panel spec types and validatePanelSpec.
// Dependencies: zod, catalog schemas, and shared validation errors.

import { z } from 'zod';
import {
  componentPropSchemas,
  isActionName,
  isComponentType,
  registeredActions,
  type ActionName,
  type BindingExpression,
  type ComponentType,
} from './catalog.js';
import { failure, type ValidationIssue, type ValidationResult } from './errors.js';

export const MAX_SPEC_ELEMENTS = 200;
export const MAX_SPEC_DEPTH = 12;

export interface PanelElement {
  readonly type: ComponentType;
  readonly props: Readonly<Record<string, unknown>>;
  readonly children: readonly string[];
  readonly on?: Readonly<Record<string, PanelAction>>;
}

export interface PanelAction {
  readonly action: ActionName;
  readonly params?: Readonly<Record<string, unknown>>;
}

export interface PanelSpec {
  readonly root: string;
  readonly elements: Readonly<Record<string, PanelElement>>;
}

export interface SpecValidationOptions {
  readonly declaredPaths?: readonly string[];
  readonly stateSchema?: unknown;
}

const elementKeys = new Set(['type', 'props', 'children', 'on']);
const actionKeys = new Set(['action', 'params']);
const dangerousSegments = new Set(['__proto__', 'prototype', 'constructor']);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function pointerPath(path: readonly (string | number)[]): string {
  return path.length === 0 ? '' : `/${path.map((part) => String(part).replaceAll('~', '~0').replaceAll('/', '~1')).join('/')}`;
}

function zodIssuePath(error: z.ZodError, base: string): string {
  const issue = error.issues[0];
  if (issue === undefined) return base;
  if (issue.code === 'unrecognized_keys' && issue.keys[0] !== undefined) return `${base}/${issue.keys[0]}`;
  return `${base}${pointerPath(issue.path.map(String))}`;
}

function decodePointer(pointer: string): string[] | ValidationIssue {
  if (!pointer.startsWith('/')) return { code: 'invalid_spec', path: '', message: 'Binding must be a JSON Pointer' };
  const segments = pointer.slice(1).split('/').map((segment) => {
    let decoded = '';
    for (let index = 0; index < segment.length; index += 1) {
      const character = segment[index];
      if (character !== '~') {
        decoded += character;
        continue;
      }
      const escape = segment[index + 1];
      if (escape !== '0' && escape !== '1') return undefined;
      decoded += escape === '0' ? '~' : '/';
      index += 1;
    }
    return decoded;
  });
  if (segments.some((segment) => segment === undefined)) {
    return { code: 'invalid_spec', path: pointer, message: 'Binding contains an invalid JSON Pointer escape' };
  }
  const decoded = segments as string[];
  const dangerous = decoded.find((segment) => dangerousSegments.has(segment));
  return dangerous === undefined
    ? decoded
    : { code: 'invalid_spec', path: pointer, message: `Dangerous JSON Pointer segment "${dangerous}"` };
}

function validateBinding(value: unknown, path: string, declaredPaths: ReadonlySet<string>): ValidationResult<BindingExpression> {
  const parsed = z.union([
    z.strictObject({ $state: z.string() }),
    z.strictObject({ $bindState: z.string() }),
    z.strictObject({ $item: z.string() }),
    z.strictObject({ $index: z.number().int().nonnegative() }),
    z.strictObject({ $bindItem: z.string() }),
  ]).safeParse(value);
  if (!parsed.success) return failure('invalid_spec', path, 'Binding must use one supported expression');
  const expression = parsed.data as BindingExpression;
  const expressionKey = Object.keys(expression)[0] ?? '';
  const pointerValue = '$index' in expression ? undefined : Object.values(expression)[0];
  if (typeof pointerValue !== 'string') return { ok: true, value: expression };
  const decoded = decodePointer(pointerValue);
  if (!Array.isArray(decoded)) return { ok: false, error: { ...decoded, path: `${path}/${expressionKey}` } };
  if (!declaredPaths.has(pointerValue)) return failure('invalid_spec', `${path}/${expressionKey}`, 'Binding path is not declared');
  return { ok: true, value: expression };
}

function schemaPaths(value: unknown, path = ''): string[] {
  if (!isRecord(value) || !isRecord(value.properties)) return path === '' ? [] : [path];
  const paths: string[] = [];
  for (const [name, child] of Object.entries(value.properties)) {
    const childPath = `${path}/${name.replaceAll('~', '~0').replaceAll('/', '~1')}`;
    paths.push(childPath, ...schemaPaths(child, childPath));
  }
  return paths;
}

function validateAction(value: unknown, path: string): ValidationResult<PanelAction> {
  if (!isRecord(value) || Object.keys(value).some((key) => !actionKeys.has(key)) || typeof value.action !== 'string') {
    return failure('invalid_spec', path, 'Action binding is malformed');
  }
  if (!isActionName(value.action)) return failure('invalid_spec', `${path}/action`, `Unknown action "${value.action}"`);
  if (value.params !== undefined && !isRecord(value.params)) return failure('invalid_spec', `${path}/params`, 'Action params must be an object');
  const params = value.params;
  const schema = registeredActions[value.action];
  if (params !== undefined && !schema.safeParse(params).success) {
    return failure('invalid_spec', `${path}/params`, `Invalid params for action "${value.action}"`);
  }
  return params === undefined ? { ok: true, value: { action: value.action } } : { ok: true, value: { action: value.action, params } };
}

function validateElement(value: unknown, path: string, declaredPaths: ReadonlySet<string>): ValidationResult<PanelElement> {
  if (!isRecord(value)) return failure('invalid_spec', path, 'Element must be an object');
  const unknownKey = Object.keys(value).find((key) => !elementKeys.has(key));
  if (unknownKey !== undefined) return failure('invalid_spec', `${path}/${unknownKey}`, 'Unknown element property');
  if (typeof value.type !== 'string' || !isComponentType(value.type)) return failure('invalid_spec', `${path}/type`, `Unknown component "${String(value.type)}"`);
  if (!isRecord(value.props)) return failure('invalid_spec', `${path}/props`, 'Component props must be an object');
  const props = componentPropSchemas[value.type].safeParse(value.props);
  if (!props.success) return failure('invalid_spec', zodIssuePath(props.error, `${path}/props`), props.error.issues[0]?.message ?? 'Invalid component props');
  if (!Array.isArray(value.children) || value.children.some((child) => typeof child !== 'string')) return failure('invalid_spec', `${path}/children`, 'Children must be string element IDs');
  const actions: Record<string, PanelAction> = Object.create(null) as Record<string, PanelAction>;
  if (value.on !== undefined) {
    if (!isRecord(value.on)) return failure('invalid_spec', `${path}/on`, 'Element actions must be an object');
    for (const [event, action] of Object.entries(value.on)) {
      const validated = validateAction(action, `${path}/on/${event}`);
      if (!validated.ok) return validated;
      actions[event] = validated.value;
    }
  }
  for (const [key, prop] of Object.entries(value.props)) {
    if (isRecord(prop) && Object.keys(prop).some((name) => name.startsWith('$'))) {
      const bindingResult = validateBinding(prop, `${path}/props/${key}`, declaredPaths);
      if (!bindingResult.ok) return bindingResult;
    }
  }
  return value.on === undefined
    ? { ok: true, value: { type: value.type, props: value.props, children: value.children } }
    : { ok: true, value: { type: value.type, props: value.props, children: value.children, on: actions } };
}

function checkTree(spec: PanelSpec): ValidationResult<PanelSpec> {
  const colors = new Map<string, 'visiting' | 'done'>();
  const visit = (id: string, depth: number, parentPath: string): ValidationResult<PanelSpec> => {
    if (depth > MAX_SPEC_DEPTH) return failure('invalid_spec', parentPath, `Tree depth exceeds ${MAX_SPEC_DEPTH}`);
    const color = colors.get(id);
    if (color === 'visiting') return failure('invalid_spec', parentPath, 'Panel tree contains a cycle');
    if (color === 'done') return { ok: true, value: spec };
    const element = spec.elements[id];
    if (element === undefined) return failure('invalid_spec', parentPath, `Unknown child element "${id}"`);
    colors.set(id, 'visiting');
    for (let index = 0; index < element.children.length; index += 1) {
      const child = element.children[index];
      if (child === undefined) return failure('invalid_spec', `${parentPath}/children/${index}`, 'Child ID is missing');
      const result = visit(child, depth + 1, `/elements/${id}/children/${index}`);
      if (!result.ok) return result;
    }
    colors.set(id, 'done');
    return { ok: true, value: spec };
  };
  return visit(spec.root, 1, '/root');
}

export function validatePanelSpec(value: unknown, options: SpecValidationOptions = {}): ValidationResult<PanelSpec> {
  if (!isRecord(value)) return failure('invalid_spec', '', 'Panel spec must be an object');
  if (typeof value.root !== 'string' || value.root.length === 0) return failure('invalid_spec', '/root', 'Panel root must be a non-empty ID');
  if (!isRecord(value.elements)) return failure('invalid_spec', '/elements', 'Panel elements must be an object');
  const elementIds = Object.keys(value.elements);
  if (elementIds.length > MAX_SPEC_ELEMENTS) return failure('invalid_spec', '/elements', `Panel exceeds ${MAX_SPEC_ELEMENTS} elements`);
  const declaredPaths = new Set([...schemaPaths(options.stateSchema), ...(options.declaredPaths ?? [])]);
  const elements: Record<string, PanelElement> = Object.create(null) as Record<string, PanelElement>;
  for (const id of elementIds) {
    const result = validateElement(value.elements[id], `/elements/${id}`, declaredPaths);
    if (!result.ok) return result;
    elements[id] = result.value;
  }
  const spec: PanelSpec = { root: value.root, elements };
  if (elements[spec.root] === undefined) return failure('invalid_spec', '/root', `Root element "${spec.root}" does not exist`);
  return checkTree(spec);
}

export function validatePanelPublication(value: unknown): ValidationResult<PanelSpec> {
  if (!isRecord(value)) return failure('invalid_spec', '', 'Panel publication must be an object');
  return validatePanelSpec(value.spec, { stateSchema: value.stateSchema });
}
