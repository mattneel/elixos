#!/usr/bin/env bun
/**
 * M21 descriptor-catalog builder (ADR-047, ADR-071).
 *
 * Constructs every tool of the pinned Oh-My-Pi 18.10.1 tool inventory through
 * its *real* upstream factory or class — `BUILTIN_TOOLS`/`HIDDEN_TOOLS`, the
 * settings-gated image/speech definitions, the autoresearch/vibe/advisor/
 * commit/compression/security publication factories — then reads
 * `toolWireSchema(tool)` (the same reader the provider wire uses) plus the
 * tool's live description, `strict` flag, presentation fields and hooks.
 *
 * Nothing here is hand-written schema text: a value only enters the catalog
 * when an upstream object produced it in this run. Each variant records the
 * exact settings/session inputs that selected it, and the builder verifies
 * every recorded inventory variant (docs/omp-inventory.json) is covered by a
 * captured schema before it writes.
 *
 * Output: os/priv/toolset/catalog.json (compiled into
 * `Elixos.Toolset.Catalog` as a BEAM literal by the Elixir side).
 *
 * The pinned checkout and its node_modules are read-only inputs. Scratch state
 * (the catalog workspace and the IDA gate-probe directory) lives under
 * build/omp-catalog-scratch, which is gitignored.
 *
 * Run from the repository root:
 *
 *   bun scripts/build-omp-catalog.ts
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

import { toolWireSchema } from "../build/upstream/oh-my-pi/packages/ai/src/utils/schema/wire";
import { AdviseTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/advisor/advise-tool";
import { createInitExperimentTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/autoresearch/tools/init-experiment";
import { createLogExperimentTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/autoresearch/tools/log-experiment";
import { createRunExperimentTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/autoresearch/tools/run-experiment";
import { createUpdateNotesTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/autoresearch/tools/update-notes";
import type { AutoresearchToolFactoryOptions } from "../build/upstream/oh-my-pi/packages/coding-agent/src/autoresearch/types";
import { createCommitTools } from "../build/upstream/oh-my-pi/packages/coding-agent/src/commit/agentic/tools/index";
import type { CommitToolOptions } from "../build/upstream/oh-my-pi/packages/coding-agent/src/commit/agentic/tools/index";
import { CompressProtocol } from "../build/upstream/oh-my-pi/packages/coding-agent/src/compress/protocol";
import { Settings } from "../build/upstream/oh-my-pi/packages/coding-agent/src/config/settings";
import { createSecurityPublicationTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/security/publication";
import {
	BUILTIN_TOOL_NAMES,
	HIDDEN_TOOL_NAMES,
	normalizeToolName,
} from "../build/upstream/oh-my-pi/packages/coding-agent/src/tools/builtin-names";
import { imageGenTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/tools/image-gen";
import { BUILTIN_TOOLS, HIDDEN_TOOLS } from "../build/upstream/oh-my-pi/packages/coding-agent/src/tools/index";
import type { Tool, ToolFactory, ToolSession } from "../build/upstream/oh-my-pi/packages/coding-agent/src/tools/index";
import { ttsTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/tools/tts";
import { createVibeTools } from "../build/upstream/oh-my-pi/packages/coding-agent/src/tools/vibe";
import type { WorkPoolYieldItem } from "../build/upstream/oh-my-pi/packages/coding-agent/src/task/workpool-yield";
import { isRecord } from "../build/upstream/oh-my-pi/packages/utils/src/type-guards";

const REPO_ROOT = path.resolve(import.meta.dir, "..");
const UPSTREAM = path.join(REPO_ROOT, "build", "upstream", "oh-my-pi");
const CODING_AGENT_PACKAGE_JSON = path.join(UPSTREAM, "packages", "coding-agent", "package.json");
const INVENTORY_JSON = path.join(REPO_ROOT, "docs", "omp-inventory.json");
const DESTINATION = path.join(REPO_ROOT, "os", "priv", "toolset", "catalog.json");

const REFERENCE = {
	repository: "https://github.com/can1357/oh-my-pi.git",
	version: "18.10.1",
	license: "MIT",
} as const;
const EXPECTED_COMMIT = "90701813e5fba6919067848989378b4ee6239c13";

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };

const SCRATCH = path.join(REPO_ROOT, "build", "omp-catalog-scratch");
const WORKSPACE = path.join(SCRATCH, "ws");
const IDA_STUB = path.join(SCRATCH, "ida-install");
const CATALOG_SESSION_ID = "elixos-catalog-session";

// ─────────────────────────────────────────────────────────────────────────────
// Pinned-source preflight

function assertPinnedSource(): void {
	const commit = spawnSync("git", ["-C", UPSTREAM, "rev-parse", "HEAD"], { encoding: "utf8" });
	if (commit.status !== 0 || commit.stdout.trim() !== EXPECTED_COMMIT) {
		throw new Error(`catalog requires the pinned checkout ${EXPECTED_COMMIT}`);
	}
	const packageJson: unknown = JSON.parse(fs.readFileSync(CODING_AGENT_PACKAGE_JSON, "utf8"));
	const version = isRecord(packageJson) ? packageJson.version : undefined;
	if (version !== REFERENCE.version) throw new Error("checkout package version differs from the recorded pin");
}

function prepareScratch(): void {
	fs.mkdirSync(WORKSPACE, { recursive: true });
	// `git_overview`/`git_hunk`/`git_file_diff` call `vcs.requireGit(cwd)` while
	// constructing, so the catalog workspace is a real git repository.
	if (!fs.existsSync(path.join(WORKSPACE, ".git"))) {
		spawnSync("git", ["init", "--quiet", WORKSPACE], { encoding: "utf8" });
	}
	// The `ida` factory gate is `exists(<install>/libidalib.so)`; the descriptor
	// is class-static and no IDA process runs. The probe records this note.
	fs.mkdirSync(IDA_STUB, { recursive: true });
	const idalib = path.join(IDA_STUB, process.platform === "win32" ? "idalib.dll" : "libidalib.so");
	if (!fs.existsSync(idalib)) fs.writeFileSync(idalib, "");
}

// ─────────────────────────────────────────────────────────────────────────────
// Sessions

interface SessionInputs {
	settings?: Record<string, unknown>;
	facts: string[];
	extra?: Partial<ToolSession>;
}

function buildSession(inputs: SessionInputs): ToolSession {
	return {
		cwd: WORKSPACE,
		hasUI: false,
		getSessionFile: () => null,
		getSessionSpawns: () => "*",
		settings: Settings.isolated(inputs.settings ?? {}),
		...(inputs.extra ?? {}),
	};
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool field extraction

/**
 * Heterogeneous upstream tool objects (classes, `ToolDefinition`s and
 * `CustomTool`s) share no index signature TypeScript can unify, so fields are
 * read reflectively here. Callers narrow every value they consume.
 */
