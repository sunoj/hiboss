// An ask whose question is one catalog v2 input (RankedChoice or ItemReview) in metadata.form.
// Exports parseAskForm, askFormOf, and validateFormAnswers; the answer schema is always derived.
// Dependencies: @hiboss/panel-runtime (catalog v2 inputs and the shared answer validator).

import { answerSchemaFor, validateAnswers, V2_INPUT_TYPES } from '@hiboss/panel-runtime';

export const FORM_ANSWER_POINTER = '/form/answer';
const MAX_FORM_BYTES = 8_192;
const MAX_ANSWERS_BYTES = 16_384;

export interface AskForm {
  readonly catalogVersion: 2;
  readonly input: { readonly type: string; readonly props: Record<string, unknown> };
}

type Result<T> = { ok: true; value: T } | { ok: false; error: string };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function bytes(value: unknown): number {
  return new TextEncoder().encode(JSON.stringify(value)).length;
}

/** Checks a send's `metadata.form`: exactly one v2 input bound to /form/answer, at most 8 KiB. */
export function parseAskForm(value: unknown): Result<AskForm> {
  if (!isRecord(value) || Object.keys(value).some((key) => key !== 'catalogVersion' && key !== 'input')) {
    return { ok: false, error: 'form must be {catalogVersion, input}' };
  }
  if (value.catalogVersion !== 2) return { ok: false, error: 'form.catalogVersion must be 2' };
  if (bytes(value) > MAX_FORM_BYTES) return { ok: false, error: 'form exceeds 8 KiB' };
  const input = value.input;
  if (!isRecord(input) || Object.keys(input).some((key) => key !== 'type' && key !== 'props')
    || typeof input.type !== 'string' || !isRecord(input.props)) {
    return { ok: false, error: 'form.input must be {type, props}' };
  }
  if (!(V2_INPUT_TYPES as readonly string[]).includes(input.type)) {
    return { ok: false, error: `form.input.type must be one of ${V2_INPUT_TYPES.join(', ')}` };
  }
  const binding = input.props.value;
  if (!isRecord(binding) || binding.$bindState !== FORM_ANSWER_POINTER) {
    return { ok: false, error: `form.input.props.value must be {"$bindState": "${FORM_ANSWER_POINTER}"}` };
  }
  const derived = answerSchemaFor(input.type, input.props);
  if (!derived.ok) return { ok: false, error: `form.input${derived.error.path}: ${derived.error.message}` };
  return { ok: true, value: { catalogVersion: 2, input: { type: input.type, props: input.props } } };
}

/**
 * The parent's form, when the parent is a form ask; malformed or absent metadata is null.
 * A message that offers options is never a form ask, so rows stored before form asks existed
 * (with a coincidental `form` key) keep their buttons and their timeout default.
 */
export function askFormOf(metadata: string | null): AskForm | null {
  if (!metadata) return null;
  try {
    const parsed = JSON.parse(metadata) as unknown;
    if (!isRecord(parsed) || parsed.form === undefined) return null;
    if (Array.isArray(parsed.options) && parsed.options.length > 0) return null;
    const form = parseAskForm(parsed.form);
    return form.ok ? form.value : null;
  } catch {
    return null;
  }
}

/** Validates the value the boss gave for the form's one input against the derived schema. */
export function validateFormAnswers(form: AskForm, answers: unknown): Result<unknown> {
  if (answers === undefined) return { ok: false, error: 'this question needs a form answer' };
  if (bytes(answers) > MAX_ANSWERS_BYTES) return { ok: false, error: 'answers exceed 16 KiB' };
  const derived = answerSchemaFor(form.input.type, form.input.props);
  if (!derived.ok) return { ok: false, error: derived.error.message };
  const schema = { type: 'object', properties: { answer: derived.value }, required: ['answer'], additionalProperties: false };
  const result = validateAnswers(schema, { answer: answers });
  return result.ok ? { ok: true, value: answers } : { ok: false, error: `answers${result.error.path.replace(/^\/answer/, '')}: ${result.error.message}` };
}
