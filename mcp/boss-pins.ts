// Boss public keys pinned on this machine by the CLI (`hiboss setup`, `hiboss boss keys --pin`, `trust`).
// Exports trustedKey: the bytes a boss signature must verify against, per the CLI's rules.
// Reads <dir of the real config>/boss-keys/*.json; depends on node:fs/path and ./config.js.

import { readdirSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { configPath } from './config.js';

interface PinFile {
  boss_id: string;
  keys: { key_id: string; public_key: string }[];
  revoked?: { key_id: string }[];
}

let override: PinFile[] | undefined;

/** Tests set pins here instead of reading the machine's files. */
export function setPinsForTest(pins: PinFile[] | undefined): void { override = pins; }

function pinsDir(env: NodeJS.ProcessEnv = process.env): string {
  const config = configPath(env);
  let real = config;
  try { real = realpathSync(config); } catch { /* config may be env-only */ }
  return join(dirname(real), 'boss-keys');
}

function loadAll(): PinFile[] {
  if (override) return override;
  const dir = pinsDir();
  let names: string[];
  try { names = readdirSync(dir).filter((name) => name.endsWith('.json')); } catch { return []; }
  return names.flatMap((name) => {
    try { return [JSON.parse(readFileSync(join(dir, name), 'utf8')) as PinFile]; } catch { return []; }
  });
}

/**
 * The pinned key's base64url bytes when pinned; the offered key only while nothing is pinned.
 * Throws for a revoked key, or an unknown key once this machine pins anything.
 */
export function trustedKey(bossId: string, keyId: string, offered: string): string {
  const all = loadAll();
  const pins = all.find((file) => file.boss_id === bossId);
  if (pins?.revoked?.some((key) => key.key_id === keyId)) throw new Error('signing key revoked on this machine');
  const pinned = pins?.keys.find((key) => key.key_id === keyId);
  if (pinned) return pinned.public_key;
  const anyPins = all.some((file) => file.keys.length > 0 || (file.revoked?.length ?? 0) > 0);
  if (anyPins) throw new Error('signed by a key this machine has not pinned; run `hiboss boss keys`');
  return offered;
}