function fieldsOf(tool: unknown): Record<string, unknown> | null {
	if (tool === null || typeof tool !== "object") return null;
	return tool as unknown as Record<string, unknown>;
}

function dataValue(value: unknown): Json | null {
	if (value === null || value === undefined) return null;
	if (typeof value === "string" || typeof value === "boolean") return value;
	if (typeof value === "number") return Number.isFinite(value) ? value : null;
	if (Array.isArray(value)) return value.map(item => dataValue(item));
	if (isRecord(value)) {
		// Undefined members are dropped exactly as JSON.stringify drops them;
		// nothing is invented for a field the tool did not define.
		const record: { [key: string]: Json } = {};
		for (const [key, item] of Object.entries(value)) {
			if (item === undefined) continue;
			record[key] = dataValue(item);
		}
		return record;
	}
	return null;
}

/** Fields whose value is a function or a dynamic resolver in some tools. */
const HOOK_FIELDS = [
	"docTopics",
	"openArgStream",
	"speculation",
	"interruptible",
	"matcherDigest",
	"matcherPaths",
	"matcherEntries",
	"formatApprovalDetails",
	"renderCall",
	"renderResult",
] as const;
const DYNAMIC_FIELDS = ["approval", "concurrency", "intent"] as const;

interface ToolFields {
	name: string;
	label: Json;
	description: string;
	description_sha256: string;
	strict: boolean | null;
	loadMode: Json;
	summary: Json;
	deferrable: Json;
	hidden: Json;
	readsSkillUris: Json;
	lenientArgValidation: Json;
	customWireName: Json;
	customFormat: Json;
	examples_count: number;
	intent: Json;
	concurrency: Json;
	approval: Json;
	hooks: string[];
}

function readFields(tool: unknown): ToolFields {
	const fields = fieldsOf(tool);
	if (fields === null) throw new Error("tool is not an object");
	const name = fields.name;
	const description = fields.description;
	if (typeof name !== "string" || typeof description !== "string") {
		throw new Error("tool has no string name/description");
	}
	const dynamic = (key: string): Json => {
		const value = fields[key];
		if (value === undefined) return null;
		const data = dataValue(value);
		return data === null ? "dynamic" : data;
	};
	const examples = fields.examples;
	return {
		name,
		label: dataValue(fields.label),
		description,
		description_sha256: digest(description),
		strict: typeof fields.strict === "boolean" ? fields.strict : null,
		loadMode: dataValue(fields.loadMode),
		summary: dataValue(fields.summary),
		deferrable: dataValue(fields.deferrable),
		hidden: dataValue(fields.hidden),
		readsSkillUris: dataValue(fields.readsSkillUris),
		lenientArgValidation: dataValue(fields.lenientArgValidation),
		customWireName: dataValue(fields.customWireName),
		customFormat: dataValue(fields.customFormat),
		examples_count: Array.isArray(examples) ? examples.length : 0,
		intent: dynamic(DYNAMIC_FIELDS[2]),
		concurrency: dynamic(DYNAMIC_FIELDS[1]),
		approval: dynamic(DYNAMIC_FIELDS[0]),
		hooks: HOOK_FIELDS.filter(hook => fields[hook] !== undefined),
	};
}

function wireSchemaOf(tool: unknown): Record<string, unknown> {
	const fields = fieldsOf(tool);
	if (fields === null || !("parameters" in fields)) throw new Error("tool has no parameters");
	// `toolWireSchema` reads only `parameters`; the cast carries the real schema.
	return toolWireSchema({ name: "catalog", description: "", parameters: fields.parameters } as unknown as Tool);
}

function schemaProperties(schema: Record<string, unknown>): string[] {
	const properties = schema.properties;
	if (!isRecord(properties)) return [];
	return Object.keys(properties).sort();
}

function schemaRequired(schema: Record<string, unknown>): string[] {
	const required = schema.required;
	if (!Array.isArray(required)) return [];
	return required.filter((item): item is string => typeof item === "string").sort();
}

// ─────────────────────────────────────────────────────────────────────────────
// Hashing

function digest(value: string): string {
	return new Bun.CryptoHasher("sha256").update(value).digest("hex");
}

