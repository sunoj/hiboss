// Device enrolment contracts: request parsing and stored join-request rows.
// Exports parseJoinPayload, JoinProfile, JoinRequestRow and delivery types.
// Pure validation; no D1 or Hono dependencies.

export interface JoinProfile { profile: string; name: string }
export interface JoinDevice { label: string; host: string | null }
export interface JoinPayload { device: JoinDevice; profiles: JoinProfile[]; invite: string | null }

export interface DeliveredProfile extends JoinProfile { agent_id: string; key: string }
export interface Delivery { device_id: string; profiles: DeliveredProfile[] }

export interface JoinRequestRow {
  id: string;
  status: 'pending' | 'approved' | 'rejected';
  device_label: string;
  device_host: string | null;
  device_id: string | null;
  profiles: string;
  invite_id: string | null;
  inviter_label: string | null;
  verification_code: string | null;
  delivery: string | null;
  created_at: string;
  updated_at: string;
}

export const MAX_PROFILES = 8;
const PROFILE_PATTERN = /^[a-z][a-z0-9-]{0,31}$/;
const NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._@+-]{0,99}$/;
const LABEL_PATTERN = /^[^<>&\u0000-\u001f]{1,64}$/;
const HOST_PATTERN = /^[A-Za-z0-9.-]{1,253}$/;
const INVITE_PATTERN = /^hb_inv_[0-9a-f]{64}$/;

/** Returns the parsed payload or a human-readable reason for a 400. */
export function parseJoinPayload(value: unknown): JoinPayload | string {
  if (!isRecord(value)) return 'body must be an object';
  if ('name' in value && !('profiles' in value)) {
    return 'this server enrols devices with profiles; upgrade the hiboss CLI and run: hiboss setup';
  }
  const device = parseDevice(value.device);
  if (typeof device === 'string') return device;
  const invite = value.invite ?? null;
  if (invite !== null && (typeof invite !== 'string' || !INVITE_PATTERN.test(invite))) return 'invite is malformed';
  if (!Array.isArray(value.profiles) || value.profiles.length === 0) return 'profiles must be a non-empty array';
  if (value.profiles.length > MAX_PROFILES) return `at most ${MAX_PROFILES} profiles per request`;
  const profiles: JoinProfile[] = [];
  for (const entry of value.profiles) {
    const profile = parseProfile(entry);
    if (typeof profile === 'string') return profile;
    if (profiles.some(p => p.profile === profile.profile || p.name === profile.name)) {
      return `duplicate profile or name: ${profile.profile}`;
    }
    profiles.push(profile);
  }
  return { device, profiles, invite: typeof invite === 'string' ? invite : null };
}

function parseDevice(value: unknown): JoinDevice | string {
  if (!isRecord(value)) return 'device must be an object with a label';
  const label = typeof value.label === 'string' ? value.label.trim() : '';
  if (!LABEL_PATTERN.test(label)) return 'device.label must be 1-64 printable characters';
  const host = typeof value.host === 'string' && value.host.trim() ? value.host.trim() : null;
  if (host !== null && !HOST_PATTERN.test(host)) return 'device.host must be a hostname';
  return { label, host };
}

function parseProfile(value: unknown): JoinProfile | string {
  if (!isRecord(value)) return 'each profile must be an object';
  const profile = typeof value.profile === 'string' ? value.profile.trim() : '';
  const name = typeof value.name === 'string' ? value.name.trim() : '';
  if (!PROFILE_PATTERN.test(profile)) return 'profile must match ^[a-z][a-z0-9-]{0,31}$';
  if (!NAME_PATTERN.test(name)) return 'agent name must be 1-100 characters of A-Z a-z 0-9 . _ @ + -';
  return { profile, name };
}

export function parseStoredProfiles(json: string): JoinProfile[] {
  try {
    const value: unknown = JSON.parse(json);
    return Array.isArray(value) ? value.map(parseProfile).filter((p): p is JoinProfile => typeof p !== 'string') : [];
  } catch {
    return [];
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}
