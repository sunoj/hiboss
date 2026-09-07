# Phase 0 JSON Render Investigation

## 1. Versions, Repository, and Dependencies
- **Resolved Versions:** `@json-render/core@0.20.0` and `@json-render/react@0.20.0`
- **Source Repository:** `https://github.com/vercel-labs/json-render`
- **Commit:** The `v0.20.0` release maps to commit `ea4b361b9ff23bcab20286c4f559a5316f0e892b`.
- **Transitive Dependencies:** Both packages have exactly one external transitive dependency: `zod@^4.3.6`.
- **Licences:** Both `@json-render/core` and `@json-render/react` are `Apache-2.0`. `zod` is `MIT`.

## 2. Expressions and Visibility
Every requested symbol exists exactly under its proposed name in `0.20.0`. They are exported from `@json-render/core` under the `PropExpression<T>` type:
```typescript
export type PropExpression<T = unknown> = T | {
    $state: string;
} | {
    $item: string;
} | {
    $index: true;
} | {
    $bindState: string;
} | {
    $bindItem: string;
} | {
    $cond: VisibilityCondition;
    $then: PropExpression<T>;
    $else: PropExpression<T>;
};
```
Visibility conditions are provided by `VisibilityCondition`:
```typescript
export type VisibilityCondition =
  | boolean
  | SingleCondition
  | SingleCondition[]
  | AndCondition
  | OrCondition;
```
A helper object `visibility` (e.g. `visibility.eq(path, val)`) is exported to create these conditions programmatically.

Since 0.20.0 is pre-1.0, the `$cond` shape inside `PropExpression` (which embeds `VisibilityCondition`) appears somewhat conflated with generic conditional rendering and might change as it forces all conditional logic through visibility-like comparisons.

## 3. Spec Validation
**Upstream provides:**
The exported `validateSpec(spec: Spec, options?: ValidateSpecOptions): SpecValidationIssues` function checks:
- The `root` exists and resolves in the `elements` map.
- Child element IDs resolve in `children` or `slots` (no dangling refs).
- `visible`, `on`, `repeat`, and `watch` are correctly placed at the top level of an element (not inside `props`).
- `repeat` blocks contain children.
- Relative `repeat.statePath` expressions do not escape their enclosing repeat scope, and the resolved path points to an array.
- Visibility conditions strictly conform to `VisibilityConditionStrictSchema`.

**HiBoss must implement:**
- **Cycles:** Upstream `validateSpec` tracks ancestors to prevent infinite loops but silently stops traversing rather than returning a cycle issue.
- **Duplicate JSON keys:** Must be caught by HiBoss at the JSON parsing layer.
- **Unknown component, prop, or action:** `validateSpec` does not check against the catalog. Zod validation via `catalog.validate(spec)` can reject unknown values, provided the Zod schemas are strict.
- **Depth and node bounds:** Upstream does not limit spec depth or node count.
- **Dangerous paths:** Upstream's internal `setByPath(obj: Record<string, unknown>, path: string, value: unknown)` does not check for `__proto__`, `prototype`, or `constructor` after decoding JSON pointers.

## 4. Catalog and Registry API
**Catalog Definition:**
An application registers its components and actions by calling `defineCatalog` from `@json-render/core`:
```typescript
declare function defineCatalog<
  TDef extends SchemaDefinition,
  TCatalog extends {
    components: Record<string, { props: unknown; description?: string }>;
    actions?: Record<string, { params: unknown; description?: string }>;
  }
>(schemaDef: TDef, catalogDef: TCatalog): Catalog<TDef, TCatalog>;
```

**React Registry and Renderer Mount:**
The React integration binds implementation logic via `defineRegistry` from `@json-render/react`:
```typescript
declare function defineRegistry<C extends Catalog>(
  catalog: C, 
  options: DefineRegistryOptions<C>
): DefineRegistryResult;
```
`defineRegistry` requires implementations for all components (and actions, if defined). Component props include `emit` and `on`:
```typescript
interface ComponentRenderProps<P = Record<string, unknown>> {
    element: UIElement<string, P>;
    children?: ReactNode;
    slots?: Record<string, ReactNode>;
    emit: (event: string) => void;
    on: (event: string) => EventHandle;
    bindings?: Record<string, string>;
}
```
An action is dispatched when the user triggers the event and the component calls `emit("press")`.

To mount the React renderer, pass the registry to `<Renderer>`:
```tsx
<Renderer spec={spec} registry={registry} />
```

## 5. Protocol Expressiveness and Forking
**Protocol Section 2 (Catalog & Capabilities):**
- **Catalog Metadata:** Upstream catalog allows a basic `description` string but has no structured `version`, units, or metadata fields. **HiBoss can add it outside the spec** by mapping metadata into custom UI element props or external structures.
- **Expression Restrictions:** Upstream natively supports `$computed` and `watch`. HiBoss can disable them by failing validation if these keys appear in the parsed spec. **(Add outside spec)**

**Protocol Section 4 (State & Schema):**
- **JSON Schema Validation:** Upstream uses Zod schemas for components, but not strict JSON Schema 2020-12 (with `allOf`/`if`/`then`) for the task state itself. **HiBoss must implement JSON Schema validation independently.** (Add outside spec)
- **Namespace Write Protections:** Upstream `setByPath` and actions do not isolate `/task`, `/form`, etc. **HiBoss can add it outside the spec** by implementing a custom `StateStore` adapter (`createStoreAdapter`) to intercept state updates and enforce ACL rules, avoiding a fork.
- **Path Vulnerabilities:** Upstream's `setByPath` is vulnerable to prototype pollution. If HiBoss processes `state.patch` commands natively, it **must fork/override** patch application logic or strictly sanitize pointer paths prior to applying them.
- **Conditional Activation:** Upstream visibility conditions do not inherently derive from form schema declarative rules. **HiBoss can add it outside the spec** by either compiling JSON Schema conditions into `visible` rules before publication or ignoring `visible` entirely for backend validation.
