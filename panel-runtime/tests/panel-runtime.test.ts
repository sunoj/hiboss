// End-to-end fixture coverage for catalog, spec, schema, and answer validation.
// Exports no runtime API; exercises the public barrel from the consumer boundary.
// Dependencies: vitest, JSON fixtures, and @hiboss/panel-runtime.

import { describe, expect, it } from 'vitest';
import metricPanel from '../fixtures/metric-panel.json' with { type: 'json' };
import rollout from '../fixtures/rollout-decision.json' with { type: 'json' };
import cycle from '../fixtures/cycle.json' with { type: 'json' };
import overDeep from '../fixtures/over-deep.json' with { type: 'json' };
import overLarge from '../fixtures/over-large.json' with { type: 'json' };
import unknownComponent from '../fixtures/unknown-component.json' with { type: 'json' };
import unknownAction from '../fixtures/unknown-action.json' with { type: 'json' };
import unsafePointer from '../fixtures/unsafe-pointer.json' with { type: 'json' };
import unknownProp from '../fixtures/unknown-prop.json' with { type: 'json' };
import unsupportedSchemaKeyword from '../fixtures/unsupported-schema-keyword.json' with { type: 'json' };
import giantArray from '../fixtures/giant-array.json' with { type: 'json' };
import downloadProgress from '../fixtures/examples/download-progress.json' with { type: 'json' };
import e2eTestRun from '../fixtures/examples/e2e-test-run.json' with { type: 'json' };
import benchmarkSweep from '../fixtures/examples/benchmark-sweep.json' with { type: 'json' };
import serviceMonitor from '../fixtures/examples/service-monitor.json' with { type: 'json' };
import researchIntake from '../fixtures/examples/research-intake.json' with { type: 'json' };
import {
  ACTION_NAMES,
  CATALOG_ID,
  CATALOG_VERSION,
  COMPONENT_TYPES,
  componentPropSchemas,
  validateAnswers,
  validateAnswerSchema,
  validateCatalogIdentity,
  validatePanelPublication,
  validatePanelSpec,
} from '../src/index.js';

