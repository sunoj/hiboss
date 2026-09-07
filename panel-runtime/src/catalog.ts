// Zod catalog for hiboss.panel version 1 and its registered actions.
// Exports component schemas, catalog metadata, and catalog identity validation.
// Dependencies: zod and shared validation errors.

import { z } from 'zod';
import { failure, type ValidationResult } from './errors.js';

export const CATALOG_ID = 'hiboss.panel' as const;
export const CATALOG_VERSION = 1 as const;
export const COMPONENT_TYPES = [
  'Stack', 'Grid', 'Section', 'Text', 'Metric', 'Progress', 'Status', 'Table',
  'LineChart', 'BarChart', 'TextInput', 'TextArea', 'NumberInput', 'Select',
  'MultiSelect', 'Toggle', 'Slider', 'Button',
] as const;
export type ComponentType = (typeof COMPONENT_TYPES)[number];
export const ACTION_NAMES = ['submitRequest', 'openPanel'] as const;
export type ActionName = (typeof ACTION_NAMES)[number];

const pointer = z.string().min(1).refine((value) => value.startsWith('/'), 'must be a JSON Pointer');
const binding = z.union([
  z.strictObject({ $state: pointer }),
  z.strictObject({ $bindState: pointer }),
  z.strictObject({ $item: pointer }),
  z.strictObject({ $index: z.number().int().nonnegative() }),
  z.strictObject({ $bindItem: pointer }),
]);
const textValue = z.union([z.string(), binding]);
const finiteNumber = z.number().finite();
const option = z.strictObject({
  id: z.string().min(1),
  label: z.string().min(1),
  description: z.string().optional(),
});
const sharedLabel = { label: z.string().min(1) };
const chartValues = z.union([
  z.array(z.union([finiteNumber, z.null()])),
  z.strictObject({ $state: pointer }),
]);

export const componentPropSchemas = {
  Stack: z.strictObject({ direction: z.enum(['vertical', 'horizontal']), gap: finiteNumber.nonnegative().optional() }),
  Grid: z.strictObject({ columns: z.number().int().positive(), gap: finiteNumber.nonnegative().optional() }),
  Section: z.strictObject({ ...sharedLabel, description: z.string().optional(), collapsible: z.boolean().optional() }),
  Text: z.strictObject({ text: textValue, tone: z.enum(['default', 'muted', 'positive', 'warning', 'danger']).optional() }),
  Metric: z.strictObject({ ...sharedLabel, value: z.union([finiteNumber, z.string(), binding]), unit: z.string().optional(), missingText: z.string().optional() }),
  Progress: z.strictObject({ ...sharedLabel, value: z.union([finiteNumber, binding]), min: finiteNumber.optional(), max: finiteNumber.optional() }),
  Status: z.strictObject({ ...sharedLabel, status: z.enum(['pending', 'active', 'success', 'warning', 'error']), message: z.string().optional() }),
  Table: z.strictObject({
    ...sharedLabel,
    columns: z.array(z.strictObject({ id: z.string().min(1), label: z.string().min(1) })).min(1),
    rows: z.array(z.record(z.string(), z.unknown())).optional(),
    rowsBinding: binding.optional(),
  }),
  LineChart: z.strictObject({ label: z.string().optional(), values: chartValues, unit: z.string().optional() }),
  BarChart: z.strictObject({ label: z.string().optional(), values: chartValues, unit: z.string().optional() }),
  TextInput: z.strictObject({ ...sharedLabel, value: binding, placeholder: z.string().optional(), minLength: z.number().int().nonnegative().optional(), maxLength: z.number().int().nonnegative().optional() }),
  TextArea: z.strictObject({ ...sharedLabel, value: binding, placeholder: z.string().optional(), rows: z.number().int().positive().optional(), minLength: z.number().int().nonnegative().optional(), maxLength: z.number().int().nonnegative().optional() }),
  NumberInput: z.strictObject({ ...sharedLabel, value: binding, min: finiteNumber.optional(), max: finiteNumber.optional(), step: finiteNumber.positive().optional() }),
  Select: z.strictObject({ ...sharedLabel, value: binding, options: z.array(option).min(1), placeholder: z.string().optional() }),
  MultiSelect: z.strictObject({ ...sharedLabel, value: binding, options: z.array(option).min(1) }),
  Toggle: z.strictObject({ ...sharedLabel, value: binding, description: z.string().optional() }),
  Slider: z.strictObject({ ...sharedLabel, value: binding, min: finiteNumber, max: finiteNumber, step: finiteNumber.positive().optional() }),
  Button: z.strictObject({ label: z.string().min(1), variant: z.enum(['primary', 'secondary', 'danger']).optional(), disabled: z.boolean().optional() }),
} as const;

export const registeredActions = {
  submitRequest: z.strictObject({}),
  openPanel: z.strictObject({ panelId: z.string().min(1) }),
} as const;

export interface CatalogManifest {
  readonly catalogId: typeof CATALOG_ID;
  readonly catalogVersion: typeof CATALOG_VERSION;
  readonly components: readonly ComponentType[];
  readonly actions: readonly ActionName[];
}

export const catalogManifest: CatalogManifest = {
  catalogId: CATALOG_ID,
  catalogVersion: CATALOG_VERSION,
  components: COMPONENT_TYPES,
  actions: ACTION_NAMES,
};

export function validateCatalogIdentity(catalogId: unknown, catalogVersion: unknown): ValidationResult<CatalogManifest> {
  if (catalogId !== CATALOG_ID) return failure('unsupported_catalog', '/catalogId', `Unsupported catalog "${String(catalogId)}"`);
  if (catalogVersion !== CATALOG_VERSION) return failure('unsupported_catalog', '/catalogVersion', `Unsupported catalog version "${String(catalogVersion)}"`);
  return { ok: true, value: catalogManifest };
}

export function isComponentType(value: string): value is ComponentType {
  return (COMPONENT_TYPES as readonly string[]).includes(value);
}

export function isActionName(value: string): value is ActionName {
  return (ACTION_NAMES as readonly string[]).includes(value);
}

export type BindingExpression =
  | { readonly $state: string }
  | { readonly $bindState: string }
  | { readonly $item: string }
  | { readonly $index: number }
  | { readonly $bindItem: string };
