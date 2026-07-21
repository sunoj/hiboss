/** Lightweight toast queue for SSE / action feedback. */

export type ToastTone = 'info' | 'success' | 'error' | 'warning';

export interface ToastItem {
	id: string;
	message: string;
	tone: ToastTone;
	ttlMs: number;
}

class ToastStore {
	items = $state<ToastItem[]>([]);

	push(message: string, tone: ToastTone = 'info', ttlMs = 4000): string {
		const id = `t-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
		this.items = [...this.items, { id, message, tone, ttlMs }];
		if (typeof window !== 'undefined') {
			window.setTimeout(() => this.dismiss(id), ttlMs);
		}
		return id;
	}

	dismiss(id: string): void {
		this.items = this.items.filter((t) => t.id !== id);
	}

	clear(): void {
		this.items = [];
	}
}

export const toasts = new ToastStore();
