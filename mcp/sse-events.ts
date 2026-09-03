// Parses incremental server-sent event buffers for the MCP transport loop.
// Exports parseEvents while preserving partial event and data state.
// Depends only on async message callbacks.

export interface EventParserState {
  readonly buffer: string;
  readonly event: string;
  readonly data: string;
}

export async function parseEvents(
  buffer: string,
  event: string,
  data: string,
  onMessage: (raw: string) => Promise<void>,
): Promise<EventParserState> {
  const lines = buffer.split('\n');
  buffer = lines.pop() ?? '';
  for (const line of lines) {
    if (line.startsWith('event:')) event = line.slice(6).trim();
    else if (line.startsWith('data:')) data += line.slice(5).trim();
    else if (line === '') {
      if (event === 'message' && data) await onMessage(data);
      event = '';
      data = '';
    }
  }
  return { buffer, event, data };
}
