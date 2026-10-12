#!/usr/bin/env bun
/**
 * M21 real-reference recorder for the OMP `todo` tool (ADR-047).
 *
 * Runs the *real* pinned upstream `TodoTool` (`packages/coding-agent/src/tools/todo.ts`)
 * against a real minimal upstream `ToolSession` whose todo memory is a plain
 * in-memory list, and records every result verbatim:
 *
 *   reference              package/version/integrity of the pinned SDK
 *   coverage               nominal | malformed | unicode | large_payload
 *   roots                  the two distinct absolute recording roots
 *   workspace/session_dir  initial workspace and session file maps
 *   initial_session        real in-memory phases before setup_calls (`[]`)
 *   setup_calls            each earlier call on the *same* session, in the same
 *                          shape as the recorded call below
 *   params/arguments       the raw arguments and the JSON form of what
 *                          `validateAgentToolArguments` handed to `execute`
 *   output | error         the exact JSON form of the AgentToolResult, or
 *                          {"kind": <Error name>, "message": <Error message>}
 *   committed_todo_phases  the real `committedTodoPhases(result)` (null when
 *                          undefined: errors and pure `view` reads)
 *   session                real in-memory phases, the phases this call handed
 *                          to setTodoPhases (null when it committed nothing),
 *                          and the session's total write count
 *   dropped_undefined      JSON paths dropped because their value is undefined
 *   effects                complete post-call workspace/session file maps
 *
 * Every call goes through the same public path the agent loop uses:
 * `validateAgentToolArguments(tool, call)` then `tool.execute(callId, args)`.
 * Nothing is synthesized: a fixture is written only when two independent
 * recording runs under different absolute roots agree after the roots are
 * rebound, and the contract self-check below (state-changing calls commit
 * exactly once, failed calls commit nothing and leave the memory untouched,
 * `committedTodoPhases` is null exactly for errors and `view`) passes.
 * `TodoTool` performs no filesystem effect, so both file maps stay empty
 * except for a deliberately pre-created session file.
 *
 *
 * Run from the repository root:
 *
 *   bun scripts/omp-fixtures/todo.ts                 # all cases, 2 roots
 *   bun scripts/omp-fixtures/todo.ts --only view-empty,init-flat-items
 *   bun scripts/omp-fixtures/todo.ts --runs 3
 *
 * Options: --only <csv> --runs <n> --scratch <dir> --out <dir> --help
 *
 * Fixtures land in build/omp-todo-fixtures/todo/ (not the protected
 * os/test/fixtures/omp tree) with an observations sidecar next to them.
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

import { validateAgentToolArguments } from "../../build/upstream/oh-my-pi/packages/agent/src/tool-arguments";
import { toolWireSchema } from "../../build/upstream/oh-my-pi/packages/ai/src/utils/schema/wire";
import { Settings } from "../../build/upstream/oh-my-pi/packages/coding-agent/src/config/settings";
import { TodoTool, committedTodoPhases } from "../../build/upstream/oh-my-pi/packages/coding-agent/src/tools/todo";
import type { Tool, ToolSession } from "../../build/upstream/oh-my-pi/packages/coding-agent/src/tools/index";
import type { TodoPhase } from "../../build/upstream/oh-my-pi/packages/tui/src/tools/todo";
import { isRecord } from "../../build/upstream/oh-my-pi/packages/utils/src/type-guards";

const REPO_ROOT = path.resolve(import.meta.dir, "..", "..");
const UPSTREAM = path.join(REPO_ROOT, "build", "upstream", "oh-my-pi");
const CODING_AGENT_PACKAGE_JSON = path.join(UPSTREAM, "packages", "coding-agent", "package.json");

/** The pin recorded into every fixture's `reference`. */
const REFERENCE = {
	package: "@oh-my-pi/pi-coding-agent",
	version: "18.10.1",
	integrity:
		"sha512-xvHDKLcAsGvDwLQG6PHZEYiELQPKJ4NiSc/yeurja8IZkC7yALjR+2pbEiCT4cSdyIfEmHFDhDUze8hSxYpiZA==",
};
const EXPECTED_COMMIT = "90701813e5fba6919067848989378b4ee6239c13";
const REFERENCE_SOURCE = "https://github.com/can1357/oh-my-pi (packages/coding-agent)";
const CALL_ID = "fixture-call";
const LARGE_PAYLOAD_BYTES = 65_536;

const COVERAGE_CATEGORIES: Record<string, true> = {
	nominal: true,
	malformed: true,
	unicode: true,
	large_payload: true,
};

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type FileMap = Record<string, string | { base64: string }>;

