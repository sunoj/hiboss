// Boss public keys pinned on this machine by the CLI (`hiboss setup`, `hiboss boss keys --pin`, `trust`).
// Exports trustedKey: the bytes a boss signature must verify against, per the CLI's rules.
// Reads <dir of the real config>/boss-keys/*.json; depends on node:fs/path and ./config.js.

import { readdirSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { configPath } from './config.js';

interface PinFile {
  boss_id: string;
  keys?: { key_id: string; public_key: string }[] | null;
  revoked?: { key_id: string }[] | null;
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
  try {
    names = readdirSync(dir).filter((name) => name.endsWith('.json'));
  } catch (error) {
    // Missing means nothing pinned; a directory that exists but cannot be listed is damaged.
    return { files: [], damaged: (error as NodeJS.ErrnoException).code !== 'ENOENT' };
  }
  const store: PinStore = { files: [], damaged: false };
  for (const name of names) {
    try {
      const file = JSON.parse(readFileSync(join(dir, name), 'utf8')) as PinFile;
      if (isPinFile(file)) store.files.push(file); else store.damaged = true;
    } catch { store.damaged = true; }
  }
  return store;
}

function isPinFile(value: unknown): value is PinFile {
  const file = value as PinFile | null;
  const list = (items: unknown, field: string) => items == null
    || (Array.isArray(items) && items.every((item) => typeof (item as Record<string, unknown>)?.[field] === 'string'));
  // The CLI always writes `keys`; a file without it is not one of ours.
  return typeof file?.boss_id === 'string' && Array.isArray(file.keys)
    && list(file.keys, 'key_id') && list(file.revoked, 'key_id');
}

/**
 * The pinned key's base64url bytes when pinned; the offered key only while nothing is pinned.
 * Throws for a revoked key, or an unknown key once this machine pins anything.
 */
export function trustedKey(bossId: string, keyId: string, offered: string): string {
  const store = loadStore();
  const pins = store.files.find((file) => file.boss_id === bossId);
  if (pins?.revoked?.some((key) => key.key_id === keyId)) throw new Error('signing key revoked on this machine');
  const pinned = pins?.keys?.find((key) => key.key_id === keyId);
  if (pinned) return pinned.public_key;
  const anyPins = store.damaged
    || store.files.some((file) => (file.keys?.length ?? 0) > 0 || (file.revoked?.length ?? 0) > 0);
  if (anyPins) throw new Error('signed by a key this machine has not pinned; run `hiboss boss keys`');
  return offered;
}
