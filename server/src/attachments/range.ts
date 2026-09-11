// Parses a single HTTP byte range without losing precision on large numerals.
// Exports parseByteRange and its explicit full/partial/unsatisfiable result.
// Dependencies: standard BigInt; callers supply the stored object size.

export type ByteRange =
  | { kind: 'full' }
  | { kind: 'unsatisfiable' }
  | { kind: 'partial'; offset: number; length: number };

export function parseByteRange(value: string | null, size: number): ByteRange {
  if (!value) return { kind: 'full' };
  const match = /^bytes=(\d*)-(\d*)$/i.exec(value.trim());
  if (!match || (!match[1] && !match[2])) return { kind: 'full' };
  const total = BigInt(size);
  if (!match[1]) {
    const suffix = BigInt(match[2]);
    if (suffix === 0n || total === 0n) return { kind: 'unsatisfiable' };
    const length = suffix < total ? suffix : total;
    return { kind: 'partial', offset: Number(total - length), length: Number(length) };
  }
  const start = BigInt(match[1]);
  const end = match[2] ? BigInt(match[2]) : total - 1n;
  if (match[2] && end < start) return { kind: 'full' };
  if (start >= total) return { kind: 'unsatisfiable' };
  const last = end < total ? end : total - 1n;
  return { kind: 'partial', offset: Number(start), length: Number(last - start + 1n) };
}
