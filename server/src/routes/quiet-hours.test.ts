// Unit tests for quiet-hours window detection and UTC scheduling conversion.
// Covers overnight windows, daytime windows, and next-end calculation.
// Depends on Vitest and the quiet-hours helper module.

import { describe, expect, it } from 'vitest';
import { getQuietHoursEnd, isInQuietHours } from './quiet-hours';

describe('isInQuietHours', () => {
  it('returns false when quiet hours are incomplete', () => {
    expect(isInQuietHours(null, '08:00', 'Asia/Bangkok')).toBe(false);
    expect(isInQuietHours('22:00', null, 'Asia/Bangkok')).toBe(false);
  });

  it('handles overnight quiet hours', () => {
    const inside = new Date('2026-04-04T16:30:00.000Z');
    const outside = new Date('2026-04-04T03:30:00.000Z');
    expect(isInQuietHours('22:00', '08:00', 'Asia/Bangkok', inside)).toBe(true);
    expect(isInQuietHours('22:00', '08:00', 'Asia/Bangkok', outside)).toBe(false);
  });

  it('handles same-day quiet hours', () => {
    const inside = new Date('2026-04-04T06:30:00.000Z');
    const outside = new Date('2026-04-04T10:30:00.000Z');
    expect(isInQuietHours('13:00', '17:00', 'Asia/Bangkok', inside)).toBe(true);
    expect(isInQuietHours('13:00', '17:00', 'Asia/Bangkok', outside)).toBe(false);
  });
});

describe('getQuietHoursEnd', () => {
  it('returns the same local-day end when it is still upcoming', () => {
    const now = new Date('2026-04-04T00:30:00.000Z');
    expect(getQuietHoursEnd('08:00', 'Asia/Bangkok', now).toISOString()).toBe('2026-04-04T01:00:00.000Z');
  });

  it('returns the next local-day end when today has already passed', () => {
    const now = new Date('2026-04-04T16:30:00.000Z');
    expect(getQuietHoursEnd('08:00', 'Asia/Bangkok', now).toISOString()).toBe('2026-04-05T01:00:00.000Z');
  });
});
