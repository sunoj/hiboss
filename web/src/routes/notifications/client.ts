// Typed HTTP client for the current boss's notification settings and probes.
// Exports NotificationsClient; depends on the shared authenticated client and ApiError.
import type { BossApiClient } from '$lib/api/client';
import { ApiError } from '$lib/api/types';
import type { Destination, DestinationId, DestinationInput, DestinationPatch, Inventory, Provider, ProviderInput } from './types';
export class NotificationsClient {
  constructor(private readonly connection: Pick<BossApiClient, 'baseUrl' | 'token'>) {}
  inventory(): Promise<Inventory> { return this.request('GET', '/destinations'); }
  create(input: DestinationInput): Promise<{ destination: Destination }> { return this.request('POST', '/destinations', input); }
  patch(id: DestinationId, input: DestinationPatch): Promise<{ destination: Destination }> {
    return this.request('PATCH', `/destinations/${encodeURIComponent(id)}`, input);
  }
  remove(id: DestinationId): Promise<{ ok: true }> { return this.request('DELETE', `/destinations/${encodeURIComponent(id)}`); }
  test(id: DestinationId): Promise<{ ok: true; external_message_id: string | null }> {
    return this.request('POST', `/destinations/${encodeURIComponent(id)}/test`);
  }
  createProvider(input: ProviderInput): Promise<{ provider: Provider }> { return this.request('POST', '/providers', input); }
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
