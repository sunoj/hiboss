// Boss public keys pinned on this machine by the CLI (`hiboss setup`, `hiboss boss keys --pin`, `trust`).
// Exports trustedKey: the bytes a boss signature must verify against, per the CLI's rules.
// Reads <dir of the real config>/boss-keys/*.json; depends on node:fs/path and ./config.js.

import { readdirSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { configPath } from './config.js';

interface PinFile {
  boss_id: string;
  keys?: { key_id: string; public_key: string }[] | null;
  revoked?: { key_id: string; revoked_at?: string; public_key?: string | null }[] | null;
}

interface PinStore { files: PinFile[]; damaged: boolean }

let override: PinStore | undefined;

/** Tests set pins here instead of reading the machine's files. */
export function setPinsForTest(pins: PinFile[] | undefined, damaged = false): void {
  override = pins === undefined ? undefined : { files: pins, damaged };
}

function pinsDir(env: NodeJS.ProcessEnv = process.env): string {
  const config = configPath(env);
  let real = config;
  try { real = realpathSync(config); } catch { /* config may be env-only */ }
  return join(dirname(real), 'boss-keys');
}

/** A file that cannot be read marks the store damaged, which never falls back to the offered key. */
function loadStore(): PinStore {
  if (override) return override;
  const dir = pinsDir();
  let names: string[];
  try { names = readdirSync(dir).filter((name) => name.endsWith('.json')); } catch { return { files: [], damaged: false }; }
  const store: PinStore = { files: [], damaged: false };
  for (const name of names) {
    try {
      const file = JSON.parse(readFileSync(join(dir, name), 'utf8')) as PinFile;
      if (typeof file?.boss_id === 'string') store.files.push(file); else store.damaged = true;
    } catch { store.damaged = true; }
  }
  return store;
}

/** Unix seconds from RFC 3339 or SQLite's `YYYY-MM-DD HH:MM:SS` (UTC). */
function parseTime(value: string | undefined): number | undefined {
  if (!value) return undefined;
  const iso = value.includes('T') ? value : `${value.replace(' ', 'T')}Z`;
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? undefined : Math.floor(ms / 1000);
}

/**
 * The pinned key's base64url bytes when pinned; the offered key only while nothing is pinned.
 * Throws for a revoked key, or an unknown key once this machine pins anything.
 */
export function trustedKey(bossId: string, keyId: string, offered: string, issuedAt: number): string {
  const store = loadStore();
  const pins = store.files.find((file) => file.boss_id === bossId);
  const revoked = pins?.revoked?.find((key) => key.key_id === keyId);
  if (revoked) {
    // History stays readable: a signature made before the revocation still counts.
    const at = parseTime(revoked.revoked_at);
    if (revoked.public_key && at !== undefined && issuedAt < at) return revoked.public_key;
    throw new Error('signing key revoked on this machine');
  }
  const pinned = pins?.keys?.find((key) => key.key_id === keyId);
  if (pinned) return pinned.public_key;
  const anyPins = store.damaged
    || store.files.some((file) => (file.keys?.length ?? 0) > 0 || (file.revoked?.length ?? 0) > 0);
  if (anyPins) throw new Error('signed by a key this machine has not pinned; run `hiboss boss keys`');
  return offered;
}
