// Validates bounded questionnaire definitions and exact submission envelopes.
// Exports definition/submission parsers; rejects execution authorizations in this catalog slice.
// Dependencies: shared schema/catalog validators and panel faults.

import { validateAnswerSchema, validateAnswers, validateCatalogIdentity, validatePanelSpec, type AnswerSchema, type PanelSpec } from '@hiboss/panel-runtime';
import { isJsonValue, isRecord } from '../definition/helpers';
import { PanelFault } from '../lifecycle/types';
import type { Questionnaire, Submission } from './types';

const MAX_DOCUMENT_BYTES = 65_536;
const MAX_ANSWERS_BYTES = 16_384;
const ID = /^[A-Za-z0-9_-]{1,128}$/;
const INPUT_TYPES = new Set(['TextInput', 'TextArea', 'NumberInput', 'Select', 'MultiSelect', 'Toggle', 'Slider']);

export function parseQuestionnaire(value: unknown): Questionnaire {
  if (!isRecord(value) || new TextEncoder().encode(JSON.stringify(value)).length > MAX_DOCUMENT_BYTES) throw new PanelFault('invalid_request', 422);
  const keys = ['kind', 'title', 'blocking', 'priority', 'expiresAt', 'catalogId', 'catalogVersion', 'formSpec', 'answerSchema', 'defaults', 'context'];
  if (Object.keys(value).some(k => !keys.includes(k))) throw new PanelFault('invalid_request', 422);
  if (value.kind !== 'intake') throw new PanelFault('unsupported_request_kind', 422, 'This release supports intake questionnaires only');
  if (typeof value.title !== 'string' || !value.title.trim() || value.title.length > 240 || typeof value.blocking !== 'boolean'
    || !['low', 'normal', 'high', 'critical'].includes(String(value.priority))) throw new PanelFault('invalid_request', 422);
  if (value.expiresAt !== undefined && (typeof value.expiresAt !== 'string' || !Number.isFinite(Date.parse(value.expiresAt)))) throw new PanelFault('invalid_expiry', 422);
  if (!validateCatalogIdentity(value.catalogId, value.catalogVersion).ok) throw new PanelFault('unsupported_catalog', 422);
  const schema = validateAnswerSchema(value.answerSchema);
  if (!schema.ok) throw new PanelFault('invalid_schema', 422, schema.error.message);
  if (!isRecord(value.defaults) || !isJsonValue(value.defaults) || !isRecord(value.context) || !isJsonValue(value.context)) throw new PanelFault('invalid_request', 422);
  const defaults = validateAnswers(optionalFields(schema.value), value.defaults);
  if (!defaults.ok) throw new PanelFault('invalid_defaults', 422, defaults.error.message);
  const stateSchema = { type: 'object', properties: { form: schema.value } };
  const contextPaths = jsonPaths(value.context, '/context');
  const spec = validatePanelSpec(value.formSpec, { stateSchema, declaredPaths: contextPaths });
  if (!spec.ok) throw new PanelFault('invalid_spec', 422, spec.error.message);
  validateFormBindings(spec.value);
  return { ...value, ...(typeof value.expiresAt === 'string' ? { expiresAt: new Date(value.expiresAt).toISOString() } : {}), formSpec: spec.value, answerSchema: schema.value } as unknown as Questionnaire;
}

function validateFormBindings(spec: PanelSpec): void {
  for (const element of Object.values(spec.elements)) {
    for (const prop of Object.values(element.props)) {
      if (!isRecord(prop)) continue;
      if ('$bindItem' in prop || ('$bindState' in prop && (typeof prop.$bindState !== 'string' || !prop.$bindState.startsWith('/form/')))) {
        throw new PanelFault('invalid_spec', 422, 'Writable bindings must target a declared answer field under /form/');
      }
    }
    if (INPUT_TYPES.has(element.type)) {
      const value = element.props.value;
      if (!isRecord(value) || typeof value.$bindState !== 'string') throw new PanelFault('invalid_spec', 422, 'Inputs require a writable answer binding');
    }
  }
}

function optionalFields(schema: AnswerSchema): AnswerSchema {
  const result: Record<string, unknown> = { ...schema, required: [] };
  for (const key of ['properties', '$defs']) {
    const children = schema[key];
    if (isRecord(children)) result[key] = Object.fromEntries(Object.entries(children).map(([name, child]) => [name, isRecord(child) ? optionalFields(child) : child]));
  }
  for (const key of ['items', 'then', 'else']) if (isRecord(schema[key])) result[key] = optionalFields(schema[key]);
  if (Array.isArray(schema.allOf)) result.allOf = schema.allOf.map(child => isRecord(child) ? optionalFields(child) : child);
  return result;
}

function jsonPaths(value: Record<string, unknown>, prefix: string): string[] {
  return Object.entries(value).flatMap(([key, child]) => {
    const path = `${prefix}/${key.replaceAll('~', '~0').replaceAll('/', '~1')}`;
    return [path, ...(isRecord(child) ? jsonPaths(child, path) : [])];
  });
}

export function parseSubmission(value: unknown, requestId: string, bossId: string): Submission {
  if (!isRecord(value) || value.protocolVersion !== 1 || value.purpose !== 'hiboss.interaction-submit'
    || Object.keys(value).some(k => !['protocolVersion', 'purpose', 'submissionId', 'requestId', 'requestRevision', 'bossId', 'answers', 'signedSubmission'].includes(k))) throw new PanelFault('invalid_submission', 422);
  if (value.requestId !== requestId || value.bossId !== bossId || typeof value.submissionId !== 'string' || !ID.test(value.submissionId)
    || !Number.isSafeInteger(value.requestRevision) || Number(value.requestRevision) < 1
    || !isRecord(value.answers) || !isJsonValue(value.answers)
    || new TextEncoder().encode(JSON.stringify(value.answers)).length > MAX_ANSWERS_BYTES) throw new PanelFault('invalid_submission', 422);
  const { signedSubmission: _, ...submission } = value;
  return submission as unknown as Submission;
}
