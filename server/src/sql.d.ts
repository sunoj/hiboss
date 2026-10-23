// Types Vite raw SQL and JSON imports used by migration-backed Worker E2E fixtures.
// Exports the source string; depends on Vite's raw asset transform.
declare module '*.sql?raw' { const sql: string; export default sql; }
declare module '*.json?raw' { const json: string; export default json; }
