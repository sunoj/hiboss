// D1 proxy that records meta.rows_read for every statement a read path executes.
// Exports meterDatabase and MeterLog; first()/raw() run through all() so their reads are counted.
// Depends only on the D1 binding; groups statements into poll iterations by idle gaps.

export interface Statement { sql: string; binds: unknown[]; rows: number; started: number; ended: number }

/** Statements recorded for one driven path, grouped into iterations by idle gaps. */
export class MeterLog {
  readonly statements: Statement[] = [];

  constructor(private readonly gapMs: number) {}

  /** Iterations: runs of statements separated by at least `gapMs` of idle time. */
  iterations(): Statement[][] {
    const groups: Statement[][] = [];
    let previousEnd = -Infinity;
    for (const statement of [...this.statements].sort((a, b) => a.started - b.started)) {
      if (groups.length === 0 || statement.started - previousEnd >= this.gapMs) groups.push([]);
      groups[groups.length - 1].push(statement);
      previousEnd = Math.max(previousEnd, statement.ended);
    }
    return groups;
  }

  total(): number {
    return this.statements.reduce((sum, statement) => sum + statement.rows, 0);
  }
}

type Stop = () => boolean;
const REAL = new WeakMap<object, D1PreparedStatement>();

/** Wraps `db`; `stop` is checked before each statement and ends a driven loop by throwing. */
export function meterDatabase(db: D1Database, log: MeterLog, stop: Stop = () => false): D1Database {
  const record = (sql: string, binds: unknown[], started: number, meta: D1Meta | undefined) => {
    log.statements.push({ sql, binds, rows: meta?.rows_read ?? 0, started, ended: Date.now() });
  };
  const wrap = (sql: string, real: D1PreparedStatement, binds: unknown[]): D1PreparedStatement => {
    const all = async <T>(): Promise<D1Result<T>> => {
      if (stop()) throw new Error('read budget: driven path stopped');
      const started = Date.now();
      const result = await real.all<T>();
      record(sql, binds, started, result.meta);
      return result;
    };
    const statement = {
      bind: (...values: unknown[]) => wrap(sql, real.bind(...values), values),
      all,
      run: all,
      first: async (column?: string) => {
        const row = ((await all<Record<string, unknown>>()).results ?? [])[0] ?? null;
        return column === undefined ? row : row?.[column] ?? null;
      },
      raw: async (options?: { columnNames?: boolean }) => {
        const rows = (await all<Record<string, unknown>>()).results ?? [];
        const values = rows.map((row) => Object.values(row));
        return options?.columnNames ? [Object.keys(rows[0] ?? {}), ...values] : values;
      },
    } as unknown as D1PreparedStatement;
    REAL.set(statement, real);
    return statement;
  };
  const batch = async <T>(statements: D1PreparedStatement[]): Promise<D1Result<T>[]> => {
    if (stop()) throw new Error('read budget: driven path stopped');
    const started = Date.now();
    const results = await db.batch<T>(statements.map((statement) => REAL.get(statement) ?? statement));
    results.forEach((result, index) => record(`batch[${index}]`, [], started, result.meta));
    return results;
  };
  return {
    prepare: (sql: string) => wrap(sql, db.prepare(sql), []),
    batch,
    exec: (sql: string) => db.exec(sql),
    dump: () => db.dump(),
    withSession: () => meterDatabase(db, log, stop),
  } as unknown as D1Database;
}