function stable(value: Json): string {
	if (value === null || typeof value !== "object") return JSON.stringify(value);
	if (Array.isArray(value)) return `[${value.map(item => stable(item)).join(",")}]`;
	const keys = Object.keys(value).sort();
	return `{${keys.map(key => `${JSON.stringify(key)}:${stable(value[key])}`).join(",")}}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// Variant captures

interface VariantSpec {
	/** Stable id inside its tool. */
	id: string;
	/** Tool instance this variant constructs; defaults to the group's name. */
	tool?: string;
	/**
	 * Gate description. Omitted only for a tool with exactly one variant and
	 * exactly one recorded inventory row: that row's `when` is used instead.
	 */
	when?: string;
	/**
	 * Recorded inventory rows this variant satisfies, when the row cannot be
	 * identified structurally (identical property sets across variants). Each
	 * claim is verified against the captured schema before it is accepted.
	 */
	inventory_rows?: number[];
	/** Expected top-level property names; asserted after construction. */
	properties?: string[];
	inputs: SessionInputs;
	/** Recorded caveats, e.g. a provisioned gate probe. */
	notes?: string[];
	build?: (session: ToolSession) => unknown;
}

interface CapturedVariant {
	id: string;
	/** Authored gate text; resolved against the inventory when absent. */
	spec_when: string | null;
	/** Authored inventory-row claims; validated in phase 2. */
	spec_rows: number[];
	construction: string;
	settings: Record<string, unknown>;
	session: string[];
	notes: string[];
	fields: ToolFields;
	parameters: Record<string, unknown>;
	properties: string[];
	required: string[];
	schema_sha256: string;
}

/** Workpool items the `yield` variant reads; the schema uses their indices. */
const YIELD_WORKPOOL_ITEMS: WorkPoolYieldItem[] = [
	{ index: 1, id: "catalog-item-1" } as unknown as WorkPoolYieldItem,
	{ index: 2, id: "catalog-item-2" } as unknown as WorkPoolYieldItem,
];

/** Every built-in and hidden factory, keyed by its recorded tool name. */
const TOOL_FACTORIES: Record<string, ToolFactory | undefined> = { ...BUILTIN_TOOLS, ...HIDDEN_TOOLS };

/** One captured variant per spec; the constructed tool name is asserted. */
async function capture(group: string, spec: VariantSpec): Promise<CapturedVariant> {
	const name = spec.tool ?? group;
	const build = spec.build ?? ((session: ToolSession) => TOOL_FACTORIES[name]?.(session) ?? null);
	const tool = await build(buildSession(spec.inputs));
	if (tool === null || tool === undefined) throw new Error(`${name}/${spec.id}: factory returned null`);
	const fields = readFields(tool);
	if (fields.name !== name) throw new Error(`${name}/${spec.id}: constructed ${fields.name}`);
	const parameters = wireSchemaOf(tool);
	const properties = schemaProperties(parameters);
	if (spec.properties !== undefined && properties.join(",") !== [...spec.properties].sort().join(",")) {
		throw new Error(`${name}/${spec.id}: properties ${properties.join(",")} != ${spec.properties.join(",")}`);
	}
	return {
		id: spec.id,
		spec_when: spec.when ?? null,
		spec_rows: spec.inventory_rows ?? [],
		construction: `factory(${name})`,
		settings: spec.inputs.settings ?? {},
		session: spec.inputs.facts,
		notes: spec.notes ?? [],
		fields,
		parameters,
		properties,
		required: schemaRequired(parameters),
		schema_sha256: digest(stable(dataValue(parameters) ?? null)),
	};
}

// ─────────────────────────────────────────────────────────────────────────────
// The inventory's variant dimensions, in recorded order

const BASH_VARIANTS: VariantSpec[] = [
	{ id: "async_off_launch_off", when: "async disabled; service launch unavailable", inventory_rows: [0], properties: ["command", "cwd", "pty", "timeout"], inputs: { settings: { "async.enabled": false, "launch.enabled": false }, facts: [] } },
	{ id: "async_on_launch_off", when: "async enabled; service launch unavailable", inventory_rows: [1], properties: ["async", "command", "cwd", "pty", "timeout"], inputs: { settings: { "async.enabled": true, "launch.enabled": false }, facts: [] } },
	{ id: "async_off_launch_on", when: "async disabled; service launch available", inventory_rows: [2], properties: ["command", "cwd", "name", "pty", "ready", "timeout"], inputs: { settings: { "async.enabled": false, "launch.enabled": true }, facts: [] } },
	{ id: "async_on_launch_on", when: "async enabled; service launch available", inventory_rows: [3], properties: ["async", "command", "cwd", "name", "pty", "ready", "timeout"], inputs: { settings: { "async.enabled": true, "launch.enabled": true }, facts: [] } },
];

const EDIT_MODES = ["replace", "patch", "apply_patch", "hashline", "sloppy"] as const;
const EDIT_VARIANTS: VariantSpec[] = EDIT_MODES.map((mode, index) => ({
	id: mode,
	when: `mode=${mode}`,
	inventory_rows: [index],
	properties: mode === "replace" ? ["old_string", "path", "new_string", "replace_all"] : mode === "patch" ? ["edits", "path"] : ["input"],
	inputs: { settings: { "edit.mode": mode }, facts: [`edit.mode=${mode}`] },
}));

const EVAL_VARIANTS: VariantSpec[] = [
	{ id: "py_js", when: "py and js enabled", inventory_rows: [0], properties: ["code", "language", "reset", "timeout", "title"], inputs: { settings: { "eval.py": true, "eval.js": true }, facts: [] } },
	{ id: "py_only", when: "only py enabled", inventory_rows: [1], properties: ["code", "language", "reset", "timeout", "title"], inputs: { settings: { "eval.py": true, "eval.js": false }, facts: [] } },
	{ id: "js_only", when: "only js enabled", inventory_rows: [2], properties: ["code", "language", "reset", "timeout", "title"], inputs: { settings: { "eval.py": false, "eval.js": true }, facts: [] } },
];

const TASK_DIMENSIONS: Array<{ isolation: boolean; batch: boolean; effort: boolean; evalTools: boolean }> = [
	{ isolation: false, batch: false, effort: false, evalTools: false },
	{ isolation: false, batch: false, effort: false, evalTools: true },
	{ isolation: false, batch: false, effort: true, evalTools: false },
	{ isolation: false, batch: false, effort: true, evalTools: true },
	{ isolation: true, batch: false, effort: false, evalTools: false },
	{ isolation: true, batch: false, effort: false, evalTools: true },
	{ isolation: true, batch: false, effort: true, evalTools: false },
	{ isolation: true, batch: false, effort: true, evalTools: true },
	{ isolation: false, batch: true, effort: false, evalTools: false },
	{ isolation: false, batch: true, effort: false, evalTools: true },
	{ isolation: false, batch: true, effort: true, evalTools: false },
	{ isolation: false, batch: true, effort: true, evalTools: true },
	{ isolation: true, batch: true, effort: false, evalTools: false },
	{ isolation: true, batch: true, effort: false, evalTools: true },
	{ isolation: true, batch: true, effort: true, evalTools: false },
	{ isolation: true, batch: true, effort: true, evalTools: true },
];

const TASK_VARIANTS: VariantSpec[] = TASK_DIMENSIONS.map((dimension, index) => ({
	id: `d${String(index).padStart(2, "0")}`,
	inventory_rows: [index],
	when:
		`${dimension.batch ? "batch" : "single"}, isolation ${dimension.isolation ? "on" : "off"}, ` +
		`effort ${dimension.effort ? "on" : "off"}, eval-tools ${dimension.evalTools ? "on" : "off"}`,
	inputs: {
		settings: {
			"task.isolation.enabled": dimension.isolation,
			"task.batch": dimension.batch,
			"task.enableEffort": dimension.effort,
			"eval.tools.enabled": dimension.evalTools,
		},
		facts: [],
	},
}));

const TASK_EXTRA: VariantSpec = {
	id: "custom_default_agent",
	when: "single spawn, custom default agent (session spawn policy names `sonic`)",
	inputs: { settings: { "task.batch": false }, facts: ["getSessionSpawns=sonic"], extra: { getSessionSpawns: () => "sonic" } },
};

const MEMORY_SCOPE_SETTINGS = { "memory.backend": "mnemopi", "mnemopi.scoping": "global" } as const;
const DECLARED_OUTPUT_SCHEMA = {
	type: "object",
	properties: { answer: { type: "string" }, count: { type: "integer" } },
	required: ["answer"],
	additionalProperties: false,
} as const;

interface ToolPlan {
	/** Tool name as constructed. */
	name: string;
	variants: VariantSpec[];
	/**
	 * Set for tools the SDK or an extension session owns: the plain built-in
	 * session is not their construction path, and the gate names the owner.
	 */
	settings_gate?: string;
}

function variant(
	id: string,
	inputs: SessionInputs = { facts: [] },
	properties?: string[],
	build?: VariantSpec["build"],
): VariantSpec {
	return { id, inputs, properties, build };
}

function stubSessionManager(): ToolSession["sessionManager"] {
	// Experimental context management resolves the notebook through a manager
	// whose session id equals the ToolSession's; only that comparison is read
	// during construction, so a two-method stub is enough and is recorded as a
	// captured session fact.
	const manager = { getSessionId: () => CATALOG_SESSION_ID };
	return manager as unknown as ToolSession["sessionManager"];
}

const PLANS: ToolPlan[] = [
	{ name: "read", variants: [variant("default")] },
	{ name: "security_scan", variants: [variant("default")] },
	{ name: "bash", variants: BASH_VARIANTS },
	{ name: "edit", variants: EDIT_VARIANTS },
	{ name: "ast_grep", variants: [variant("default")] },
	{ name: "ast_edit", variants: [variant("default")] },
	{ name: "ask", variants: [variant("default", { facts: ["hasUI=true"], extra: { hasUI: true } })] },
	{ name: "debug", variants: [variant("default")] },
	{
		name: "ida",
		variants: [
			{
				id: "default",
				inputs: { settings: { "ida.installDir": IDA_STUB }, facts: ["ida.installDir=<gate probe directory>"] },
				notes: [
					"The ida factory gate is `exists(<ida.installDir>/libidalib.so)`; the catalog probe provisions an empty libidalib file under build/omp-catalog-scratch so the real class is constructed. The descriptor is class-static and no IDA installation, database or process is involved.",
				],
			},
		],
	},
	{ name: "eval", variants: EVAL_VARIANTS },
	{ name: "github", variants: [variant("default")] },
	{ name: "glob", variants: [variant("default")] },
	{ name: "grep", variants: [variant("default")] },
	{ name: "find", variants: [variant("default")] },
	{ name: "lsp", variants: [variant("default", { facts: ["enableLsp=default"] })] },
	{ name: "checkpoint", variants: [variant("default")] },
	{ name: "rewind", variants: [variant("default")] },
	{
		name: "context_notes",
		variants: [
			variant("default", {
				settings: { "compaction.experimentalContextManagement": true },
				facts: ["sessionManager(stub)=catalog session owner"],
				extra: { sessionManager: stubSessionManager(), getSessionId: () => CATALOG_SESSION_ID },
			}),
		],
	},
	{
		name: "new_context",
		variants: [
			variant("default", {
				settings: { "compaction.experimentalContextManagement": true },
				facts: ["sessionManager(stub)=catalog session owner"],
				extra: { sessionManager: stubSessionManager(), getSessionId: () => CATALOG_SESSION_ID },
			}),
		],
	},
	{ name: "task", variants: [...TASK_VARIANTS, TASK_EXTRA] },
	{ name: "wait", variants: [variant("default")] },
	{ name: "todo", variants: [variant("default")] },
	{ name: "web_search", variants: [variant("default")] },
	{
		name: "write",
		variants: [
			{ id: "default", when: "normal write grant", inventory_rows: [0], inputs: { facts: ["deviceOnlyWrite=false"] } },
			{
				id: "device_only",
				when: "device-only transport granted for read-only explicit list",
				inventory_rows: [1],
				inputs: { facts: ["deviceOnlyWrite=true"], extra: { deviceOnlyWrite: true } },
			},
		],
	},
	{ name: "memory_edit", variants: [variant("default", { settings: { "memory.backend": "mnemopi" }, facts: ["memory.backend=mnemopi"] })] },
	{
		name: "retain",
		variants: [
			{ id: "default", when: "no shared global bank advertised", inventory_rows: [0], inputs: { settings: { "memory.backend": "mnemopi" }, facts: ["memory.backend=mnemopi"] } },
			{ id: "global_scope", when: "memory.backend=mnemopi and mnemopi.scoping != per-project", inventory_rows: [1], inputs: { settings: MEMORY_SCOPE_SETTINGS, facts: ["memory.backend=mnemopi", "mnemopi.scoping=global"] } },
		],
	},
	{ name: "recall", variants: [variant("default", { settings: { "memory.backend": "mnemopi" }, facts: ["memory.backend=mnemopi"] })] },
	{ name: "reflect", variants: [variant("default", { settings: { "memory.backend": "mnemopi" }, facts: ["memory.backend=mnemopi"] })] },
	{
		name: "learn",
		variants: [
			{ id: "default", when: "global scope unavailable", inventory_rows: [0], inputs: { settings: { "memory.backend": "mnemopi", "autolearn.enabled": true }, facts: ["memory.backend=mnemopi"] } },
			{ id: "global_scope", when: "Mnemopi shared bank available", inventory_rows: [1], inputs: { settings: { ...MEMORY_SCOPE_SETTINGS, "autolearn.enabled": true }, facts: ["memory.backend=mnemopi", "mnemopi.scoping=global"] } },
		],
	},
	{ name: "manage_skill", variants: [variant("default", { settings: { "autolearn.enabled": true }, facts: ["autolearn.enabled=true"] })] },
	{ name: "think", variants: [variant("default")] },
	{
		name: "yield",
		variants: [
			{ id: "declared_schema", when: "ordinary child, valid declared output schema", inventory_rows: [0], inputs: { facts: ["outputSchema=declared object schema"], extra: { outputSchema: DECLARED_OUTPUT_SCHEMA } } },
			{ id: "no_schema", when: "no output schema / invalid or nonrepresentable processing path", inventory_rows: [1], inputs: { facts: ["outputSchema=absent"] } },
			{ id: "workpool_items", when: "workpool items present", inventory_rows: [2], inputs: { facts: ["getWorkPoolYieldItems=2 items"], extra: { getWorkPoolYieldItems: () => YIELD_WORKPOOL_ITEMS } } },
		],
	},
	{ name: "goal", variants: [variant("default")] },
	{
		name: "generate_image",
		settings_gate: "SDK settingsGatedCustomEntries: cfgGenerateImageEnabled",
		variants: [variant("default", { facts: ["settings gated custom entry"] }, undefined, () => imageGenTool)],
	},
	{
		name: "tts",
		settings_gate: "SDK settingsGatedCustomEntries: cfgSpeechgenEnabled",
		variants: [variant("default", { facts: ["settings gated custom entry"] }, undefined, () => ttsTool)],
	},
];

// ─────────────────────────────────────────────────────────────────────────────
// Owned-session tool families (autoresearch, vibe, advisor, commit, compression,
// security publication): their factories are called with the arguments the SDK
// passes. Dependencies that are only read inside `execute` stay stubs and are
// recorded per variant.

const AUTORESEARCH_OPTIONS = {
	dashboard: {},
	getRuntime: () => ({}),
	pi: {},
} as unknown as AutoresearchToolFactoryOptions;

const COMMIT_OPTIONS: Omit<CommitToolOptions, "cwd" | "settings"> = {
	authStorage: {} as unknown as CommitToolOptions["authStorage"],
	modelRegistry: {} as unknown as CommitToolOptions["modelRegistry"],
	spawns: "*",
	state: {},
	changelogTargets: ["CHANGELOG.md"],
};

function autoresearchPlans(): ToolPlan[] {
	const settings = Settings.isolated({});
	const options = { ...AUTORESEARCH_OPTIONS, settings };
	const gate = "autoresearch extension: active only while the autoresearch session mode is on";
	return [
		{ name: "init_experiment", settings_gate: gate, variants: [variant("default", { facts: [] }, undefined, () => createInitExperimentTool(options))] },
		{ name: "run_experiment", settings_gate: gate, variants: [variant("default", { facts: [] }, undefined, () => createRunExperimentTool(options))] },
		{ name: "log_experiment", settings_gate: gate, variants: [variant("default", { facts: [] }, undefined, () => createLogExperimentTool(options))] },
		{ name: "update_notes", settings_gate: gate, variants: [variant("default", { facts: [] }, undefined, () => createUpdateNotesTool(options))] },
	];
}

function vibePlan(): ToolPlan {
	const gate = "SessionTools vibe registry: top-level session only";
	return {
		name: "vibe_spawn",
		settings_gate: gate,
		variants: [
			variant("vibe_spawn", { facts: [] }, undefined, session => createVibeTools(session)[0]),
			variant("vibe_send", { facts: [] }, undefined, session => createVibeTools(session)[1]),
			variant("vibe_wait", { facts: [] }, undefined, session => createVibeTools(session)[2]),
			variant("vibe_kill", { facts: [] }, undefined, session => createVibeTools(session)[3]),
			variant("vibe_list", { facts: [] }, undefined, session => createVibeTools(session)[4]),
		].map(spec => ({ ...spec, tool: spec.id })),
	};
}

function commitPlan(): ToolPlan {
	const gate = "dedicated commit-agent customTools";
	return {
		name: "git_overview",
		settings_gate: gate,
		variants: [
			variant("git_overview", { facts: ["cwd=scratch git repository"] }, undefined, () => commitTools()[0]),
			variant("git_file_diff", { facts: ["cwd=scratch git repository"] }, undefined, () => commitTools()[1]),
			variant("git_hunk", { facts: ["cwd=scratch git repository"] }, undefined, () => commitTools()[2]),
			variant("recent_commits", { facts: ["cwd=scratch git repository"] }, undefined, () => commitTools()[3]),
			variant("analyze_files", { facts: ["cwd=scratch git repository"] }, undefined, () => commitTools()[4]),
			variant("propose_changelog", { facts: ["cwd=scratch git repository"] }, undefined, () => commitTools()[5]),
			variant("propose_commit", { facts: ["cwd=scratch git repository"] }, undefined, () => commitTools()[6]),
			variant("split_commit", { facts: ["cwd=scratch git repository"] }, undefined, () => commitTools()[7]),
		].map(spec => ({ ...spec, tool: spec.id })),
	};
}

function commitTools() {
	return createCommitTools({ ...COMMIT_OPTIONS, cwd: WORKSPACE, settings: Settings.isolated({}) });
}

const PROTOCOL = new CompressProtocol("catalog extraction source text");

const FAMILY_PLANS: ToolPlan[] = [
	...autoresearchPlans(),
	vibePlan(),
	{
		name: "advise",
		settings_gate: "separate advisor agent loop, not the primary toolRegistry",
		variants: [variant("default", { facts: [] }, undefined, () => new AdviseTool(() => {}))],
	},
	commitPlan(),
	{
		name: "rewrite",
		settings_gate: "restricted compression-session customTools",
		variants: [variant("default", { facts: [] }, undefined, () => PROTOCOL.rewriteTool())],
	},
	{
		name: "approve",
		settings_gate: "restricted compression-session customTools",
		variants: [variant("default", { facts: [] }, undefined, () => PROTOCOL.approveTool())],
	},
	{
		name: "security_publish",
		settings_gate: "dedicated security-review session publicationTool",
		variants: [
			variant("default", { facts: ["plan.repositoryRoot=scratch workspace"] }, undefined, () =>
				createSecurityPublicationTool({
					plan: { repositoryRoot: WORKSPACE } as unknown as Parameters<typeof createSecurityPublicationTool>[0]["plan"],
					scanId: "catalog-scan",
					store: {} as unknown as Parameters<typeof createSecurityPublicationTool>[0]["store"],
					startedAt: new Date(0).toISOString(),
				}),
			),
		],
	},
];

// ─────────────────────────────────────────────────────────────────────────────
// Inventory metadata

interface InventoryVariant {
	when: string;
	source?: string;
	arguments?: string;
	required?: string[] | null;
}

interface InventoryTool {
	name: string;
	origin: string;
	registry?: string;
	factory: string;
	source: string[];
	availability: string;
	dependencies?: string[];
	tests?: string[];
	jido_action_target?: string;
	proposed_jido_category?: string;
	schema_variants: InventoryVariant[];
}

function loadInventory(): InventoryTool[] {
	const parsed: unknown = JSON.parse(fs.readFileSync(INVENTORY_JSON, "utf8"));
	if (!isRecord(parsed)) throw new Error("inventory is not an object");
	const tools = parsed.tools;
	if (!isRecord(tools)) throw new Error("inventory.tools is not an object");
	const entries = tools.tools;
	if (!Array.isArray(entries)) throw new Error("inventory.tools.tools is not an array");
	return entries as InventoryTool[];
}

/**
 * Top-level names of an inventory `arguments` description such as
 * `{path:string,edits:{op?:'create'}[]}`. The first brace group wins; the
 * workpool/flat runtime rows of `task` are matched against the schema whose
 * properties they name. Returns null when the text carries no brace group.
 */
function inventoryArgumentNames(text: string): string[] | null {
	const start = text.indexOf("{");
	if (start === -1) return null;
	let depth = 0;
	let end = -1;
	for (let index = start; index < text.length; index++) {
		const character = text[index];
		if (character === "{") depth++;
		else if (character === "}") {
			depth--;
			if (depth === 0) {
				end = index;
				break;
			}
		}
	}
	if (end === -1) return null;
	const body = text.slice(start + 1, end);
	const names: string[] = [];
	let nested = 0;
	let token = "";
	for (let index = 0; index < body.length; index++) {
		const character = body[index];
		if (character === "{" || character === "[") nested++;
		if (character === "}" || character === "]") nested--;
		if (nested === 0 && character === ":") {
			const match = /([A-Za-z_][A-Za-z0-9_]*)\??\s*$/.exec(token);
			if (match !== null && !names.includes(match[1])) names.push(match[1]);
			token = "";
		}
		if (nested === 0 && character === ",") token = "";
		if (nested === 0 && character !== ":") token += character;
		if (nested > 0) token = "";
	}
	return names;
}

interface Coverage {
	index: number;
	when: string;
	source: string | null;
	mode: "schema" | "runtime_acceptance" | "uncovered";
	/** The captured variant whose schema satisfies this recorded row. */
	variant: string | null;
	/** Every captured variant that matches structurally; several may share a shape. */
	matches: string[];
	note: string | null;
}

/** Names and required keys an inventory row names, when its text is parseable. */
function rowShape(variant: InventoryVariant): { names: string[] | null; required: string[] | null } {
	return {
		names: variant.arguments === undefined ? null : inventoryArgumentNames(variant.arguments),
		required: Array.isArray(variant.required) ? [...variant.required].sort() : null,
	};
}

function matchesShape(candidate: CapturedVariant, shape: { names: string[] | null; required: string[] | null }): boolean {
	if (shape.names === null) return false;
	if (candidate.properties.join(",") !== [...shape.names].sort().join(",")) return false;
	return shape.required === null || candidate.required.join(",") === shape.required.join(",");
}

/**
 * Maps every recorded inventory row to the captured schema that satisfies it.
 * An authored claim (`inventory_rows`) is verified against the captured schema
 * first; the remaining rows are matched structurally. A row that is neither
 * claimed nor structurally matched is reported as uncovered, which fails the
 * build.
 */
function resolveCoverage(entry: InventoryTool, captured: CapturedVariant[]): Coverage[] {
	const assigned = new Map<number, string>();
	for (const item of captured) {
		for (const index of item.spec_rows) {
			const row = entry.schema_variants[index];
			if (row === undefined) throw new Error(`${entry.name}/${item.id}: claims missing inventory row ${index}`);
			if (!matchesShape(item, rowShape(row))) {
				throw new Error(
					`${entry.name}/${item.id}: claimed row ${index} has a different schema ` +
						`(${rowShape(row).names?.join(",")} != ${item.properties.join(",")})`,
				);
			}
			const existing = assigned.get(index);
			if (existing !== undefined && existing !== item.id) {
				throw new Error(`${entry.name}: row ${index} is claimed by both ${existing} and ${item.id}`);
			}
			assigned.set(index, item.id);
		}
	}
	return entry.schema_variants.map((row, index) => {
		const shape = rowShape(row);
		const matches = captured.filter(candidate => matchesShape(candidate, shape)).map(candidate => candidate.id);
		const claimed = assigned.get(index);
		if (claimed === undefined && matches.length === 0) {
			return {
				index,
				when: row.when,
				source: row.source ?? null,
				mode: "uncovered",
				variant: null,
				matches: [],
				note: row.arguments ?? null,
			};
		}
		const runtime = row.when.includes("runtime acceptance");
		return {
			index,
			when: row.when,
			source: row.source ?? null,
			mode: runtime ? "runtime_acceptance" : "schema",
			variant: claimed ?? matches[0],
			matches,
			note: runtime ? (row.arguments ?? null) : null,
		};
	});
}

// ─────────────────────────────────────────────────────────────────────────────
// Build

interface CatalogTool {
	name: string;
	membership: "descriptive";
	origin: string;
	factory: string;
	construct: string;
	jido_target: string | null;
	port_status: "declared_target_only";
	availability: string;
	dependencies: string[];
	source: string[];
	tests: string[];
	/** Factory/class returned non-null in a plain session at build time. */
	constructs_in_plain_session: boolean;
	plain_session_gate: string | null;
	canonical_variant: string;
	variants: Array<
		Omit<CapturedVariant, "spec_when" | "spec_rows"> & {
			when: string;
			inventory_rows: number[];
			source: string | null;
		}
	>;
	inventory_variants: Coverage[];
}

interface BuiltCatalog {
	schema_version: number;
	generated_by: string;
	reference: {
		repository: string;
		revision: string;
		version: string;
		license: string;
		license_sha256: string;
		package: string;
		schema_reader: string;
		inventory: string;
	};
	/** Canonicalization facts produced by the pinned normalizer itself. */
	name_normalization: {
		source: string;
		canonical_names: string[];
		probes: { [input: string]: string };
		aliases: { [lowerInput: string]: string };
	};
	/**
	 * Which layer each fact belongs to. The catalog records potential and
	 * descriptors; enablement and implementation are separate claims.
	 */
	claims: {
		membership: string;
		constructs_in_plain_session: string;
		enabled_selection: string;
		implemented: string;
	};
	counts: {
		tools: number;
		captured_tools: number;
		captured_variants: number;
		inventory_variants: number;
		inventory_variants_covered: number;
	};
	tools: CatalogTool[];
}

/** Inputs whose normalization the catalog records; custom spelling stays intact. */
const NAME_PROBES = ["read", "READ", "Read", "search", "SEARCH", "Search", "grep", "MyTool", "my-tool"];

function nameNormalization(): BuiltCatalog["name_normalization"] {
	const probes: Record<string, string> = {};
	const aliases: Record<string, string> = {};
	for (const input of NAME_PROBES) {
		const normalized = normalizeToolName(input);
		probes[input] = normalized;
		if (normalized !== input.toLowerCase()) aliases[input.toLowerCase()] = normalized;
	}
	return {
		source: "build/upstream/oh-my-pi/packages/coding-agent/src/tools/builtin-names.ts",
		canonical_names: [...BUILTIN_TOOL_NAMES, ...HIDDEN_TOOL_NAMES],
		probes,
		aliases,
	};
}

interface DefaultSession {
	constructible: boolean;
	gate: string | null;
}

/**
 * Constructs the tool in a plain session — no settings overrides, no extra
 * session fields — matching the default coding session the SDK builds. Tools an
 * extension or the SDK owns are not reachable this way; their owning gate is
 * recorded instead.
 */
async function probeDefaultSession(name: string, gate: string | undefined): Promise<DefaultSession> {
	if (gate !== undefined) return { constructible: false, gate };
	const factory = TOOL_FACTORIES[name];
	if (factory === undefined) return { constructible: false, gate: "not a built-in factory" };
	try {
		const tool = await factory(buildSession({ facts: [] }));
		return { constructible: tool !== null, gate: tool === null ? "factory returned null (see availability)" : null };
	} catch (error) {
		return { constructible: false, gate: `construction failed: ${(error as Error).message}` };
	}
}

async function build(): Promise<BuiltCatalog> {
	assertPinnedSource();
	prepareScratch();
	const inventory = loadInventory();
	const groups = [...PLANS, ...FAMILY_PLANS];
	const inventoryNames = new Set(inventory.map(entry => entry.name));

	// Phase 1: construct every variant of every group and file it under the tool
	// name the constructed object reports.
	const capturesByTool = new Map<string, CapturedVariant[]>();
	const gatesByTool = new Map<string, string>();
	for (const group of groups) {
		for (const spec of group.variants) {
			const name = spec.tool ?? group.name;
			if (!inventoryNames.has(name)) throw new Error(`${name}: captured tool is not in the inventory`);
			const captured = await capture(group.name, spec);
			const bucket = capturesByTool.get(name) ?? [];
			bucket.push(captured);
			capturesByTool.set(name, bucket);
			if (group.settings_gate !== undefined) gatesByTool.set(name, group.settings_gate);
		}
	}

	// Phase 2: build the catalog in recorded inventory order.
	const tools: CatalogTool[] = [];
	const uncovered: string[] = [];
	for (const entry of inventory) {
		const captured = capturesByTool.get(entry.name);
		if (captured === undefined) throw new Error(`${entry.name}: no captured variants`);
		const coverage = resolveCoverage(entry, captured);
		for (const row of coverage) {
			if (row.mode === "uncovered") uncovered.push(`${entry.name}[${row.index}]: ${row.note ?? row.when}`);
		}
		const variants = captured.map(item => {
			const rows = coverage.filter(candidate => candidate.variant === item.id);
			// A variant that satisfied several rows (identical property sets, e.g.
			// the write grant/device-only pair) must carry its own gate text.
			const when = item.spec_when ?? (rows.length === 1 ? rows[0].when : null);
			if (when === null) throw new Error(`${entry.name}/${item.id}: ambiguous inventory match needs an authored when label`);
			const { spec_when: _specWhen, spec_rows: _specRows, ...rest } = item;
			return { ...rest, when, inventory_rows: rows.map(row => row.index), source: rows[0]?.source ?? null };
		});
		const canonical = captured[0];
		const defaultSession = await probeDefaultSession(entry.name, gatesByTool.get(entry.name));
		tools.push({
			name: entry.name,
			membership: "descriptive",
			origin: entry.origin,
			factory: entry.factory,
			construct: canonical.construction,
			jido_target: entry.jido_action_target ?? null,
			port_status: "declared_target_only",
			availability: entry.availability,
			dependencies: entry.dependencies ?? [],
			source: entry.source,
			tests: entry.tests ?? [],
			constructs_in_plain_session: defaultSession.constructible,
			plain_session_gate: defaultSession.gate,
			canonical_variant: canonical.id,
			variants,
			inventory_variants: coverage,
		});
	}
	if (uncovered.length > 0) throw new Error(`inventory variants without captured schema data:\n  ${uncovered.join("\n  ")}`);

	const catalog: BuiltCatalog = {
		schema_version: 1,
		generated_by: "scripts/build-omp-catalog.ts",
		reference: {
			repository: REFERENCE.repository,
			revision: EXPECTED_COMMIT,
			version: REFERENCE.version,
			license: REFERENCE.license,
			license_sha256: digest(fs.readFileSync(path.join(UPSTREAM, "LICENSE"), "utf8")),
			package: "@oh-my-pi/pi-coding-agent",
			schema_reader: "build/upstream/oh-my-pi/packages/ai/src/utils/schema/wire.ts#toolWireSchema",
			inventory: "docs/omp-inventory.json",
		},
		name_normalization: nameNormalization(),
		claims: {
			membership:
				"Descriptive inventory membership: the tool ID exists in the pinned SDK inventory and a descriptor was captured. Membership alone enables nothing.",
			constructs_in_plain_session:
				"The pinned factory/class returned a tool in a plain session (no settings overrides, no extra session fields) during the build. The session plan's enabled selection is a separate, settings-driven claim this catalog does not make.",
			enabled_selection:
				"Owned by the session plan (settings gates plus explicit tool lists); query Elixos.Toolset/Catalog summaries, not membership.",
			implemented:
				"Runtime query: Elixos.Toolset.Catalog.implemented/0 lists tools whose recorded jido_target module is loaded in this VM and implements the Jido action contract (run/2 plus validate_params/1).",
		},
		counts: {
			tools: inventory.length,
			captured_tools: tools.length,
			captured_variants: tools.reduce((total, tool) => total + tool.variants.length, 0),
			inventory_variants: inventory.reduce((total, entry) => total + entry.schema_variants.length, 0),
			inventory_variants_covered: tools.reduce(
				(total, tool) => total + tool.inventory_variants.filter(row => row.mode !== "uncovered").length,
				0,
			),
		},
		tools,
	};
	if (catalog.counts.tools !== catalog.counts.captured_tools) throw new Error("captured tool count differs from the inventory");
	return catalog;
}

const catalog = await build();
fs.mkdirSync(path.dirname(DESTINATION), { recursive: true });
fs.writeFileSync(DESTINATION, `${JSON.stringify(catalog, null, "\t")}\n`);
const bytes = fs.statSync(DESTINATION).size;
console.log(
	`OMP_CATALOG: ${catalog.counts.captured_tools} tools, ${catalog.counts.captured_variants} captured variants, ` +
		`${catalog.counts.inventory_variants_covered}/${catalog.counts.inventory_variants} inventory variants covered, ` +
		`${bytes} bytes; sha256=${digest(fs.readFileSync(DESTINATION, "utf8"))}; reference=${EXPECTED_COMMIT}`,
);
