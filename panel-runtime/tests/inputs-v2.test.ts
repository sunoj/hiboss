// Catalog v2 inputs: version gating, derived answer schemas, and questionnaire consistency.
// Exports no runtime API; exercises the public barrel from the consumer boundary.
// Dependencies: vitest and @hiboss/panel-runtime.

import { describe, expect, it } from 'vitest';
import {
  answerSchemaFor,
  validateAnswerSchema,
  validateAnswers,
  validateCatalogIdentity,
  validateInputAnswerSchemas,
  validatePanelSpec,
} from '../src/index.js';

const ranked = {
  label: 'Order the follow-ups',
  value: { $bindState: '/form/order' },
  options: [{ id: 'sync', label: 'Fix sync' }, { id: 'settings', label: 'Split settings' }, { id: 'flag', label: 'Rename flag' }],
};
const review = {
  label: 'Pre-release checklist',
  value: { $bindState: '/form/checks' },
  items: [{ id: 'changelog', label: 'Changelog read' }, { id: 'rollback', label: 'Rollback tested' }],
  verdicts: [{ id: 'confirmed', label: 'Confirmed' }, { id: 'not_confirmed', label: 'Cannot confirm', requiresNote: true }],
};

function formSchema(key: string, derived: Record<string, unknown>) {
  return { type: 'object', properties: { [key]: derived }, required: [key], additionalProperties: false };
}

function spec(type: string, props: unknown) {
  return { root: 'main', elements: { main: { type, props, children: [] } } };
}

describe('catalog v2 identity', () => {
  it('accepts versions 1 and 2 and lists the new inputs only in 2', () => {
    const v1 = validateCatalogIdentity('hiboss.panel', 1);
    const v2 = validateCatalogIdentity('hiboss.panel', 2);
    expect(v1.ok && v1.value.components.includes('RankedChoice')).toBe(false);
    expect(v2.ok && v2.value.components.includes('ItemReview')).toBe(true);
    expect(validateCatalogIdentity('hiboss.panel', 3).ok).toBe(false);
  });

  it('rejects a v2 input in a v1 spec with an actionable message', () => {
    const declaredPaths = ['/form/order'];
    const v1 = validatePanelSpec(spec('RankedChoice', ranked), { declaredPaths });
    expect(v1.ok).toBe(false);
    expect(!v1.ok && v1.error.message).toContain('catalogVersion 2');
    expect(validatePanelSpec(spec('RankedChoice', ranked), { declaredPaths, catalogVersion: 2 }).ok).toBe(true);
  });

  it('rejects duplicate ids, a topK above the option count, and a read-only value', () => {
    const dup = { ...ranked, options: [ranked.options[0], ranked.options[0]] };
    expect(answerSchemaFor('RankedChoice', dup).ok).toBe(false);
    expect(answerSchemaFor('RankedChoice', { ...ranked, topK: 4 }).ok).toBe(false);
    expect(answerSchemaFor('RankedChoice', { ...ranked, value: { $state: '/form/order' } }).ok).toBe(false);
    expect(answerSchemaFor('ItemReview', { ...review, verdicts: [review.verdicts[0]] }).ok).toBe(false);
  });
});

describe('RankedChoice answers', () => {
  const derived = answerSchemaFor('RankedChoice', ranked);
  const schema = derived.ok ? formSchema('order', derived.value) : {};

  it('derives a schema inside the supported subset', () => {
    expect(derived.ok).toBe(true);
    expect(validateAnswerSchema(schema).ok).toBe(true);
  });

  it('accepts a full permutation and rejects repeats, gaps and unknown ids', () => {
    expect(validateAnswers(schema, { order: ['flag', 'sync', 'settings'] }).ok).toBe(true);
    expect(validateAnswers(schema, { order: ['flag', 'flag', 'sync'] }).ok).toBe(false);
    expect(validateAnswers(schema, { order: ['flag', 'sync'] }).ok).toBe(false);
    expect(validateAnswers(schema, { order: ['flag', 'sync', 'other'] }).ok).toBe(false);
  });

  it('ranks only the first k with topK', () => {
    const top = answerSchemaFor('RankedChoice', { ...ranked, topK: 2 });
    const topSchema = top.ok ? formSchema('order', top.value) : {};
    expect(validateAnswers(topSchema, { order: ['settings', 'sync'] }).ok).toBe(true);
    expect(validateAnswers(topSchema, { order: ['settings', 'sync', 'flag'] }).ok).toBe(false);
  });
});

describe('ItemReview answers', () => {
  const derived = answerSchemaFor('ItemReview', review);
  const schema = derived.ok ? formSchema('checks', derived.value) : {};

  it('derives a schema inside the supported subset', () => {
    expect(derived.ok).toBe(true);
    expect(validateAnswerSchema(schema).ok).toBe(true);
  });

  it('needs every item and a note on a verdict that requires one', () => {
    const ok = { checks: { changelog: { verdict: 'confirmed' }, rollback: { verdict: 'not_confirmed', note: 'Old schema only' } } };
    expect(validateAnswers(schema, ok).ok).toBe(true);
    expect(validateAnswers(schema, { checks: { changelog: { verdict: 'confirmed' } } }).ok).toBe(false);
    expect(validateAnswers(schema, { checks: { changelog: { verdict: 'confirmed' }, rollback: { verdict: 'not_confirmed' } } }).ok).toBe(false);
    expect(validateAnswers(schema, { checks: { changelog: { verdict: 'confirmed' }, rollback: { verdict: 'maybe' } } }).ok).toBe(false);
    expect(validateAnswers(schema, { checks: { ...ok.checks, extra: { verdict: 'confirmed' } } }).ok).toBe(false);
  });

  it('lets an optional note through on a verdict that does not require one', () => {
    const answers = { checks: { changelog: { verdict: 'confirmed', note: 'Read twice' }, rollback: { verdict: 'confirmed' } } };
    expect(validateAnswers(schema, answers).ok).toBe(true);
  });
});

describe('questionnaire consistency', () => {
  it('requires the declared schema at a v2 input to equal the derived one', () => {
    const elements = { main: { type: 'RankedChoice', props: ranked } };
    const derived = answerSchemaFor('RankedChoice', ranked);
    expect(derived.ok && validateInputAnswerSchemas(elements, formSchema('order', derived.value)).ok).toBe(true);
    const loose = formSchema('order', { type: 'array', items: { type: 'string' } });
    const result = validateInputAnswerSchemas(elements, loose);
    expect(result.ok).toBe(false);
    expect(!result.ok && result.error.path).toBe('/formSpec/elements/main/props/value');
  });
});
