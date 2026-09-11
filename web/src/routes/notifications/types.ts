// Notification inventory and mutation contracts shared by the page and its client.
// Exports destination/provider models; depends only on domain literal types.
export type DestinationId = string & { readonly __brand: 'DestinationId' };
export type ProviderId = string & { readonly __brand: 'ProviderId' };
export type Priority = 'low' | 'normal' | 'high' | 'critical';
export type Kind = 'telegram_chat' | 'discord_channel' | 'apns' | 'native_live';
export type Mode = 'off' | 'shadow' | 'on';
export interface Provider { id: ProviderId; provider: 'telegram' | 'discord'; label: string; created_at: string }
export interface Destination {
  id: DestinationId; kind: Kind; label: string; target: string; provider_id: ProviderId | null;
  provider_label: string | null; enabled: number; min_priority: Priority; honours_quiet_hours: number; route_count: number;
}
export interface Inventory { destinations: Destination[]; providers: Provider[]; mode: Mode }
export interface DestinationInput {
  kind: 'telegram_chat' | 'discord_channel'; label: string; provider_id: ProviderId;
  target: { chat_id: string; message_thread_id?: number } | { channel_id: string; thread_id?: string };
}
export interface ProviderInput { provider: 'telegram' | 'discord'; label: string; credentials: { bot_token?: string; webhook_url?: string } }
export type DestinationPatch = Partial<Pick<Destination, 'label' | 'min_priority'>> & { enabled?: boolean; honours_quiet_hours?: boolean };
export const PRIORITIES: Priority[] = ['low', 'normal', 'high', 'critical'];
export const KIND_ICONS: Record<Kind, string> = { telegram_chat: '➤', discord_channel: '#', apns: '▣', native_live: '◉' };
export function targetLabel(row: Destination): string {
  try {
    const target: Record<string, unknown> = JSON.parse(row.target);
    const id = target.chat_id ?? target.channel_id ?? target.device_id ?? '';
    const thread = target.message_thread_id ?? target.thread_id;
    return thread ? `${id} / ${thread}` : String(id);
  } catch { return ''; }
}
