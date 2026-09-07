// Validates the bounded answer-schema subset and submitted answer objects.
// Exports AnswerSchema, validateAnswerSchema, and validateAnswers.
// Dependencies: shared validation errors.

import { failure, type ValidationResult } from './errors.js';

export type SchemaType = 'string' | 'number' | 'integer' | 'boolean' | 'null' | 'object' | 'array';
type SchemaTypeValue = SchemaType | readonly SchemaType[];
export type AnswerSchema = Readonly<Record<string, unknown>>;

const SUPPORTED_KEYWORDS = new Set([
  '$defs', '$ref', 'type', 'properties', 'required', 'additionalProperties', 'items',
  'minItems', 'maxItems', 'uniqueItems', 'enum', 'minimum', 'maximum',
  'exclusiveMinimum', 'exclusiveMaximum', 'minLength', 'maxLength', 'if', 'then', 'else', 'allOf',
]);
const SCHEMA_TYPES = new Set<SchemaType>(['string', 'number', 'integer', 'boolean', 'null', 'object', 'array']);
const MAX_ALLOF = 8;

interface SchemaRecord {
  readonly [key: string]: unknown;
}

interface ValidationContext {
  readonly root: SchemaRecord;
  readonly refs: ReadonlySet<string>;
}

function isRecord(value: unknown): value is SchemaRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function pathKey(path: string, key: string): string {
  return `${path}/${key.replaceAll('~', '~0').replaceAll('/', '~1')}`;
}

function jsonValue(value: unknown): boolean {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return true;
  if (typeof value === 'number') return Number.isFinite(value);
  if (Array.isArray(value)) return value.every(jsonValue);
  return isRecord(value) && Object.values(value).every(jsonValue);
}

function schemaError(path: string, message: string, keyword?: string): ValidationResult<never> {
  return failure('invalid_answers', path, message, keyword);
}

function schemaTypeValue(value: unknown): SchemaTypeValue | undefined {
  if (typeof value === 'string' && SCHEMA_TYPES.has(value as SchemaType)) return value as SchemaType;
  if (Array.isArray(value) && value.length > 0 && value.every((item) => typeof item === 'string' && SCHEMA_TYPES.has(item as SchemaType))) return value as SchemaType[];
  return undefined;
}

