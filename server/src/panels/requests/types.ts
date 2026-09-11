// Durable questionnaire domain contracts shared by storage and HTTP handlers.
// Exports immutable definitions, request heads, and purpose-bound submissions.
// Dependencies: panel-runtime schema/spec types and JSON value contracts.

import type { AnswerSchema, PanelSpec } from '@hiboss/panel-runtime';
import type { JsonValue } from '../definition/types';

export type RequestId = string & { readonly __requestId: unique symbol };
export interface Questionnaire {
  kind: 'intake'; title: string; blocking: boolean; priority: 'low' | 'normal' | 'high' | 'critical';
  expiresAt?: string; catalogId: 'hiboss.panel'; catalogVersion: 1;
  formSpec: PanelSpec; answerSchema: AnswerSchema; defaults: Record<string, JsonValue>; context: Record<string, JsonValue>;
}
export interface RequestRow {
  request_id: RequestId; panel_id: string; revision: number; state: 'open' | 'accepted' | 'withdrawn';
  expires_at: string | null; blocking: number; idempotency_key: string; request_hash: string;
  submission_id: string | null; withdrawal_reason: string | null; created_at: string;
}
export interface Submission {
  protocolVersion: 1; purpose: 'hiboss.interaction-submit'; submissionId: string;
  requestId: string; requestRevision: number; bossId: string; answers: Record<string, JsonValue>;
}
export interface SubmissionRow {
  submission_id: string; request_id: string; revision: number; boss_id: string; payload_hash: string;
  answers_json: string; provenance_json: string; accepted_at: string; acknowledged_at: string | null;
}