interface CallRun {
	params: Json;
	/** What `validateAgentToolArguments` handed to `execute` (null when it threw). */
	arguments: Json | null;
	/** Exact JSON form of the AgentToolResult; null when the call threw. */
	output: Json | null;
	error: { kind: string; message: string } | null;
	/** The real `committedTodoPhases(result)`, or null when it is undefined. */
	committed: Json | null;
	session: { phases: Json; writes: number; committed: Json | null };
	droppedUndefined: string[];
}

interface CaseSpec {
	name: string;
	coverage: string[];
	params: Json;
	setup?: Json[];
	sessionFile?: string;
	note?: string;
}

interface CaseRun {
	roots: { workspace: string; session_dir: string };
	initial: { workspace: FileMap; session_dir: FileMap };
	setup: CallRun[];
	call: CallRun;
	final: { workspace: FileMap; session_dir: FileMap };
	foreignPaths: string[];
}

// ─────────────────────────────────────────────────────────────────────────────
// CLI

interface Options {
	only: string[];
	runs: number;
	scratch: string;
	out: string;
}

function parseOptions(argv: string[]): Options {
	if (argv.includes("--help") || argv.includes("-h")) {
		console.log(
			[
				"bun scripts/omp-fixtures/todo.ts [--only case,csv] [--runs n]",
				"                                [--scratch dir] [--out dir]",
				"",
				"Records real pinned-SDK todo outcomes into build/omp-todo-fixtures/todo/*.json.",
			].join("\n"),
		);
		process.exit(0);
	}
	const value = (flag: string): string | undefined => {
		const index = argv.indexOf(flag);
		if (index === -1) return undefined;
		const next = argv[index + 1];
		if (next === undefined || next.startsWith("--")) throw new Error(`${flag} needs a value`);
		return next;
	};
	const only = value("--only")?.split(",").map(part => part.trim()).filter(Boolean) ?? [];
	const runsRaw = value("--runs");
	const runs = runsRaw === undefined ? 2 : Number(runsRaw);
	if (!Number.isInteger(runs) || runs < 2) throw new Error("--runs must be an integer >= 2");
	return {
		only,
		runs,
		scratch: value("--scratch") ?? path.join(REPO_ROOT, "build", "omp-todo-fixture-record"),
		out: value("--out") ?? path.join(REPO_ROOT, "build", "omp-todo-fixtures"),
	};
}

// ─────────────────────────────────────────────────────────────────────────────
// Pinned-source preflight

function assertPinnedSource(): string {
	if (!fs.existsSync(CODING_AGENT_PACKAGE_JSON)) {
		throw new Error(`prepared upstream checkout is missing: ${CODING_AGENT_PACKAGE_JSON}`);
	}
	const packageJson: unknown = JSON.parse(fs.readFileSync(CODING_AGENT_PACKAGE_JSON, "utf8"));
	const version = isRecord(packageJson) ? packageJson.version : undefined;
	if (version !== REFERENCE.version) {
		throw new Error(`checkout package version ${String(version)} does not match recorder pin ${REFERENCE.version}`);
	}
	const head = spawnSync("git", ["-C", UPSTREAM, "rev-parse", "HEAD"], { encoding: "utf8" });
	const commit = head.status === 0 ? head.stdout.trim() : null;
	if (commit !== EXPECTED_COMMIT) {
		throw new Error(`checkout HEAD ${String(commit)} does not match recorder pin ${EXPECTED_COMMIT}`);
	}
	console.log(`pinned checkout ${UPSTREAM}`);
	console.log(`  version ${REFERENCE.version} commit ${EXPECTED_COMMIT}`);
	return EXPECTED_COMMIT;
}

// ─────────────────────────────────────────────────────────────────────────────
// Session, tool, files

/** The real session memory the todo tool mutates; nothing else holds state. */
interface TodoMemory {
	phases: TodoPhase[];
	/** Every `setTodoPhases` argument, in order. */
	writes: TodoPhase[][];
}

/**
 * The minimally configured upstream `ToolSession`, as the upstream test
 * utilities build it, plus the session's todo callbacks. `getSessionFile`
 * answers with the case's real session-root file (or null), which is exactly
 * what decides `details.storage`.
 */
function buildSession(workspace: string, sessionFile: string | null, memory: TodoMemory): ToolSession {
	return {
		cwd: workspace,
		hasUI: false,
		enableLsp: false,
		getSessionFile: () => sessionFile,
		getSessionSpawns: () => "*",
		getTodoPhases: () => memory.phases,
		setTodoPhases: phases => {
			memory.writes.push(phases);
			memory.phases = phases;
		},
		settings: Settings.isolated({}),
	};
}

