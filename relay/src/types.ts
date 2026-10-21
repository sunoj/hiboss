// Shared types for the push relay Worker.
// Exports the Worker bindings, Hono app environment and push vocabulary.

export interface Env {
  DB: D1Database;
  PUSH_RATE_LIMITER: RateLimit;
  REGISTRATION_RATE_LIMITER: RateLimit;
  SELF_RATE_LIMITER: RateLimit;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_AUTH_KEY?: string;
}

export type AppEnv = { Bindings: Env };

export type ApnsEnvironment = 'sandbox' | 'production';
export type PushKind = 'decision' | 'message' | 'system';
export type ApnsPriority = 5 | 10;
export type InterruptionLevel = 'passive' | 'active' | 'time-sensitive';

/** Urgency metadata the Server derives from its own payload; used verbatim in the APNs request. */
export interface DeliveryLevel {
  priority: ApnsPriority;
  interruption: InterruptionLevel;
  sound: boolean;
}

export interface TokenBody {
  apnsToken: string;
  environment: ApnsEnvironment;
}

export interface PushBody extends DeliveryLevel {
  handle: string;
  kind: PushKind;
  ciphertext: string;
  collapseId?: string;
}

export interface Registration {
  handle_hash: string;
  secret_hash: string;
  apns_token: string;
  environment: ApnsEnvironment;
}