describe('hiboss.panel catalog', () => {
  it('registers every protocol component and both host actions', () => {
    expect(Object.keys(componentPropSchemas)).toEqual([...COMPONENT_TYPES]);
    expect(ACTION_NAMES).toEqual(['submitRequest', 'openPanel']);
    expect(validateCatalogIdentity(CATALOG_ID, CATALOG_VERSION).ok).toBe(true);
    expect(validateCatalogIdentity('other.catalog', 1)).toMatchObject({ ok: false, error: { code: 'unsupported_catalog', path: '/catalogId' } });
  });

  it.each([
    ['download progress', downloadProgress],
    ['end-to-end test run', e2eTestRun],
    ['benchmark sweep', benchmarkSweep],
    ['service monitor', serviceMonitor],
  ] as const)('accepts the %s reference panel and its task state', (_name, fixture) => {
    expect(validatePanelPublication(fixture)).toMatchObject({ ok: true });
    const state = validateAnswers(fixture.stateSchema, fixture.initialState);
    expect(state).toMatchObject({ ok: true });
  });

  it('accepts the metric panel and keeps its element map prototype-free', () => {
    const result = validatePanelPublication(metricPanel);
    expect(result.ok).toBe(true);
    if (result.ok) expect(Object.getPrototypeOf(result.value.elements)).toBeNull();
    const state = validateAnswers(metricPanel.stateSchema, metricPanel.initialState);
    expect(state).toMatchObject({ ok: true });
  });

  it('accepts a declared headline, secondary value, and nullable series path', () => {
    const publication = {
      ...metricPanel,
      stateSchema: {
        ...metricPanel.stateSchema,
        properties: { task: { type: 'object', properties: { completed: { type: 'integer' }, rate: { type: 'number' }, trend: { type: 'array' } }, required: ['completed', 'rate', 'trend'], additionalProperties: false } },
      },
      initialState: { task: { completed: 4, rate: 0.88, trend: [0.7, null, 0.88] } },
      summary: {
        stage: 'Running',
        headline: { path: '/task/completed', label: 'Open' },
        secondary: { path: '/task/rate', label: 'Today', unit: '%' },
        series: '/task/trend',
      },
    };
    expect(validatePanelPublication(publication)).toMatchObject({ ok: true });
  });

  it('rejects a headline on an undeclared path with the summary pointer', () => {
    const publication = { ...metricPanel, summary: { stage: 'Running', headline: { path: '/task/missing', label: 'Missing' } } };
    expect(validatePanelPublication(publication)).toMatchObject({ ok: false, error: { path: '/summary/headline/path' } });
  });

  it('rejects a headline pointing at an object', () => {
    const publication = { ...metricPanel, summary: { stage: 'Running', headline: { path: '/task', label: 'Task' } } };
    expect(validatePanelPublication(publication)).toMatchObject({ ok: false, error: { path: '/summary/headline/path' } });
  });

  it('accepts a panel without a summary', () => {
    expect(validatePanelPublication({ ...metricPanel, summary: undefined })).toMatchObject({ ok: true });
  });

  it('accepts the rollout form and validates dependent full-rollout answers', () => {
    const spec = validatePanelSpec(rollout.formSpec, { declaredPaths: ['/form/strategy', '/form/trafficPercent'] });
    expect(spec).toMatchObject({ ok: true });
    const schema = validateAnswerSchema(rollout.answerSchema);
    expect(schema).toMatchObject({ ok: true });
    if (!schema.ok) return;
    expect(validateAnswers(schema.value, { strategy: 'canary', trafficPercent: 10 })).toMatchObject({ ok: true });
    expect(validateAnswers(schema.value, { strategy: 'full', trafficPercent: 10 })).toMatchObject({ ok: false, error: { code: 'invalid_answers', path: '/trafficPercent' } });
    expect(validateAnswers(schema.value, { strategy: 'full', trafficPercent: 100 })).toMatchObject({ ok: true });
  });

  it('accepts the research intake form and validates its array answer', () => {
    const paths = ['/form/researchQuestion', '/form/background', '/form/evidenceTypes', '/form/confidence'];
    expect(validatePanelSpec(researchIntake.formSpec, { declaredPaths: paths })).toMatchObject({ ok: true });
    const schema = validateAnswerSchema(researchIntake.answerSchema);
    expect(schema).toMatchObject({ ok: true });
    if (!schema.ok) return;
    expect(validateAnswers(schema.value, researchIntake.defaults)).toMatchObject({ ok: true });
    expect(validateAnswers(schema.value, {
      researchQuestion: 'Which workflow reduces review time?',
      background: 'The team needs evidence for a focused tooling decision.',
      evidenceTypes: ['literature-review', 'benchmarks'],
      confidence: 0.75,
    })).toMatchObject({ ok: true });
  });

  it('omits inactive conditional answer paths', () => {
    const schema = {
      type: 'object',
      properties: { mode: { type: 'string', enum: ['short', 'long'] } },
      required: ['mode'],
      additionalProperties: false,
      allOf: [{ if: { properties: { mode: { enum: ['short'] } } }, then: { properties: { detail: { type: 'string' } }, required: ['detail'] }, else: { properties: { reason: { type: 'string' } }, required: ['reason'] } }],
    };
    const accepted = validateAnswerSchema(schema);
    expect(accepted.ok).toBe(true);
    if (!accepted.ok) return;
    expect(validateAnswers(accepted.value, { mode: 'short', detail: 'x' })).toMatchObject({ ok: true });
    expect(validateAnswers(accepted.value, { mode: 'short', reason: 'wrong' })).toMatchObject({ ok: false, error: { path: '/reason' } });
    expect(validateAnswers(accepted.value, { mode: 'long', detail: 'wrong' })).toMatchObject({ ok: false, error: { path: '/detail' } });
    expect(validateAnswers(accepted.value, { mode: 'long' })).toMatchObject({ ok: false, error: { path: '/reason' } });
  });
});

describe('invalid spec fixtures', () => {
  it.each([
    [cycle, '/elements/b/children/0'],
    [overDeep, '/elements/n11/children/0'],
    [overLarge, '/elements'],
    [unknownComponent, '/elements/main/type'],
    [unknownAction, '/elements/submit/on/press/action'],
    [unsafePointer, '/elements/main/props/value/$state'],
    [unknownProp, '/elements/main/props/fontFamily'],
  ] as const)('rejects the fixture at %s', (fixture, path) => {
    const result = validatePanelSpec(fixture, { declaredPaths: ['/task/__proto__'] });
    expect(result).toMatchObject({ ok: false, error: { code: 'invalid_spec', path } });
  });
});

describe('invalid answer fixtures', () => {
  it('rejects unsupported keywords explicitly', () => {
    expect(validateAnswerSchema(unsupportedSchemaKeyword)).toMatchObject({ ok: false, error: { code: 'invalid_answers', keyword: 'pattern', path: '/properties/name/pattern' } });
  });

  it('rejects a giant array using the bounded array schema', () => {
    const schema = { type: 'object', properties: { values: { type: 'array', items: { type: 'integer' }, maxItems: 200 } }, required: ['values'], additionalProperties: false };
    expect(validateAnswers(schema, { values: giantArray })).toMatchObject({ ok: false, error: { code: 'invalid_answers', path: '/values' } });
  });
});