function restoreFiles(root: string, files: FileMap): void {
	fs.mkdirSync(root, { recursive: true });
	for (const relative of Object.keys(files).sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)))) {
		const entry = files[relative]!;
		const bytes = typeof entry === "string" ? Buffer.from(entry, "utf8") : Buffer.from(entry.base64, "base64");
		const destination = path.join(root, ...relative.split("/"));
		fs.mkdirSync(path.dirname(destination), { recursive: true });
		fs.writeFileSync(destination, bytes);
	}
}

function snapshotFiles(root: string): FileMap {
	const files: FileMap = {};
	const walk = (directory: string): void => {
		const entries = fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1));
		for (const entry of entries) {
			const full = path.join(directory, entry.name);
			const stat = fs.lstatSync(full);
			if (stat.isDirectory()) {
				walk(full);
				continue;
			}
			if (!stat.isFile()) throw new Error(`recorder cannot record non-regular entry at ${full}`);
			const bytes = fs.readFileSync(full);
			const text = bytes.toString("utf8");
			const relative = path.relative(root, full).split(path.sep).join("/");
			files[relative] = bytes.equals(Buffer.from(text, "utf8")) ? text : { base64: bytes.toString("base64") };
		}
	};
	if (fs.existsSync(root)) walk(root);
	return files;
}

// ─────────────────────────────────────────────────────────────────────────────
// Call, JSON form, comparisons

/**
 * JSON.stringify's exact JSON form. Fields JSON cannot represent (undefined
 * object members — `blocker` after `unblock`, `isError` on success) are dropped
 * by the runtime, so their paths are reported instead of silently normalized.
 */
function toJsonForm(value: unknown, where: string, dropped: string[]): Json {
	if (value === undefined) {
		dropped.push(where);
		return null;
	}
	if (value === null || typeof value === "boolean" || typeof value === "string") return value;
	if (typeof value === "number") {
		if (!Number.isFinite(value)) throw new Error(`non-finite number at ${where}`);
		return value;
	}
	if (Array.isArray(value)) return value.map((item, index) => toJsonForm(item, `${where}[${index}]`, dropped));
	if (isRecord(value)) {
		const converted: { [key: string]: Json } = {};
		for (const [key, item] of Object.entries(value)) {
			if (item === undefined) {
				dropped.push(`${where}.${key}`);
				continue;
			}
			converted[key] = toJsonForm(item, `${where}.${key}`, dropped);
		}
		return converted;
	}
	throw new Error(`non-JSON value at ${where}: ${typeof value}`);
}

function memorySnapshot(memory: TodoMemory, committed: TodoPhase[] | null, dropped: string[]): CallRun["session"] {
	return {
		phases: toJsonForm(memory.phases, "session.phases", dropped),
		writes: memory.writes.length,
		committed: committed === null ? null : toJsonForm(committed, "session.committed", dropped),
	};
}

/** One real upstream call: the SDK validation path, then `execute`. */
async function callTool(tool: Tool, params: Json, memory: TodoMemory): Promise<CallRun> {
	const dropped: string[] = [];
	const writesBefore = memory.writes.length;
	let arguments_: Json | null = null;
	try {
		const validated = validateAgentToolArguments(tool, {
			type: "toolCall",
			id: CALL_ID,
			name: tool.name,
			arguments: params,
		});
		arguments_ = toJsonForm(validated, "arguments", dropped);
		const raw: unknown = await tool.execute(CALL_ID, validated);
		const output = toJsonForm(raw, "output", dropped);
		const committed = committedTodoPhases(raw as Parameters<typeof committedTodoPhases>[0]);
		const committedJson = committed === undefined ? null : toJsonForm(committed, "committed", dropped);
		return {
			params,
			arguments: arguments_,
			output,
			error: null,
			committed: committedJson,
			session: memorySnapshot(memory, memory.writes[writesBefore] ?? null, dropped),
			droppedUndefined: dropped,
		};
	} catch (error) {
		const kind = error instanceof Error && error.name.length > 0 ? error.name : "Error";
		const message = error instanceof Error ? error.message : String(error);
		return {
			params,
			arguments: arguments_,
			output: null,
			error: { kind, message },
			committed: null,
			session: memorySnapshot(memory, null, dropped),
			droppedUndefined: dropped,
		};
	}
}

/** The fixture form of a call: exactly one of output/error, like the contract's top level. */
function toFixtureCall(call: CallRun): Record<string, Json> {
	return {
		tool: "todo",
		params: call.params,
		arguments: call.arguments,
		...(call.output === null ? { error: call.error } : { output: call.output }),
		committed_todo_phases: call.committed,
		session: call.session,
		dropped_undefined: call.droppedUndefined,
	};
}

