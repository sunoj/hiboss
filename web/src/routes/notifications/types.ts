// Notification inventory and mutation contracts for HiBoss client destinations.
// Shared by the Delivery view and its authenticated client.
export type DestinationId = string & { readonly __brand: 'DestinationId' };
export type Priority = 'low' | 'normal' | 'high' | 'critical';
export type Kind = 'apns' | 'native_live';
export type Mode = 'off' | 'shadow' | 'on';

export interface Destination {
  id: DestinationId;
  kind: Kind;
  label: string;
  target: string;
  enabled: number;
  min_priority: Priority;
  honours_quiet_hours: number;
  route_count: number;
}

export interface Inventory {
  destinations: Destination[];
  mode: Mode;
}

export type DestinationPatch = Partial<Pick<Destination, 'label' | 'min_priority'>> & {
  enabled?: boolean;
  honours_quiet_hours?: boolean;
};

export const PRIORITIES: Priority[] = ['low', 'normal', 'high', 'critical'];
export const KIND_ICONS: Record<Kind, string> = { apns: '▣', native_live: '◉' };

export function targetLabel(row: Destination): string {
  try {
    const target: Record<string, unknown> = JSON.parse(row.target);
    return String(target.device_id ?? '');
  } catch {
    return '';
  }
}
