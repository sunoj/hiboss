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
  return {
    baseUrl,
    headers: {
      Authorization: `Bearer ${key}`,
      Accept: 'application/json',
    },
    defaultChannel: channel,
  };
}
