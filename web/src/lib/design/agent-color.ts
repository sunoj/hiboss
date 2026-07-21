/** Stable hue from agent identity for multi-agent visual distinction. */

const HUES = [210, 160, 35, 280, 12, 190, 320, 55, 145, 240] as const;

export function hashIdentity(input: string): number {
	let hash = 0;
	for (let i = 0; i < input.length; i += 1) {
		hash = (hash * 31 + input.charCodeAt(i)) >>> 0;
	}
	return hash;
}

export function agentHue(name: string | null | undefined): number {
	const key = (name ?? 'unknown').trim() || 'unknown';
	return HUES[hashIdentity(key) % HUES.length] ?? 210;
}

/** CSS color for agent identity dot / chip. */
export function agentColor(name: string | null | undefined): string {
	return `hsl(${agentHue(name)} 62% 58%)`;
}

export function agentInitials(name: string | null | undefined): string {
	const parts = (name ?? '?').trim().split(/[\s._-]+/).filter(Boolean);
	if (parts.length === 0) return '?';
	if (parts.length === 1) return (parts[0] ?? '?').slice(0, 2).toUpperCase();
	const a = parts[0]?.[0] ?? '';
	const b = parts[1]?.[0] ?? '';
	return `${a}${b}`.toUpperCase();
}
