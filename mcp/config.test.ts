// Covers MCP config path parity, profile selection, and ephemeral credentials.
// Tests loadConfig/configPath against isolated temporary v2 files without network calls.

import { afterEach, describe, expect, it } from 'bun:test';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { configPath, loadConfig } from './config';

const temporary: string[] = [];
const valid = {
  version: 2, server: 'https://shared.example', default_profile: 'codex',
  profiles: {
    claude: { key: 'hb_claude', agent_id: 'c', name: 'alice-claude@host' },
    codex: { key: 'hb_codex', server: 'https://codex.example' },
  },
};

function fixture(value: unknown): string {
  const dir = mkdtempSync(join(tmpdir(), 'hiboss-mcp-config-'));
  temporary.push(dir);
  const path = join(dir, 'config.json');
  writeFileSync(path, JSON.stringify(value));
  return path;
}

afterEach(() => {
  for (const path of temporary.splice(0)) rmSync(path, { recursive: true });
});

describe('configPath', () => {
  it('honors HIBOSS_CONFIG and platform config directories', () => {
    expect(configPath({ HIBOSS_CONFIG: '/custom/config.json' }, 'darwin', '/home/me')).toBe('/custom/config.json');
    expect(configPath({}, 'darwin', '/Users/me')).toBe('/Users/me/Library/Application Support/hiboss/config.json');
    expect(configPath({ XDG_CONFIG_HOME: '/custom/xdg' }, 'linux', '/home/me')).toBe('/custom/xdg/hiboss/config.json');
    expect(configPath({ XDG_CONFIG_HOME: 'relative' }, 'linux', '/home/me')).toBe('/home/me/.config/hiboss/config.json');
    expect(configPath({ APPDATA: 'C:\\Users\\me\\AppData\\Roaming' }, 'win32', '/home/me')).toBe(join('C:\\Users\\me\\AppData\\Roaming', 'hiboss', 'config.json'));
    expect(() => configPath({ HIBOSS_CONFIG: '' })).toThrow('HIBOSS_CONFIG is empty');
  });
});

describe('loadConfig', () => {
  it('defaults to claude even when the file default profile differs', () => {
    expect(loadConfig({ HIBOSS_CONFIG: fixture(valid) })).toEqual({ server: 'https://shared.example', key: 'hb_claude' });
  });

  it('selects an explicit profile and its server override', () => {
    expect(loadConfig({ HIBOSS_CONFIG: fixture(valid), HIBOSS_PROFILE: 'codex' })).toEqual({
      server: 'https://codex.example', key: 'hb_codex',
    });
  });

  it('uses the ephemeral pair without touching the config file', () => {
    expect(loadConfig({ HIBOSS_CONFIG: '/missing/config.json', HIBOSS_PROFILE: 'missing', HIBOSS_SERVER: 'https://ephemeral.example', HIBOSS_KEY: 'hb_temp' }))
      .toEqual({ server: 'https://ephemeral.example', key: 'hb_temp' });
    expect(() => loadConfig({ HIBOSS_SERVER: 'https://ephemeral.example' })).toThrow('HIBOSS_KEY');
    expect(() => loadConfig({ HIBOSS_KEY: 'hb_temp' })).toThrow('HIBOSS_SERVER');
  });

  it('reports missing profiles and rejects legacy or malformed configuration', () => {
    const path = fixture(valid);
    expect(() => loadConfig({ HIBOSS_CONFIG: path, HIBOSS_PROFILE: ' ' })).toThrow('HIBOSS_PROFILE is empty');
    expect(() => loadConfig({ HIBOSS_CONFIG: path, HIBOSS_PROFILE: 'aid' }))
      .toThrow("profile 'aid' is not set up; run: hiboss setup --profile aid");
    for (const value of [
      { server: 'https://legacy.example', key: 'hb_legacy' },
      { version: 2, server: 'https://example', profiles: { claude: { key: '' } } },
      { version: 2, profiles: { claude: { key: 'hb_key' } } },
      { ...valid, api_key: 'synthetic-secret' },
      { ...valid, profiles: { claude: { key: 'hb_key', server_url: 'https://old.example' } } },
    ]) {
      expect(() => loadConfig({ HIBOSS_CONFIG: fixture(value) })).toThrow();
    }
    expect(() => loadConfig({ HIBOSS_CONFIG: '/missing/config.json' })).toThrow('cannot read v2 hiboss config');
  });
});
