// Reads the shared v2 hiboss profile configuration for the MCP channel.
// Exports configPath and loadConfig; depends on node filesystem, OS, and path APIs.
// Never writes credentials: migration and setup belong to the CLI.

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

export type Config = { server: string; key: string };
type Environment = NodeJS.ProcessEnv;
const FILE_FIELDS = new Set(['version', 'server', 'device_id', 'default_profile', 'channel', 'profiles']);
const PROFILE_FIELDS = new Set(['key', 'agent_id', 'name', 'server']);

export function configPath(env: Environment = process.env, platform = process.platform, home = homedir()): string {
  if (env.HIBOSS_CONFIG !== undefined) {
    if (!env.HIBOSS_CONFIG.trim()) throw new Error('HIBOSS_CONFIG is empty; provide a config path');
    return env.HIBOSS_CONFIG;
  }
  const base = platform === 'darwin'
    ? join(home, 'Library', 'Application Support')
    : platform === 'win32'
      ? env.APPDATA || join(home, 'AppData', 'Roaming')
      : env.XDG_CONFIG_HOME?.startsWith('/') ? env.XDG_CONFIG_HOME : join(home, '.config');
  return join(base, 'hiboss', 'config.json');
}

export function loadConfig(env: Environment = process.env, platform = process.platform, home = homedir()): Config {
  const server = env.HIBOSS_SERVER?.trim();
  const key = env.HIBOSS_KEY?.trim();
  if (server || key) {
    if (!server || !key) throw new Error(`rule 1: ${server ? 'HIBOSS_KEY' : 'HIBOSS_SERVER'} is missing; HIBOSS_SERVER and HIBOSS_KEY must be set together`);
    return { server, key };
  }
  if (env.HIBOSS_SERVER !== undefined || env.HIBOSS_KEY !== undefined) {
    throw new Error('rule 1: HIBOSS_SERVER and HIBOSS_KEY are missing; set both together');
  }

  const rule = env.HIBOSS_PROFILE !== undefined ? 2 : 3;
  if (env.HIBOSS_PROFILE !== undefined && !env.HIBOSS_PROFILE.trim()) {
    throw new Error('rule 2: HIBOSS_PROFILE is empty; choose a configured profile');
  }
  const profile = env.HIBOSS_PROFILE?.trim() || 'claude';
  const path = configPath(env, platform, home);
  const file = readV2(path, rule, profile);
  const profiles = file.profiles as Record<string, unknown>;
  const selected = Object.hasOwn(profiles, profile) ? profiles[profile] : undefined;
  if (!selected || typeof selected !== 'object' || Array.isArray(selected)) {
    throw new Error(`rule ${rule}: profile '${profile}' is not set up; run: hiboss setup --profile ${profile}`);
  }
  const entry = selected as Record<string, unknown>;
  const resolvedServer = typeof entry.server === 'string' && entry.server.trim() ? entry.server : file.server;
  if (typeof resolvedServer !== 'string' || !resolvedServer.trim() || typeof entry.key !== 'string' || !entry.key.trim()) {
    throw new Error(`rule ${rule}: profile '${profile}' has invalid credentials in ${path}; run: hiboss setup --profile ${profile}`);
  }
  return { server: resolvedServer.trim(), key: entry.key.trim() };
}

function readV2(path: string, rule: number, profile: string): Record<string, unknown> {
  let raw: unknown;
  try {
    raw = JSON.parse(readFileSync(path, 'utf8')) as unknown;
  } catch {
    throw new Error(`rule ${rule}: cannot read v2 hiboss config at ${path}; run: hiboss setup --profile ${profile}`);
  }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new Error(`rule ${rule}: invalid v2 hiboss config at ${path}; run: hiboss setup --profile ${profile}`);
  }
  const file = raw as Record<string, unknown>;
  if (file.version !== 2 || !file.profiles || typeof file.profiles !== 'object' || Array.isArray(file.profiles)
    || typeof file.default_profile !== 'string' || !file.default_profile
    || Object.keys(file).some((field) => !FILE_FIELDS.has(field))
    || (file.server != null && typeof file.server !== 'string')
    || (file.device_id != null && typeof file.device_id !== 'string')
    || (file.channel != null && typeof file.channel !== 'string')
    || Object.values(file.profiles).some((value) => !validProfile(value))) {
    throw new Error(`rule ${rule}: invalid v2 hiboss config at ${path}; run: hiboss setup --profile ${profile}`);
  }
  return file;
}

function validProfile(value: unknown): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const profile = value as Record<string, unknown>;
  return Object.keys(profile).every((field) => PROFILE_FIELDS.has(field))
    && (profile.key == null || typeof profile.key === 'string')
    && (profile.agent_id == null || typeof profile.agent_id === 'string')
    && (profile.name == null || typeof profile.name === 'string')
    && (profile.server == null || typeof profile.server === 'string');
}
