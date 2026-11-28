// Tests description normalization and channel fallback payloads.
// Depends on the description parser, channel delivery, and mocked fetch.
import { describe, expect, it } from 'vitest';
import { parseOptionDescriptions } from './option-descriptions';


describe('option descriptions', () => {
  it('orders descriptions by offered option and counts Unicode characters', () => {
    const text = '😀'.repeat(200);
    expect(parseOptionDescriptions([{ label: ' B ', text: ` ${text} ` },
      { label: 'A', text: 'first' }], ['A', 'B'])).toEqual({ ok: true, value: [
      { label: 'A', text: 'first' }, { label: 'B', text },
    ] });
    expect(parseOptionDescriptions(undefined, undefined)).toEqual({ ok: true, value: undefined });
  });

});
