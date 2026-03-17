// Loads hiboss configuration from the environment or ~/.config/hiboss/config.json.
// Provides a typed HibossContext (base URL, headers, default channel) for HTTP helpers.
// Depends on Node OS/FS primitives and the MCP formatting helpers for error text.

import os from 'node:os';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { getErrorMessage } from './format.js';

type ConfigFile = { server?: string; key?: string; channel?: string };

export type HibossContext = {
  baseUrl: URL;
  headers: Record<string, string>;
  defaultChannel?: string;
  sessionId?: string;
};

const CONFIG_PATH = path.join(os.homedir(), '.config', 'hiboss', 'config.json');

export async function loadHibossContext(): Promise<HibossContext> {
  const envServer = process.env.HIBOSS_SERVER;
  const envKey = process.env.HIBOSS_KEY;
  const envChannel = process.env.HIBOSS_CHANNEL;
  if (envServer && envKey) {
    return buildContext(envServer, envKey, envChannel);
  }
  const fileConfig = await readConfigFile();
  if (fileConfig.server && fileConfig.key) {
    return buildContext(fileConfig.server, fileConfig.key, envChannel ?? fileConfig.channel);
  }
  throw new Error(
    'HIBOSS_SERVER/HIBOSS_KEY missing and ~/.config/hiboss/config.json could not provide a valid server/key.',
  );
}

async function readConfigFile(): Promise<ConfigFile> {
  try {
    const contents = await readFile(CONFIG_PATH, 'utf8');
    const parsed = JSON.parse(contents);
    if (parsed && typeof parsed === 'object') {
      return parsed as ConfigFile;
    }
    throw new Error('Config file did not contain an object.');
  } catch (error) {
    throw new Error(`Unable to load hiboss config at ${CONFIG_PATH}: ${getErrorMessage(error)}`);
  }
}

function buildContext(server: string, key: string, channel?: string): HibossContext {
  if (!server) {
    throw new Error('Hiboss server URL is empty.');
  }
  if (!key) {
    throw new Error('Hiboss API key is empty.');
  }
  const baseUrl = new URL(server);
  // Read session ID from the same file the CLI writes
  const sessionId = readSessionId();
  return {
    baseUrl,
    headers: {
      Authorization: `Bearer ${key}`,
      Accept: 'application/json',
    },
    defaultChannel: channel,
    sessionId,
  };
}

function readSessionId(): string | undefined {
  try {
    // Compute project hash same as CLI (FNV-1a of cwd)
    const cwd = process.cwd();
    let h = BigInt('0xcbf29ce484222325');
    for (let i = 0; i < cwd.length; i++) {
      h ^= BigInt(cwd.charCodeAt(i));
      h = BigInt.asUintN(64, h * BigInt('0x100000001b3'));
    }
    const hash = h.toString(16).padStart(16, '0');
    const sessionFile = `/tmp/hiboss-session-${hash}`;
    const fs = require('node:fs');
    const content = fs.readFileSync(sessionFile, 'utf8').trim();
    return content || undefined;
  } catch {
    return undefined;
  }
}
