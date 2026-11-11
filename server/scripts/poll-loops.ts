// Static scan of server sources for repeated-execution sites: timed loops, intervals, DO alarms.
// Exports findRepeatSites and isProductionSource; used by the read-budget completeness check.
// Depends on the TypeScript compiler API (devDependency) only; no type checking is performed.

import ts from 'typescript';

export type RepeatKind = 'loop' | 'interval' | 'alarm' | 'reschedule';
export interface RepeatSite { id: string; kind: RepeatKind; line: number }

// Wait helpers that may be imported from outside the scanned tree, counted even when not defined here.
const CONVENTIONAL_WAITS = ['delay', 'sleep'];
const TEST_SOURCE = /(\.test\.ts|\.d\.ts)$|(^|\/)tests?\/|(^|[/-])test-[\w-]+\.ts$/;

export function isProductionSource(path: string): boolean {
  return path.endsWith('.ts') && !TEST_SOURCE.test(path);
}

/** Every repeat site in `sources` (path relative to src → text), keyed `<path>#<function>`. */
export function findRepeatSites(sources: Map<string, string>): RepeatSite[] {
  const files = [...sources].map(([path, text]) =>
    [path, ts.createSourceFile(path, text, ts.ScriptTarget.Latest, true)] as const);
  const waits = waitFunctions(files.map(([, file]) => file));
  const sites = new Map<string, RepeatSite>();
  for (const [path, file] of files) {
    const visit = (node: ts.Node): void => {
      const kind = siteKind(node, waits);
      if (kind) {
        const id = `${path}#${enclosingName(node)}`;
        const line = file.getLineAndCharacterOfPosition(node.getStart()).line + 1;
        if (!sites.has(`${id}:${kind}`)) sites.set(`${id}:${kind}`, { id, kind, line });
      }
      ts.forEachChild(node, visit);
    };
    visit(file);
  }
  return [...sites.values()].sort((a, b) => a.id.localeCompare(b.id) || a.kind.localeCompare(b.kind));
}

function siteKind(node: ts.Node, waits: Set<string>): RepeatKind | null {
  if (isLoop(node) && contains(loopBody(node), (inner) => isTimerWait(inner, waits))) return 'loop';
  if (!ts.isCallExpression(node)) return null;
  const name = calleeName(node);
  if (name === 'setInterval') return 'interval';
  if (name === 'setAlarm') return 'alarm';
  if (name === 'setTimeout' && reschedulesSelf(node)) return 'reschedule';
  return null;
}

/** Functions whose body waits on a timer without looping: `delay`, `sleep`, wrappers of those. */
function waitFunctions(files: ts.SourceFile[]): Set<string> {
  const waits = new Set<string>(CONVENTIONAL_WAITS);
  for (let grew = true; grew;) {
    grew = false;
    for (const file of files) {
      const visit = (node: ts.Node): void => {
        const named = namedFunction(node);
        if (named && !waits.has(named.name) && !contains(named.body, isLoop)
          && contains(named.body, (inner) => isTimerWait(inner, waits))) {
          waits.add(named.name);
          grew = true;
        }
        ts.forEachChild(node, visit);
      };
      visit(file);
    }
  }
  return waits;
}

function isTimerWait(node: ts.Node, waits: Set<string>): boolean {
  if (!ts.isCallExpression(node)) return false;
  const name = calleeName(node);
  // `await setTimeout(ms)` (timers/promises) or a timer that settles a promise is a sleep.
  if (name === 'setTimeout') return !isFunctionLike(node.arguments[0]) || resolvesPromise(node);
  if (name === 'wait' && ts.isPropertyAccessExpression(node.expression)
    && node.expression.expression.getText() === 'scheduler') return true;
  return name !== null && waits.has(name);
}

/** `new Promise((resolve) => setTimeout(resolve, ms))`: the timer settles the promise (a sleep). */
function resolvesPromise(call: ts.CallExpression): boolean {
  const callback = call.arguments[0];
  for (let current: ts.Node | undefined = call.parent; current; current = current.parent) {
    if (!(ts.isArrowFunction(current) || ts.isFunctionExpression(current))) continue;
    const owner = current.parent;
    if (!ts.isNewExpression(owner) || owner.expression.getText() !== 'Promise') continue;
    const resolve = current.parameters[0]?.name;
    return callback !== undefined && resolve !== undefined && ts.isIdentifier(resolve)
      && contains(callback, (inner) => ts.isIdentifier(inner) && inner.text === resolve.text);
  }
  return false;
}

function reschedulesSelf(call: ts.CallExpression): boolean {
  const self = enclosingName(call);
  const callback = call.arguments[0];
  return callback !== undefined && contains(callback, (inner) =>
    (ts.isIdentifier(inner) && inner.text === self.split('.').pop()));
}

function isFunctionLike(node: ts.Node | undefined): boolean {
  return node !== undefined && (ts.isArrowFunction(node) || ts.isFunctionExpression(node) || ts.isIdentifier(node));
}

function isLoop(node: ts.Node): node is ts.IterationStatement {
  return ts.isWhileStatement(node) || ts.isDoStatement(node) || ts.isForStatement(node)
    || ts.isForOfStatement(node) || ts.isForInStatement(node);
}

function loopBody(loop: ts.IterationStatement): ts.Node[] {
  const parts: (ts.Node | undefined)[] = [loop.statement];
  if (ts.isWhileStatement(loop) || ts.isDoStatement(loop)) parts.push(loop.expression);
  if (ts.isForStatement(loop)) parts.push(loop.condition, loop.incrementor);
  return parts.filter((part): part is ts.Node => part !== undefined);
}

function contains(nodes: ts.Node | ts.Node[], match: (node: ts.Node) => boolean): boolean {
  const search = (node: ts.Node): boolean => match(node) || ts.forEachChild(node, search) === true;
  return (Array.isArray(nodes) ? nodes : [nodes]).some(search);
}

function calleeName(call: ts.CallExpression): string | null {
  const callee = call.expression;
  if (ts.isIdentifier(callee)) return callee.text;
  if (ts.isPropertyAccessExpression(callee)) return callee.name.text;
  return null;
}

function namedFunction(node: ts.Node): { name: string; body: ts.Node } | null {
  if (ts.isFunctionDeclaration(node) && node.name && node.body) return { name: node.name.text, body: node.body };
  if (ts.isMethodDeclaration(node) && node.body) return { name: node.name.getText(), body: node.body };
  if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.initializer
    && (ts.isArrowFunction(node.initializer) || ts.isFunctionExpression(node.initializer))) {
    return { name: node.name.text, body: node.initializer.body };
  }
  return null;
}

/** Name of the nearest named function; an anonymous route handler is named by its route call. */
function enclosingName(node: ts.Node): string {
  const names: string[] = [];
  for (let current = node.parent; current; current = current.parent) {
    if (ts.isClassDeclaration(current) && current.name) names.unshift(current.name.text);
    if (names.length > 0) continue;
    const named = namedFunction(current);
    if (named) { names.unshift(named.name); continue; }
    if ((ts.isArrowFunction(current) || ts.isFunctionExpression(current)) && ts.isCallExpression(current.parent)) {
      const path = current.parent.arguments[0];
      if (ts.isStringLiteral(path)) names.unshift(`${current.parent.expression.getText()}(${path.text})`);
    }
  }
  return names.join('.') || '<module>';
}
