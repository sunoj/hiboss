// Typed HTTP client for the current boss's notification settings and probes.
// Exports NotificationsClient; depends on the shared authenticated client and ApiError.
import type { BossApiClient } from '$lib/api/client';
import { ApiError } from '$lib/api/types';
import type { Destination, DestinationId, DestinationPatch, Inventory } from './types';
export class NotificationsClient {
  constructor(private readonly connection: Pick<BossApiClient, 'baseUrl' | 'token'>) {}
  async inventory(): Promise<Inventory> {
    type ServerDestination = Omit<Destination, 'kind'> & { kind: string };
    const { destinations, mode } = await this.request<{
      destinations: ServerDestination[]; mode: Inventory['mode'];
    }>('GET', '/destinations');
    return {
      mode,
      destinations: destinations.filter((row): row is Destination =>
        row.kind === 'apns' || row.kind === 'native_live')
    };
  }
  patch(id: DestinationId, input: DestinationPatch): Promise<{ destination: Destination }> {
    return this.request('PATCH', `/destinations/${encodeURIComponent(id)}`, input);
  }
  test(id: DestinationId): Promise<{ ok: true; external_message_id: string | null }> {
    return this.request('POST', `/destinations/${encodeURIComponent(id)}/test`);
  }
  private async request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const response = await fetch(`${this.connection.baseUrl}/api/boss${path}`, {
      method, headers: { Authorization: `Bearer ${this.connection.token}`, Accept: 'application/json',
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    const text = await response.text();
    if (!response.ok) throw new ApiError(response.status, text || response.statusText);
    return JSON.parse(text) as T;
  }
}
