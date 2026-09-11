// Verifies multi-choice answers survive questionnaire completion and card dismissal.
// Covers array validation, accepted-answer discovery, and immutable result readback.
// Dependencies: authenticated Worker/D1 fixtures and Vitest; run on a grok host.

import { SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { base, bossHeaders, create, finish, publishPanel, questionnaire, read, setup, submit } from './support';

beforeAll(setup);

describe('multi-choice questionnaire completion', () => {
  it('preserves both choices when the completed card is dismissed immediately', async () => {
    const panelId = await publishPanel();
    const response = await create(panelId, {
      ...questionnaire, defaults: { features: [] },
      answerSchema: {
        type: 'object', additionalProperties: false, required: ['features'],
        properties: { features: { type: 'array', uniqueItems: true, items: { type: 'string', enum: ['media', 'live', 'draft'] } } },
      },
      formSpec: { root: 'features', elements: { features: {
        type: 'MultiSelect', children: [], props: {
          label: 'Features', value: { $bindState: '/form/features' },
          options: ['media', 'live', 'draft'].map(id => ({ id, label: id })),
        },
      } } },
    });
    expect(response.status).toBe(201);
    const { requestId } = await response.json<{ requestId: string }>();
    expect((await submit(requestId, { features: ['media', 'media'] })).status).toBe(422);
    expect((await submit(requestId, { features: ['unknown'] })).status).toBe(422);
    const answers = { features: ['draft', 'media'] };
    expect((await submit(requestId, answers)).status).toBe(201);
    const pending = await SELF.fetch(`${base}/interaction-requests`, { headers: bossHeaders });
    expect((await pending.json<{ requests: { requestId: string }[] }>()).requests.map(row => row.requestId)).not.toContain(requestId);
    expect((await finish(panelId, { dismissal: { policy: 'immediate' } })).status).toBe(200);
    const panel = await SELF.fetch(`${base}/panels/${panelId}`, { headers: bossHeaders });
    expect(await panel.json()).toMatchObject({ lifecycle: { taskState: 'completed', dismissalPolicy: 'immediate' } });
    expect(await (await read(requestId)).json()).toMatchObject({ state: 'accepted', submission: { answers } });
    expect((await submit(requestId, { features: [] })).status).toBe(409);
  });
});