function validateSchemaNode(value: unknown, path: string): ValidationResult<SchemaRecord> {
  if (!isRecord(value)) return schemaError(path, 'Schema must be an object');
  const unsupported = Object.keys(value).find((key) => !SUPPORTED_KEYWORDS.has(key));
  if (unsupported !== undefined) return schemaError(pathKey(path, unsupported), `Unsupported answer-schema keyword "${unsupported}"`, unsupported);
  if (value.type !== undefined && schemaTypeValue(value.type) === undefined) return schemaError(pathKey(path, 'type'), 'Schema type is outside the supported subset', 'type');
  if (value.$ref !== undefined && (typeof value.$ref !== 'string' || !/^#\/\$defs\/[^/]+$/.test(value.$ref))) return schemaError(pathKey(path, '$ref'), 'Only local #/$defs references are supported', '$ref');
  if (value.properties !== undefined) {
    if (!isRecord(value.properties)) return schemaError(pathKey(path, 'properties'), 'properties must be an object', 'properties');
    for (const [key, child] of Object.entries(value.properties)) {
      const result = validateSchemaNode(child, pathKey(pathKey(path, 'properties'), key));
      if (!result.ok) return result;
    }
  }
  if (value.$defs !== undefined) {
    if (!isRecord(value.$defs)) return schemaError(pathKey(path, '$defs'), '$defs must be an object', '$defs');
    for (const [key, child] of Object.entries(value.$defs)) {
      const result = validateSchemaNode(child, pathKey(pathKey(path, '$defs'), key));
      if (!result.ok) return result;
    }
  }
  if (value.required !== undefined && (!Array.isArray(value.required) || value.required.some((item) => typeof item !== 'string') || new Set(value.required).size !== value.required.length)) return schemaError(pathKey(path, 'required'), 'required must be a unique string array', 'required');
  if (value.additionalProperties !== undefined && typeof value.additionalProperties !== 'boolean') return schemaError(pathKey(path, 'additionalProperties'), 'additionalProperties must be boolean', 'additionalProperties');
  if (value.items !== undefined) {
    const result = validateSchemaNode(value.items, pathKey(path, 'items'));
    if (!result.ok) return result;
  }
  if (value.allOf !== undefined) {
    if (!Array.isArray(value.allOf) || value.allOf.length > MAX_ALLOF) return schemaError(pathKey(path, 'allOf'), `allOf must contain at most ${MAX_ALLOF} schemas`, 'allOf');
    for (let index = 0; index < value.allOf.length; index += 1) {
      const result = validateSchemaNode(value.allOf[index], `${pathKey(path, 'allOf')}/${index}`);
      if (!result.ok) return result;
    }
  }
  for (const keyword of ['if', 'then', 'else'] as const) {
    if (value[keyword] !== undefined) {
      const result = validateSchemaNode(value[keyword], pathKey(path, keyword));
      if (!result.ok) return result;
    }
  }
  for (const keyword of ['minItems', 'maxItems', 'minLength', 'maxLength'] as const) {
    if (value[keyword] !== undefined && (typeof value[keyword] !== 'number' || !Number.isInteger(value[keyword]) || value[keyword] < 0)) return schemaError(pathKey(path, keyword), `${keyword} must be a non-negative integer`, keyword);
  }
  for (const keyword of ['minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum'] as const) {
    if (value[keyword] !== undefined && (typeof value[keyword] !== 'number' || !Number.isFinite(value[keyword]))) return schemaError(pathKey(path, keyword), `${keyword} must be a finite number`, keyword);
  }
  if (value.enum !== undefined && (!Array.isArray(value.enum) || !value.enum.every(jsonValue))) return schemaError(pathKey(path, 'enum'), 'enum must contain JSON values', 'enum');
  if (value.uniqueItems !== undefined && typeof value.uniqueItems !== 'boolean') return schemaError(pathKey(path, 'uniqueItems'), 'uniqueItems must be boolean', 'uniqueItems');
  return { ok: true, value };
}

function refName(value: SchemaRecord): string | undefined {
  return typeof value.$ref === 'string' && /^#\/\$defs\/[^/]+$/.test(value.$ref) ? value.$ref.slice('#/$defs/'.length) : undefined;
}

function checkReferences(value: SchemaRecord, root: SchemaRecord, path: string, stack: ReadonlySet<string>): ValidationResult<true> {
  const reference = refName(value);
  if (reference !== undefined) {
    const defs = root.$defs;
    if (!isRecord(defs) || !isRecord(defs[reference])) return schemaError(pathKey(path, '$ref'), `Unknown local definition "${reference}"`, '$ref');
    if (stack.has(reference)) return schemaError(pathKey(path, '$ref'), 'Recursive $ref is not supported', '$ref');
    const next = new Set(stack);
    next.add(reference);
    const result = checkReferences(defs[reference], root, `/$defs/${reference}`, next);
    if (!result.ok) return result;
  }
  for (const [key, child] of Object.entries(value)) {
    if (key === '$defs' || key === '$ref') continue;
    if (key === 'properties' && isRecord(child)) {
      for (const [name, property] of Object.entries(child)) {
        if (isRecord(property)) { const result = checkReferences(property, root, pathKey(pathKey(path, 'properties'), name), stack); if (!result.ok) return result; }
      }
    } else if (['items', 'if', 'then', 'else'].includes(key) && isRecord(child)) {
      const result = checkReferences(child, root, pathKey(path, key), stack); if (!result.ok) return result;
    } else if (key === 'allOf' && Array.isArray(child)) {
      for (let index = 0; index < child.length; index += 1) { const item = child[index]; if (isRecord(item)) { const result = checkReferences(item, root, `${path}/allOf/${index}`, stack); if (!result.ok) return result; } }
    }
  }
  if (isRecord(value.$defs)) for (const [name, child] of Object.entries(value.$defs)) if (isRecord(child)) { const result = checkReferences(child, root, `/$defs/${name}`, stack); if (!result.ok) return result; }
  return { ok: true, value: true };
}

export function validateAnswerSchema(value: unknown): ValidationResult<AnswerSchema> {
  const result = validateSchemaNode(value, '');
  if (!result.ok) return result;
  if (result.value.type !== 'object' && refName(result.value) === undefined) return schemaError('/type', 'Answer schema root must have type object', 'type');
  const references = checkReferences(result.value, result.value, '', new Set());
  return references.ok ? { ok: true, value: result.value } : references;
}

function sameJson(left: unknown, right: unknown): boolean {
  if (Object.is(left, right)) return true;
  if (Array.isArray(left) && Array.isArray(right)) return left.length === right.length && left.every((item, index) => sameJson(item, right[index]));
  if (isRecord(left) && isRecord(right)) return Object.keys(left).length === Object.keys(right).length && Object.entries(left).every(([key, item]) => key in right && sameJson(item, right[key]));
  return false;
}

function typeMatches(type: SchemaTypeValue, value: unknown): boolean {
  if (Array.isArray(type)) return type.some((item) => typeMatches(item, value));
  if (type === 'null') return value === null;
  if (type === 'array') return Array.isArray(value);
  if (type === 'object') return isRecord(value);
  if (type === 'integer') return typeof value === 'number' && Number.isInteger(value) && Number.isFinite(value);
  return typeof value === type && (type !== 'number' || Number.isFinite(value));
}

function resolveSchema(schema: SchemaRecord, context: ValidationContext): SchemaRecord | ValidationResult<never> {
  const name = refName(schema);
  if (name === undefined) return schema;
  const defs = context.root.$defs;
  const target = isRecord(defs) ? defs[name] : undefined;
  return isRecord(target) ? target : schemaError('/$ref', `Unknown local definition "${name}"`, '$ref');
}

function isSchemaFailure(value: SchemaRecord | ValidationResult<never>): value is ValidationResult<never> {
  return 'error' in value && 'ok' in value;
}

function conditionMatches(schema: SchemaRecord, value: unknown, context: ValidationContext): boolean {
  return validateNode(schema, value, '', context).ok;
}

function conditionalProperties(schema: SchemaRecord, value: unknown, context: ValidationContext): Set<string> {
  const names = new Set<string>();
  const collect = (branch: unknown): void => { if (isRecord(branch) && isRecord(branch.properties)) Object.keys(branch.properties).forEach((name) => names.add(name)); };
  if (Array.isArray(schema.allOf)) for (const item of schema.allOf) if (isRecord(item) && isRecord(item.if)) collect(conditionMatches(item.if, value, context) ? item.then : item.else);
  if (isRecord(schema.if)) collect(conditionMatches(schema.if, value, context) ? schema.then : schema.else);
  return names;
}

function validateObject(schema: SchemaRecord, value: SchemaRecord, path: string, context: ValidationContext): ValidationResult<true> {
  const active = conditionalProperties(schema, value, context);
  const properties = isRecord(schema.properties) ? schema.properties : {};
  for (const name of Object.keys(properties)) active.add(name);
  const conditionalNames = new Set<string>();
  const collectAllBranches = (branch: unknown): void => { if (isRecord(branch) && isRecord(branch.properties)) Object.keys(branch.properties).forEach((name) => conditionalNames.add(name)); };
  if (Array.isArray(schema.allOf)) for (const item of schema.allOf) if (isRecord(item) && isRecord(item.if)) { collectAllBranches(item.then); collectAllBranches(item.else); }
  if (isRecord(schema.if)) { collectAllBranches(schema.then); collectAllBranches(schema.else); }
  for (const key of Object.keys(value)) {
    if (conditionalNames.has(key) && !active.has(key)) return failure('invalid_answers', pathKey(path, key), 'Inactive answer path must be omitted');
    if (schema.additionalProperties === false && !active.has(key)) return failure('invalid_answers', pathKey(path, key), 'Unexpected answer path');
  }
  const required = new Set(typeof schema.required === 'object' && Array.isArray(schema.required) ? schema.required.filter((item): item is string => typeof item === 'string') : []);
  const addBranchRequired = (branch: unknown): void => {
    const branchRequired = isRecord(branch) ? branch.required : undefined;
    if (Array.isArray(branchRequired)) branchRequired.filter((name): name is string => typeof name === 'string').forEach((name) => required.add(name));
  };
  if (Array.isArray(schema.allOf)) for (const branch of schema.allOf) if (isRecord(branch) && isRecord(branch.if)) addBranchRequired(conditionMatches(branch.if, value, context) ? branch.then : branch.else);
  if (isRecord(schema.if)) addBranchRequired(conditionMatches(schema.if, value, context) ? schema.then : schema.else);
  for (const name of required) if (!(name in value)) return failure('invalid_answers', pathKey(path, name), 'Required answer is missing');
  for (const [name, child] of Object.entries(properties)) if (name in value) { const result = validateNode(child, value[name], pathKey(path, name), context); if (!result.ok) return result; }
  return { ok: true, value: true };
}

function validateNode(rawSchema: unknown, value: unknown, path: string, context: ValidationContext): ValidationResult<true> {
  if (!isRecord(rawSchema)) return failure('invalid_answers', path, 'Invalid schema node');
  const resolved = resolveSchema(rawSchema, context);
  if (isSchemaFailure(resolved)) return resolved;
  const schema = resolved;
  if (Array.isArray(schema.enum) && !schema.enum.some((item) => sameJson(item, value))) return failure('invalid_answers', path, 'Value is not one of the allowed enum values');
  const schemaType = schemaTypeValue(schema.type);
  if (schemaType !== undefined && !typeMatches(schemaType, value)) return failure('invalid_answers', path, `Expected ${String(schema.type)}`);
  if (typeof value === 'number') {
    for (const [key, pass] of [['minimum', value >= Number(schema.minimum)], ['maximum', value <= Number(schema.maximum)], ['exclusiveMinimum', value > Number(schema.exclusiveMinimum)], ['exclusiveMaximum', value < Number(schema.exclusiveMaximum)] ] as const) if (schema[key] !== undefined && !pass) return failure('invalid_answers', path, `Value violates ${key}`);
  }
  if (typeof value === 'string') {
    if (schema.minLength !== undefined && value.length < Number(schema.minLength)) return failure('invalid_answers', path, 'String is shorter than minLength');
    if (schema.maxLength !== undefined && value.length > Number(schema.maxLength)) return failure('invalid_answers', path, 'String is longer than maxLength');
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < Number(schema.minItems)) return failure('invalid_answers', path, 'Array is shorter than minItems');
    if (schema.maxItems !== undefined && value.length > Number(schema.maxItems)) return failure('invalid_answers', path, 'Array is longer than maxItems');
    if (schema.uniqueItems === true && value.some((item, index) => value.slice(0, index).some((previous) => sameJson(previous, item)))) return failure('invalid_answers', path, 'Array items must be unique');
    if (schema.items !== undefined) for (let index = 0; index < value.length; index += 1) { const result = validateNode(schema.items, value[index], `${path}/${index}`, context); if (!result.ok) return result; }
  }
  if (isRecord(value) && (schemaType !== undefined && typeMatches(schemaType, value) && isRecord(value) || schema.properties !== undefined || schema.additionalProperties !== undefined)) { const result = validateObject(schema, value, path, context); if (!result.ok) return result; }
  if (Array.isArray(schema.allOf)) for (const item of schema.allOf) { if (isRecord(item) && isRecord(item.if)) { const branch = conditionMatches(item.if, value, context) ? item.then : item.else; if (branch !== undefined) { const result = validateNode(branch, value, path, context); if (!result.ok) return result; } } else { const result = validateNode(item, value, path, context); if (!result.ok) return result; } }
  if (isRecord(schema.if)) { const branch = conditionMatches(schema.if, value, context) ? schema.then : schema.else; if (branch !== undefined) { const result = validateNode(branch, value, path, context); if (!result.ok) return result; } }
  return { ok: true, value: true };
}

export function validateAnswers(schema: AnswerSchema, answers: unknown): ValidationResult<Readonly<Record<string, unknown>>> {
  const schemaResult = validateAnswerSchema(schema);
  if (!schemaResult.ok) return schemaResult;
  if (!isRecord(answers)) return failure('invalid_answers', '', 'Answers must be an object');
  const context: ValidationContext = { root: schemaResult.value, refs: new Set() };
  const result = validateNode(schemaResult.value, answers, '', context);
  return result.ok ? { ok: true, value: answers } : result;
}