function rebind(value: Json, bindings: [string, string][]): Json {
	if (typeof value === "string") {
		let result = value;
		for (const [from, to] of bindings) result = result.split(from).join(to);
		return result;
	}
	if (Array.isArray(value)) return value.map(item => rebind(item, bindings));
	if (value === null || typeof value !== "object") return value;
	const converted: { [key: string]: Json } = {};
	for (const [key, item] of Object.entries(value)) converted[rebind(key, bindings) as string] = rebind(item, bindings);
	return converted;
}

function sortKeys(value: unknown): unknown {
	if (Array.isArray(value)) return value.map(sortKeys);
	if (!isRecord(value)) return value;
	const sorted: Record<string, unknown> = {};
	for (const key of Object.keys(value).sort()) sorted[key] = sortKeys(value[key]);
	return sorted;
}

function canonical(value: unknown): string {
	return JSON.stringify(sortKeys(value));
}

/** Absolute-looking paths in a recorded call that no recorded root rebinds. */
function foreignAbsolutePaths(value: Json, roots: string[]): string[] {
	const found = new Set<string>();
	const walk = (item: Json): void => {
		if (typeof item === "string") {
			for (const match of item.match(/(?:\/[A-Za-z0-9._@+-]+){2,}/g) ?? []) {
				if (!roots.some(root => match.startsWith(root))) found.add(match);
			}
			return;
		}
		if (Array.isArray(item)) {
			for (const child of item) walk(child);
			return;
		}
		if (item !== null && typeof item === "object") {
			for (const child of Object.values(item)) walk(child);
		}
	};
	walk(value);
	return [...found].sort();
}

// ─────────────────────────────────────────────────────────────────────────────
// Recording

function resultIsError(call: CallRun): boolean {
	if (call.error !== null) return true;
	return isRecord(call.output) && call.output.isError === true;
}

function resultOp(call: CallRun): string | null {
	if (!isRecord(call.output)) return null;
	const details = call.output.details;
	return isRecord(details) && typeof details.op === "string" ? details.op : null;
}

function outcomeLabel(call: CallRun): string {
	if (call.error !== null) return `error:${call.error.kind}`;
	if (isRecord(call.output) && call.output.isError === true) return "error-result";
	return "output";
}

async function runCase(spec: CaseSpec, base: string): Promise<CaseRun> {
	fs.rmSync(base, { recursive: true, force: true });
	const workspace = path.join(base, "workspace");
	const sessionDir = path.join(base, "session");
	// A declared session file is a real initial file in the session root: it is
	// what makes `details.storage` "session" instead of "memory".
	restoreFiles(workspace, {});
	restoreFiles(sessionDir, spec.sessionFile === undefined ? {} : { [spec.sessionFile]: "" });
	const initial = { workspace: snapshotFiles(workspace), session_dir: snapshotFiles(sessionDir) };

	const memory: TodoMemory = { phases: [], writes: [] };
	const sessionFile = spec.sessionFile === undefined ? null : path.join(sessionDir, spec.sessionFile);
	const tool = new TodoTool(buildSession(workspace, sessionFile, memory));
	const setup: CallRun[] = [];
	for (const params of spec.setup ?? []) setup.push(await callTool(tool, params, memory));
	const call = await callTool(tool, spec.params, memory);

	const final = { workspace: snapshotFiles(workspace), session_dir: snapshotFiles(sessionDir) };
	const roots = { workspace, session_dir: sessionDir };
	const rootList = [workspace, sessionDir];
	return {
		roots,
		initial,
		setup,
		call,
		final,
		foreignPaths: foreignAbsolutePaths(toJsonForm({ setup, call }, "recorded", []), rootList),
	};
}

interface Verification {
	stable: boolean;
	detail: string;
}

function runPayload(run: CaseRun): unknown {
	return {
		initial: run.initial,
		setup: run.setup.map(call => ({ ...call, droppedUndefined: undefined })),
		call: { ...run.call, droppedUndefined: undefined },
		final: run.final,
	};
}

function verifyRuns(first: CaseRun, others: CaseRun[]): Verification {
	for (const [index, other] of others.entries()) {
		const bindings: [string, string][] = [
			[first.roots.workspace, other.roots.workspace],
			[first.roots.session_dir, other.roots.session_dir],
		];
		const expected = rebind(toJsonForm(runPayload(first), "run", []), bindings);
		const actual = toJsonForm(runPayload(other), "run", []);
		if (canonical(expected) !== canonical(actual)) {
			return { stable: false, detail: `run ${index + 2} differs: ${canonical(expected)} != ${canonical(actual)}` };
		}
	}
	return { stable: true, detail: `${others.length + 1} runs agree` };
}

// ─────────────────────────────────────────────────────────────────────────────
// Contract self-check (the invariants the Elixir replay driver asserts)

