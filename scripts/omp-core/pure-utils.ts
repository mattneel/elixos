// OMP 18.10.1 packages/utils/src/index.ts:46-65; retain its clone semantics.
export { isRecord } from "../../build/upstream/oh-my-pi/packages/utils/src/type-guards.ts";
export { parseJsonWithRepair } from "../../build/upstream/oh-my-pi/packages/utils/src/json-parse.ts";
export * as prompt from "../../build/upstream/oh-my-pi/packages/utils/src/prompt.ts";

// The validator emits one constant schema-support warning, never arguments.
export const logger = {
  warn(message: string) {
    console.warn(message);
  },
};

function isPlainObject(value: object): value is Record<string, unknown> {
  return Object.getPrototypeOf(value) === Object.prototype || Array.isArray(value);
}

export function structuredCloneJSON<T>(value: T): T {
  if (!value || typeof value !== "object") return value;
  if (isPlainObject(value)) {
    try {
      return structuredClone(value);
    } catch {
      // Upstream falls back for an unsupported clone or nested value.
    }
  }
  return JSON.parse(JSON.stringify(value)) as T;
}
