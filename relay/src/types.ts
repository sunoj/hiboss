// Shared types for the push relay Worker.
// Exports the Worker bindings, Hono app environment and push vocabulary.

export interface Env {
  DB: D1Database;
  PUSH_RATE_LIMITER: RateLimit;
  REGISTRATION_RATE_LIMITER: RateLimit;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_AUTH_KEY?: string;
  GLOBAL_DAILY_PUSH_LIMIT?: string;
}

export type AppEnv = { Bindings: Env };

export type ApnsEnvironment = 'sandbox' | 'production';
export type PushKind = 'decision' | 'message' | 'system';

export interface TokenBody {
  apnsToken: string;
  environment: ApnsEnvironment;
}

export interface PushBody {
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
