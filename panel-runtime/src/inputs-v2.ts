// Catalog v2 inputs RankedChoice and ItemReview: prop schemas and their exact answer schemas.
// Exports inputV2PropSchemas, answerSchemaFor, and validateInputAnswerSchemas.
// Dependencies: zod and shared validation errors (no catalog import, to avoid a cycle).

import { z } from 'zod';
import { failure, type ValidationResult } from './errors.js';

const pointer = z.string().min(1).refine((value) => value.startsWith('/'), 'must be a JSON Pointer');
const writable = z.strictObject({ $bindState: pointer });
/** ASCII ids, so no two ids can collide under Unicode normalization on a client. */
const id = z.string().regex(/^[A-Za-z0-9_.-]{1,64}$/, 'ids use only letters, digits, "_", "." and "-"');
const entry = z.strictObject({ id, label: z.string().min(1).max(200), description: z.string().max(400).optional() });

function uniqueIds(list: readonly { id: string }[]): boolean {
  return new Set(list.map((item) => item.id)).size === list.length;
}

const rankedChoice = z.strictObject({
  label: z.string().min(1),
  value: writable,
  options: z.array(entry).min(2).max(20).refine(uniqueIds, 'Option ids must be unique'),
  topK: z.number().int().positive().optional(),
}).refine((props) => props.topK === undefined || props.topK <= props.options.length,
  { message: 'topK cannot exceed the number of options', path: ['topK'] });

const verdict = z.strictObject({ id, label: z.string().min(1).max(60), requiresNote: z.boolean().optional() });
const itemReview = z.strictObject({
  label: z.string().min(1),
  value: writable,
  items: z.array(entry).min(1).max(50).refine(uniqueIds, 'Item ids must be unique'),
  verdicts: z.array(verdict).min(2).max(4).refine(uniqueIds, 'Verdict ids must be unique'),
  layout: z.enum(['checklist', 'grid']).optional(),
});

export const inputV2PropSchemas = { RankedChoice: rankedChoice, ItemReview: itemReview } as const;

export type RankedChoiceProps = z.infer<typeof rankedChoice>;
export type ItemReviewProps = z.infer<typeof itemReview>;
export const NOTE_MAX_LENGTH = 1000;

function rankedSchema(props: RankedChoiceProps): Record<string, unknown> {
  const count = props.topK ?? props.options.length;
  return {
    type: 'array',
    items: { type: 'string', enum: props.options.map((option) => option.id) },
    uniqueItems: true,
    minItems: count,
    maxItems: count,
  };
}

function reviewItemSchema(props: ItemReviewProps): Record<string, unknown> {
  const noted = props.verdicts.filter((entry) => entry.requiresNote).map((entry) => entry.id);
  const schema: Record<string, unknown> = {
    type: 'object',
    properties: {
      verdict: { type: 'string', enum: props.verdicts.map((entry) => entry.id) },
      note: { type: 'string', maxLength: NOTE_MAX_LENGTH },
    },
    required: ['verdict'],
    additionalProperties: false,
  };
  if (noted.length === 0) return schema;
  return {
    ...schema,
    if: { properties: { verdict: { enum: noted } }, required: ['verdict'] },
    then: { properties: { note: { type: 'string', minLength: 1 } }, required: ['note'] },
  };
}

function reviewSchema(props: ItemReviewProps): Record<string, unknown> {
  const item = reviewItemSchema(props);
  return {
    type: 'object',
    properties: Object.fromEntries(props.items.map((entry) => [entry.id, item])),
    required: props.items.map((entry) => entry.id),
    additionalProperties: false,
  };
}

/** The exact answer schema a v2 input's value must satisfy, derived from its props. */
export function answerSchemaFor(type: string, props: unknown): ValidationResult<Record<string, unknown>> {
  if (type === 'RankedChoice') {
    const parsed = rankedChoice.safeParse(props);
    return parsed.success ? { ok: true, value: rankedSchema(parsed.data) } : failure('invalid_spec', '/props', parsed.error.issues[0]?.message ?? 'Invalid RankedChoice');
  }
  if (type === 'ItemReview') {
    const parsed = itemReview.safeParse(props);
    return parsed.success ? { ok: true, value: reviewSchema(parsed.data) } : failure('invalid_spec', '/props', parsed.error.issues[0]?.message ?? 'Invalid ItemReview');
  }
  return failure('invalid_spec', '/type', `"${type}" has no derived answer schema`);
}

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    return `{${entries.map(([key, child]) => `${JSON.stringify(key)}:${canonical(child)}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

/** The decoded `/form/<key>` property name, or undefined for any other pointer. */
function formKey(formPointer: string): string | undefined {
  const raw = formPointer.replace(/^\/form\//, '');
  if (raw === formPointer || raw.includes('/')) return undefined;
  return raw.replaceAll('~1', '/').replaceAll('~0', '~');
}

function schemaAt(answerSchema: unknown, key: string): unknown {
  const properties = (answerSchema as { properties?: Record<string, unknown> } | null)?.properties;
  return properties !== undefined && Object.prototype.hasOwnProperty.call(properties, key) ? properties[key] : undefined;
}

function isRequired(answerSchema: unknown, key: string): boolean {
  const required = (answerSchema as { required?: unknown } | null)?.required;
  return Array.isArray(required) && required.includes(key);
}

/**
 * A questionnaire may not loosen a v2 input: the schema at each such input's `/form/<key>`
 * binding must equal the derived one, so the native control and the server agree.
 */
export function validateInputAnswerSchemas(
  elements: Readonly<Record<string, { type: string; props: Readonly<Record<string, unknown>> }>>,
  answerSchema: unknown,
): ValidationResult<true> {
  for (const [elementId, element] of Object.entries(elements)) {
    if (element.type !== 'RankedChoice' && element.type !== 'ItemReview') continue;
    const derived = answerSchemaFor(element.type, element.props);
    if (!derived.ok) return derived;
    const binding = (element.props.value as { $bindState?: string } | undefined)?.$bindState ?? '';
    const key = formKey(binding);
    const declared = key === undefined ? undefined : schemaAt(answerSchema, key);
    if (key === undefined || !isRequired(answerSchema, key)) {
      return failure('invalid_spec', `/formSpec/elements/${elementId}/props/value`,
        `${element.type} must bind to a /form/<field> listed in the answer schema's root "required"`);
    }
    if (declared === undefined || canonical(declared) !== canonical(derived.value)) {
      return failure('invalid_spec', `/formSpec/elements/${elementId}/props/value`,
        `The answer schema at ${binding} must equal the one derived from this ${element.type}: ${canonical(derived.value)}`);
    }
  }
  return { ok: true, value: true };
}
