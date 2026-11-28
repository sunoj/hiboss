// Validates per-option descriptions and composes channel fallback text.
// Exports metadata parsing and body formatting without changing stored message bodies.

export interface OptionDescription { label: string; text: string }

type ParseResult =
  | { ok: true; value: OptionDescription[] | undefined }
  | { ok: false; error: string };

export function parseOptionDescriptions(value: unknown, options: string[] | undefined): ParseResult {
  if (value === undefined) return { ok: true, value: undefined };
  if (!options) return { ok: false, error: 'option_descriptions requires options' };
  if (!Array.isArray(value) || value.length === 0 || value.length > options.length) {
    return { ok: false, error: 'option_descriptions must contain 1 to the number of options entries' };
  }
  const descriptions: OptionDescription[] = [];
  const seen = new Set<string>();
  for (const [index, raw] of value.entries()) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
      return { ok: false, error: `option_descriptions[${index}] must be an object` };
    }
    const item = raw as Record<string, unknown>;
    const label = typeof item.label === 'string' ? item.label.trim() : '';
    if (!label || !options.includes(label)) {
      return { ok: false, error: `option_descriptions[${index}].label must match an option` };
    }
    if (seen.has(label)) return { ok: false, error: `option_descriptions label '${label}' must be unique` };
    const text = typeof item.text === 'string' ? item.text.trim() : '';
    if (!text || Array.from(text).length > 200) {
      return { ok: false, error: `option_descriptions[${index}].text must contain 1 to 200 characters` };
    }
    seen.add(label);
    descriptions.push({ label, text });
  }
  return { ok: true, value: options.flatMap(label => descriptions.filter(item => item.label === label)) };
}
