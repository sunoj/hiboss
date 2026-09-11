// Types Vite raw SQL imports used by migration-backed Worker E2E fixtures.
// Exports the SQL source string; depends on Vite's raw asset transform.
declare module '*.sql?raw' { const sql: string; export default sql; }