function inputStrings(value: Json): string[] {
	if (typeof value === "string") return [value];
	if (Array.isArray(value)) return value.flatMap(inputStrings);
	if (value === null || typeof value !== "object") return [];
	return Object.entries(value).flatMap(([key, item]) => [key, ...inputStrings(item)]);
}

function assertContract(spec: CaseSpec, run: CaseRun): void {
	if (spec.coverage.length === 0 || new Set(spec.coverage).size !== spec.coverage.length) {
		throw new Error("coverage must be a non-empty unique list");
	}
	for (const category of spec.coverage) {
		if (COVERAGE_CATEGORIES[category] !== true) throw new Error(`unknown coverage category ${category}`);
	}
	const workspace = run.roots.workspace;
	const sessionDir = run.roots.session_dir;
	if (!path.isAbsolute(workspace) || !path.isAbsolute(sessionDir)) throw new Error("roots must be absolute");
	if (workspace === sessionDir) throw new Error("roots must differ");
	if (workspace.startsWith(`${sessionDir}/`) || sessionDir.startsWith(`${workspace}/`)) {
		throw new Error("roots must not nest");
	}

	const failed = resultIsError(run.call);
	const op = resultOp(run.call);
	const readOnly = op === "view";
	if (spec.coverage.includes("nominal") && failed) throw new Error("nominal coverage needs a successful call");
	if (spec.coverage.includes("malformed") && !failed) {
		throw new Error("malformed coverage needs an error outcome or an error result");
	}
	if (spec.coverage.includes("unicode")) {
		const ok = inputStrings(spec.params).some(value => /[^\x00-\x7F]/.test(value));
		if (!ok) throw new Error("unicode coverage needs a non-ASCII input");
	}
	if (spec.coverage.includes("large_payload")) {
		const large = inputStrings(spec.params).some(value => Buffer.byteLength(value, "utf8") >= LARGE_PAYLOAD_BYTES);
		if (!large) throw new Error(`large_payload coverage needs one input string >= ${LARGE_PAYLOAD_BYTES} bytes`);
	}

	const previous = run.setup.at(-1)?.session.phases;
	// A failed call is atomic: nothing committed, memory untouched.
	if (failed && run.call.session.committed !== null) throw new Error("a failed call must not commit phases");
	if (failed && previous !== undefined && canonical(previous) !== canonical(run.call.session.phases)) {
		throw new Error("a failed call must leave the memory untouched");
	}
	if (!failed && readOnly && run.call.session.committed !== null) throw new Error("view must not commit phases");
	if (!failed && !readOnly && run.call.session.committed === null) {
		throw new Error("a successful state-changing call must commit once");
	}
	// committedTodoPhases is the host's persistence decision: exactly the
	// committed phases for a successful state-changing op, null otherwise.
	const committed = run.call.committed;
	if (!failed && !readOnly && canonical(committed) !== canonical(run.call.session.committed)) {
		throw new Error("committedTodoPhases must equal the phases handed to setTodoPhases");
	}
	if ((failed || readOnly) && committed !== null) throw new Error("committedTodoPhases must be null here");
	for (const call of run.setup) {
		if (resultIsError(call) && call.session.committed !== null) {
			throw new Error("a failed setup call must not commit phases");
		}
	}
	const expectedFiles = spec.sessionFile === undefined ? {} : { [spec.sessionFile]: "" };
	if (canonical(run.initial.session_dir) !== canonical(expectedFiles)) {
		throw new Error("initial session map must reflect the declared session file");
	}
	if (canonical(run.final.session_dir) !== canonical(expectedFiles)) {
		throw new Error("todo must not write to the session root");
	}
	if (canonical(run.initial.workspace) !== canonical({}) || canonical(run.final.workspace) !== canonical({})) {
		throw new Error("todo performs no workspace write; both maps must be empty");
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// The recorded cases

const NOMINAL_SEED: Json[] = [
	{
		op: "init",
		list: [
			{ phase: "Phase A", items: ["first", "second"] },
			{ phase: "Phase B", items: ["third"] },
		],
	},
];

const LARGE_ITEM = `bulk-${"x".repeat(LARGE_PAYLOAD_BYTES)}`;
const LARGE_ITEMS: Json[] = [LARGE_ITEM, ...Array.from({ length: 71 }, (_, index) => `${index}-bulk-${"x".repeat(1017)}`)];

const CASES: CaseSpec[] = [
	{
		name: "init-two-phases",
		coverage: ["nominal"],
		params: {
			op: "init",
			list: [
				{ phase: "Build", items: ["compile", "link"] },
				{ phase: "Verify", items: ["smoke", "report"] },
			],
		},
		note: "normalizeInProgressTask starts the first pending task of the first phase.",
	},
	{
		name: "init-flat-items",
		coverage: ["nominal"],
		params: { op: "init", items: ["alpha", "beta"] },
		note: "flat items with no phase land in the DEFAULT_INIT_PHASE.",
	},
	{
		name: "init-repair-missing-op-list",
		coverage: ["nominal"],
		params: { list: [{ phase: "Repaired", items: ["one", "two"] }] },
		note: "Raw arguments omit `op`; lenientArgValidation hands them through and the tool repairs to init.",
	},
	{
		name: "init-repair-items-empty-session",
		coverage: ["nominal"],
		params: { items: ["solo"] },
		note: "Bare items with no existing phases infer init.",
	},
	{
		name: "init-duplicate-task",
		coverage: ["malformed"],
		params: { op: "init", list: [{ phase: "Dup", items: ["same", "same"] }] },
	},
	{
		name: "init-duplicate-phase",
		coverage: ["malformed"],
		params: {
			op: "init",
			list: [
				{ phase: "Dup", items: ["a"] },
				{ phase: "Dup", items: ["b"] },
			],
		},
	},
	{
		name: "init-missing-list",
		coverage: ["malformed"],
		params: { op: "init" },
	},
	{
		name: "init-replaces-existing",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "init", list: [{ phase: "Fresh", items: ["only"] }] },
		note: "init is a replacement: the previous phases are discarded, not merged.",
	},
	{
		name: "init-over-existing-fails-atomically",
		coverage: ["malformed"],
		setup: NOMINAL_SEED,
		params: {
			op: "init",
			list: [
				{ phase: "Phase A", items: ["first", "first"] },
			],
		},
		note: "The duplicate check is within the new list; a rejected init leaves the previous list committed.",
	},
	{
		name: "missing-op-items-with-phase-append",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { items: ["appended"], phase: "Phase C" },
		note: "items + phase infer append once phases exist.",
	},
	{
		name: "start-moves-pointer",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "start", task: "third" },
	},
	{
		name: "start-unknown-task-id",
		coverage: ["malformed"],
		setup: NOMINAL_SEED,
		params: { op: "start", task: "task-1" },
		note: "task-N is answered with the content-addressed hint.",
	},
	{
		name: "start-unknown-task-empty",
		coverage: ["malformed"],
		params: { op: "start", task: "missing" },
		note: "The empty-list hint fires when no phases exist.",
	},
	{
		name: "done-auto-advance",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "done", task: "first" },
		note: "completedTasks carries the transition; the next pending task starts.",
	},
	{
		name: "done-phase",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "done", phase: "Phase B" },
	},
	{
		name: "done-no-target-empty",
		coverage: ["nominal"],
		params: { op: "done" },
	},
	{
		name: "done-worked-ahead-summary",
		coverage: ["nominal"],
		setup: [...NOMINAL_SEED, { op: "done", task: "third" }],
		params: { op: "done", task: "first" },
		note: "Completing in phase order after later work exercises the worked-ahead summary branch.",
	},
	{
		name: "rm-task",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "rm", task: "second" },
	},
	{
		name: "rm-phase",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "rm", phase: "Phase B" },
	},
	{
		name: "rm-all",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "rm" },
	},
	{
		name: "drop-task",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "drop", task: "third" },
	},
	{
		name: "drop-phase",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "drop", phase: "Phase A" },
	},
	{
		name: "block-task-with-reason",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "block", task: "second", reason: "waiting  on\n  the user" },
		note: "Whitespace runs in the reason collapse to single spaces.",
	},
	{
		name: "block-task-without-reason",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "block", task: "second" },
		note: "An absent reason leaves blocker undefined (dropped by JSON.stringify).",
	},
	{
		name: "block-phase-open-only",
		coverage: ["nominal"],
		setup: [
			{ op: "init", list: [{ phase: "Phase A", items: ["a1", "a2", "a3"] }] },
			{ op: "done", task: "a1" },
		],
		params: { op: "block", phase: "Phase A", reason: "external" },
		note: "Blocking a phase never reopens completed work.",
	},
	{
		name: "block-single-task-no-active",
		coverage: ["nominal"],
		setup: [{ op: "init", items: ["only"] }],
		params: { op: "block", task: "only", reason: "waiting" },
		note: "A blocked list keeps no in-progress pointer.",
	},
	{
		name: "block-requires-target",
		coverage: ["malformed"],
		setup: NOMINAL_SEED,
		params: { op: "block" },
	},
	{
		name: "unblock-task",
		coverage: ["nominal"],
		setup: [...NOMINAL_SEED, { op: "block", task: "second", reason: "waiting" }],
		params: { op: "unblock", task: "second" },
	},
	{
		name: "unblock-not-blocked",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "unblock", task: "first" },
		note: "Unblocking actionable work is a successful no-op that still commits.",
	},
	{
		name: "append-existing-phase",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "append", phase: "Phase A", items: ["later", "last"] },
	},
	{
		name: "append-new-phase",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "append", phase: "Phase C", items: ["extra"] },
	},
	{
		name: "append-duplicate-atomic",
		coverage: ["malformed"],
		setup: NOMINAL_SEED,
		params: { op: "append", phase: "Phase A", items: ["fresh", "first"] },
		note: "One duplicate rejects the whole batch: `fresh` is not appended.",
	},
	{
		name: "append-missing-items",
		coverage: ["malformed"],
		setup: NOMINAL_SEED,
		params: { op: "append", phase: "Phase A" },
	},
	{
		name: "append-missing-phase",
		coverage: ["malformed"],
		setup: NOMINAL_SEED,
		params: { op: "append", items: ["orphan"] },
	},
	{
		name: "view-populated",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "view" },
		note: "view is a read: no normalization, no setTodoPhases call.",
	},
	{
		name: "view-empty",
		coverage: ["nominal"],
		params: { op: "view" },
	},
	{
		name: "view-items-empty-tolerated",
		coverage: ["nominal"],
		setup: NOMINAL_SEED,
		params: { op: "view", items: [] },
		note: "The schema deliberately allows an empty items list on ops that ignore it.",
	},
	{
		name: "invalid-args-missing-op",
		coverage: ["malformed"],
		params: { task: "first" },
		note: "Targeting args alone are not an unambiguous shape: the schema summary is returned.",
	},
	{
		name: "invalid-args-unknown-op",
		coverage: ["malformed"],
		params: { op: "remove" },
	},
	{
		name: "invalid-args-array",
		coverage: ["malformed"],
		params: ["init"],
	},
	{
		name: "unicode-init",
		coverage: ["nominal", "unicode"],
		params: { op: "init", items: ["日本語のタスク", "emoji 🚀🔥", "ключ", "नमस्ते", "café\u0301"] },
	},
	{
		name: "unicode-unknown-task",
		coverage: ["malformed", "unicode"],
		setup: NOMINAL_SEED,
		params: { op: "done", task: "存在しないタスク" },
	},
	{
		name: "large-payload-bulk-items",
		coverage: ["nominal", "large_payload"],
		params: { op: "init", list: [{ phase: "Bulk", items: LARGE_ITEMS }] },
	},
	{
		name: "session-storage",
		coverage: ["nominal"],
		sessionFile: "session.jsonl",
		params: { op: "init", items: ["persisted"] },
		note: "A session file exists: storage is \"session\" while the file itself stays untouched.",
	},
];


