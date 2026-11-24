// Validates server-owned embed JSON and groups inline fields.
// The renderer handles every text value with embeds disabled.

export interface EmbedField { name: string; value: string; inline?: boolean }
export interface Embed {
	text?: string;
	color?: number | null;
	title?: string;
	url?: string;
	author?: string;
	description?: string;
	fields?: EmbedField[];
	image?: string;
	thumbnail?: string;
	footer?: string;
	timestamp?: string;
}

export function decodeEmbed(source: string): Embed | undefined {
	try {
		if (source.includes('\n')) return;
		const value: unknown = JSON.parse(source);
		if (!value || typeof value !== 'object' || Array.isArray(value)) return;
		const record = value as Record<string, unknown>;
		const embed: Embed = {};
		for (const key of ['text', 'title', 'url', 'author', 'description', 'image',
			'thumbnail', 'footer', 'timestamp'] as const) {
			const field = record[key];
			if (field == null) continue;
			if (typeof field !== 'string') return;
			embed[key] = field;
		}
		if (typeof record.color === 'number' && Number.isInteger(record.color)
			&& record.color >= 0 && record.color <= 0xffffff) embed.color = record.color;
		if (record.fields != null) {
			if (!Array.isArray(record.fields) || !record.fields.every(isField)) return;
			embed.fields = record.fields;
		}
		return Object.keys(embed).length ? embed : undefined;
	} catch {
		return;
	}
}

function isField(field: unknown): field is EmbedField {
	if (!field || typeof field !== 'object') return false;
	const value = field as Record<string, unknown>;
	return typeof value.name === 'string' && typeof value.value === 'string'
		&& (value.inline === undefined || typeof value.inline === 'boolean');
}

export function fieldRows(fields: EmbedField[]): EmbedField[][] {
	const rows: EmbedField[][] = [];
	for (const field of fields) {
		const last = rows.at(-1);
		if (field.inline && last?.[0].inline && last.length < 3) last.push(field);
		else rows.push([field]);
	}
	return rows;
}