async function recordCases(options: Options, commit: string): Promise<void> {
	const names = CASES.map(spec => spec.name);
	for (const name of options.only) {
		if (!names.includes(name)) throw new Error(`unknown case in --only: ${name}`);
	}
	const selected = options.only.length === 0 ? CASES : CASES.filter(spec => options.only.includes(spec.name));
	const referenceTool = new TodoTool(
		buildSession(options.scratch, null, { phases: [], writes: [] }),
	);
	const failures: string[] = [];
	const recorded: Record<string, Json>[] = [];
	const written = new Set<string>();

	for (const spec of selected) {
		const runs: CaseRun[] = [];
		for (let index = 0; index < options.runs; index++) {
			const base =
				index === 0
					? path.join(options.scratch, spec.name)
					: path.join(options.scratch, ".verify", String(index + 1), spec.name);
			runs.push(await runCase(spec, base));
		}
		const first = runs[0]!;
		const verification = verifyRuns(first, runs.slice(1));
		if (!verification.stable) {
			failures.push(`${spec.name}: ${verification.detail}`);
			console.error(`FAIL ${spec.name}: ${verification.detail}`);
			continue;
		}
		try {
			assertContract(spec, first);
		} catch (error) {
			const detail = `${spec.name}: contract self-check failed: ${error instanceof Error ? error.message : String(error)}`;
			failures.push(detail);
			console.error(`FAIL ${detail}`);
			continue;
		}
		const fixture: Record<string, unknown> = {
			reference: REFERENCE,
			coverage: spec.coverage,
			roots: first.roots,
			workspace: first.initial.workspace,
			session_dir: first.initial.session_dir,
			initial_session: { phases: [] },
			setup_calls: first.setup.map(toFixtureCall),
			...toFixtureCall(first.call),
			effects: first.final,
		};
		if (spec.sessionFile !== undefined) fixture.session_file = spec.sessionFile;
		const directory = path.join(options.out, "todo");
		fs.mkdirSync(directory, { recursive: true });
		const fixturePath = path.join(directory, `${spec.name}.json`);
		fs.writeFileSync(fixturePath, `${JSON.stringify(sortKeys(fixture), null, 2)}\n`);
		written.add(fixturePath);
		console.log(
			`ok   todo/${spec.name} -> ${outcomeLabel(first.call)} (writes ${first.call.session.writes}, ${spec.coverage.join("+")})`,
		);
		recorded.push({
			name: spec.name,
			status: "recorded",
			fixture: path.relative(REPO_ROOT, fixturePath),
			coverage: spec.coverage,
			outcome: outcomeLabel(first.call),
			error: first.call.error,
			setup_calls: first.setup.length,
			session_writes: first.call.session.writes,
			committed_todo_phases: first.call.committed !== null,
			effects: {
				workspace: Object.keys(first.final.workspace),
				session_dir: Object.keys(first.final.session_dir),
			},
			dropped_undefined: first.call.droppedUndefined,
			foreign_absolute_paths: first.foreignPaths,
			note: spec.note ?? null,
		});
	}

	// Existing acceptance evidence is retained even if a recorder case changes.
	const directory = path.join(options.out, "todo");
	if (fs.existsSync(directory)) {
		for (const name of fs.readdirSync(directory)) {
			if (!name.endsWith(".json")) continue;
			const fixturePath = path.join(directory, name);
			if (written.has(fixturePath)) continue;
			console.log(`retained existing fixture ${path.relative(REPO_ROOT, fixturePath)}`);
		}
	}

	const observations = {
		reference: REFERENCE,
		source: { checkout: UPSTREAM, commit, packageVersion: REFERENCE.version, source: REFERENCE_SOURCE },
		invocation: {
			command: `bun scripts/omp-fixtures/todo.ts ${process.argv.slice(2).join(" ")}`.trim(),
			bun: Bun.version,
			runs: options.runs,
			scratch: options.scratch,
			out: options.out,
		},
		tool: {
			name: referenceTool.name,
			label: referenceTool.label,
			summary: referenceTool.summary,
			description: referenceTool.description,
			description_bytes: Buffer.byteLength(referenceTool.description, "utf8"),
			approval: referenceTool.approval,
			concurrency: referenceTool.concurrency,
			strict: referenceTool.strict,
			lenientArgValidation: referenceTool.lenientArgValidation,
			loadMode: referenceTool.loadMode,
			parameters: sortKeys(toolWireSchema(referenceTool)),
		},
		cases: recorded,
		failures,
		notes: [
			"output is the exact JSON form of the SDK AgentToolResult (content/details plus isError when present).",
			"arguments is the JSON form of the arguments validateAgentToolArguments handed to execute; for this lenient tool a schema failure passes the raw arguments through instead of throwing.",
			"initial_session.phases is the memory before setup_calls; replay starts from it and applies setup_calls in order.",
			"error.kind is the thrown Error's name; malformed todo arguments do not throw because TodoTool sets lenientArgValidation — the raw arguments reach execute() and the tool returns its own error result.",
			"setup_calls are real calls on the same session before the recorded one: raw params, the arguments validateAgentToolArguments handed to execute, output/error, the committed phases, and the resulting memory.",
			"session.committed is the exact phases argument of the call's setTodoPhases invocation (null when the call committed nothing); session.writes counts every setTodoPhases call of the whole session.",
			"committed_todo_phases is the real committedTodoPhases(result): null for errors and pure view reads, the committed phases otherwise.",
			"dropped_undefined lists the paths JSON.stringify drops (undefined object members such as blocker after unblock and isError on success).",
			"TodoTool performs no filesystem effect: workspace and session_dir stay empty apart from a case's declared session file, and effects always equals the initial maps.",
			"initialize the replayed session with initial_session.phases, then apply setup_calls in order; a fixture is only written when two runs under different roots agree.",
			`recorder host paths (not peer behaviour): ${JSON.stringify({
				WSL_DISTRO_NAME: process.env.WSL_DISTRO_NAME ?? null,
				platform: process.platform,
			})}`,
		],
	};
	fs.mkdirSync(options.scratch, { recursive: true });
	const observationsPath = path.join(options.scratch, "observations.json");
	fs.writeFileSync(observationsPath, `${JSON.stringify(observations, null, 2)}\n`);
	console.log(`recorded ${recorded.length} fixtures, ${failures.length} failures`);
	console.log(`observations ${observationsPath}`);
	if (failures.length > 0) process.exitCode = 1;
}

async function main(): Promise<void> {
	const options = parseOptions(process.argv.slice(2));
	const commit = assertPinnedSource();
	console.log(`  scratch ${options.scratch}`);
	console.log(`  out ${options.out}`);
	console.log(`  runs per case ${options.runs}`);
	await recordCases(options, commit);
}

await main();
