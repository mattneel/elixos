#!/usr/bin/env bun
/**
 * M21 differential-fixture recorder (ADR-047).
 *
 * Runs the *real* pinned OMP SDK tool factories against isolated workspace and
 * session roots and records each result verbatim into the fixture contract
 * consumed by `os/test/elixos/toolset_differential_test.exs`:
 *
 *   reference      package/version/integrity of the pinned SDK
 *   coverage       nominal | unicode | malformed | numeric_boundaries | large_payload
 *   params         the raw arguments handed to the SDK validation path
 *   roots          the two distinct absolute recording roots
 *   workspace      initial workspace file map (literal bytes / {"base64": ...})
 *   session_dir    initial session file map
 *   output         the exact JSON form of the AgentToolResult, or
 *   error          {"kind": <Error name>, "message": <Error message>}
 *   effects        complete post-call workspace/session file maps
 *
 * A call goes through the same public path the agent loop uses:
 * `validateAgentToolArguments(tool, call)` (the SDK argument-validation path)
 * followed by `tool.execute(callId, validatedArgs)`. Nothing is synthesized:
 * a fixture is only written when two independent recording runs under
 * different absolute roots produce the identical outcome and identical file
 * effects after the recorded roots are rebound, and a contract self-check
 * (the same rules the replay driver asserts) passes.
 *
 * Run from the repository root:
 *
 *   bun scripts/record-omp-fixtures.ts                    # all first-slice tools
 *   bun scripts/record-omp-fixtures.ts --only read,glob    # subset
 *   bun scripts/record-omp-fixtures.ts --runs 3            # extra stability runs
 *
 * Options: --only <csv> --runs <n> --scratch <dir> --fixtures <dir> --help
 *
 * The pinned upstream checkout is read-only reference input; this recorder
 * writes only fixture JSON under os/test/fixtures/omp/<tool>/ and scratch
 * state under <scratch> (default build/omp-fixture-record, gitignored).
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

import { validateAgentToolArguments } from "../build/upstream/oh-my-pi/packages/agent/src/tool-arguments";
import { toolWireSchema } from "../build/upstream/oh-my-pi/packages/ai/src/utils/schema/wire";
import { Settings } from "../build/upstream/oh-my-pi/packages/coding-agent/src/config/settings";
import { GlobTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/tools/glob";
import { GrepTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/tools/grep";
import { ReadTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/tools/read";
import { ThinkTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/tools/think";
import { WriteTool } from "../build/upstream/oh-my-pi/packages/coding-agent/src/tools/write";
import type { Tool, ToolSession } from "../build/upstream/oh-my-pi/packages/coding-agent/src/tools/index";
import { isRecord } from "../build/upstream/oh-my-pi/packages/utils/src/type-guards";

const REPO_ROOT = path.resolve(import.meta.dir, "..");
const UPSTREAM = path.join(REPO_ROOT, "build", "upstream", "oh-my-pi");
const CODING_AGENT_PACKAGE_JSON = path.join(UPSTREAM, "packages", "coding-agent", "package.json");

/**
 * The pin recorded into every fixture's `reference`. The version is asserted
 * against the prepared checkout's package.json and the commit against the
 * checkout's HEAD below; the integrity is the public npm pin for 18.10.1.
 */
const REFERENCE = {
	package: "@oh-my-pi/pi-coding-agent",
	version: "18.10.1",
	integrity:
		"sha512-xvHDKLcAsGvDwLQG6PHZEYiELQPKJ4NiSc/yeurja8IZkC7yALjR+2pbEiCT4cSdyIfEmHFDhDUze8hSxYpiZA==",
};
const EXPECTED_COMMIT = "90701813e5fba6919067848989378b4ee6239c13";
const REFERENCE_SOURCE = "https://github.com/can1357/oh-my-pi (packages/coding-agent)";

const COVERAGE_CATEGORIES: Record<string, true> = {
	nominal: true,
	unicode: true,
	malformed: true,
	numeric_boundaries: true,
	large_payload: true,
};
const LARGE_PAYLOAD_BYTES = 65_536;
const CALL_ID = "fixture-call";

type ToolName = "read" | "write" | "glob" | "grep" | "think";
const TOOL_NAMES: ToolName[] = ["read", "write", "glob", "grep", "think"];

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type FileMap = Record<string, string | { base64: string }>;
type ReaderOutcome = { output: Json } | { error: { kind: string; message: string } };

interface NumericBoundary {
	path: string[];
	limit: number;
	relation: "below" | "at" | "above";
}

interface CaseSpec {
	tool: ToolName;
	name: string;
	coverage: string[];
	params: Record<string, Json>;
	numericBoundary?: NumericBoundary;
	files?: FileMap;
	sessionFiles?: FileMap;
	fileTimes?: { workspace?: Record<string, number>; session_dir?: Record<string, number> };
	/** A string that must NOT appear anywhere in the recorded outcome. */
	privacyProbe?: string;
	/** Free-form note stored in the observations sidecar. */
	note?: string;
}

interface CaseRun {
	roots: { workspace: string; session_dir: string };
	initial: { workspace: FileMap; session_dir: FileMap };
	outcome: ReaderOutcome;
	final: { workspace: FileMap; session_dir: FileMap };
	droppedUndefined: string[];
	foreignPaths: string[];
}

// ─────────────────────────────────────────────────────────────────────────────
// CLI

interface Options {
	only: ToolName[];
	runs: number;
	scratch: string;
	fixtures: string;
}

function parseOptions(argv: string[]): Options {
	if (argv.includes("--help") || argv.includes("-h")) {
		console.log(
			[
				"bun scripts/record-omp-fixtures.ts [--only read,write,glob,grep,think] [--runs n]",
				"                                    [--scratch dir] [--fixtures dir]",
				"",
				"Records real pinned-SDK tool outcomes into os/test/fixtures/omp/<tool>/*.json.",
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
	const onlyRaw = value("--only");
	const only = onlyRaw === undefined ? TOOL_NAMES : onlyRaw.split(",").map(part => part.trim()).filter(Boolean);
	for (const tool of only) {
		if (!TOOL_NAMES.includes(tool as ToolName)) throw new Error(`unknown tool in --only: ${tool}`);
	}
	const runsRaw = value("--runs");
	const runs = runsRaw === undefined ? 2 : Number(runsRaw);
	if (!Number.isInteger(runs) || runs < 2) throw new Error("--runs must be an integer >= 2");
	return {
		only: only as ToolName[],
		runs,
		scratch: value("--scratch") ?? path.join(REPO_ROOT, "build", "omp-fixture-record"),
		fixtures: value("--fixtures") ?? path.join(REPO_ROOT, "os", "test", "fixtures", "omp"),
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
// Session, tools, files

/**
 * The minimally configured ToolSession the upstream test utilities use, with
 * the unrelated LSP integration explicitly off (a supported session field).
 * `getSessionFile` is null: these slices persist no session state, so the
 * session root stays untouched unless the tool itself writes there.
 */
function buildSession(workspace: string): ToolSession {
	return {
		cwd: workspace,
		hasUI: false,
		enableLsp: false,
		getSessionFile: () => null,
		getSessionSpawns: () => "*",
		settings: Settings.isolated({}),
	};
}

function buildTool(tool: ToolName, session: ToolSession): Tool {
	switch (tool) {
		case "read":
			return new ReadTool(session);
		case "write":
			return new WriteTool(session);
		case "glob":
			return new GlobTool(session, { rootPathAlias: true });
		case "grep":
			return new GrepTool(session);
		case "think":
			return new ThinkTool();
	}
}

function restoreFiles(root: string, files: FileMap): void {
	fs.mkdirSync(root, { recursive: true });
	// Byte-wise key order, matching Erlang term order for the replay driver's
	// decoded file maps (and therefore its restore order).
	const relativePaths = Object.keys(files).sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
	for (const relative of relativePaths) {
		const entry = files[relative];
		const bytes = typeof entry === "string" ? Buffer.from(entry, "utf8") : Buffer.from(entry.base64, "base64");
		const destination = path.join(root, ...relative.split("/"));
		fs.mkdirSync(path.dirname(destination), { recursive: true });
		fs.writeFileSync(destination, bytes);
	}
}

function restoreTimes(root: string, files: FileMap, times: Record<string, number> = {}): void {
	for (const [relative, seconds] of Object.entries(times)) {
		if (!Object.hasOwn(files, relative) || !Number.isSafeInteger(seconds)) {
			throw new Error(`mtime must identify an initial file and whole POSIX seconds: ${relative}`);
		}
		fs.utimesSync(path.join(root, ...relative.split("/")), seconds, seconds);
	}
}

function snapshotFiles(root: string): FileMap {
	const files: FileMap = {};
	const walk = (directory: string): void => {
		const entries = fs
			.readdirSync(directory, { withFileTypes: true })
			.sort((a, b) => (a.name < b.name ? -1 : 1));
		for (const entry of entries) {
			const full = path.join(directory, entry.name);
			const stat = fs.lstatSync(full);
			if (stat.isDirectory()) {
				walk(full);
				continue;
			}
			if (!stat.isFile()) throw new Error(`recorder cannot record non-regular entry at ${full}`);
			const relative = path.relative(root, full).split(path.sep).join("/");
			const bytes = fs.readFileSync(full);
			const text = bytes.toString("utf8");
			files[relative] = bytes.equals(Buffer.from(text, "utf8")) ? text : { base64: bytes.toString("base64") };
		}
	};
	walk(root);
	return files;
}

// ─────────────────────────────────────────────────────────────────────────────
// Call, JSON form, comparisons

/**
 * JSON.stringify's exact JSON form of the raw result. Fields JSON cannot
 * represent (undefined object members) are dropped by the runtime, so their
 * paths are collected and reported in the observations sidecar instead of
 * being silently normalized. Anything else non-JSON fails loudly.
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
	if (Array.isArray(value)) {
		return value.map((item, index) => toJsonForm(item, `${where}[${index}]`, dropped));
	}
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

async function callTool(tool: Tool, params: Record<string, unknown>): Promise<CaseRun["outcome"] & { dropped: string[] }> {
	const dropped: string[] = [];
	try {
		const validated = validateAgentToolArguments(tool, {
			type: "toolCall",
			id: CALL_ID,
			name: tool.name,
			arguments: params,
		});
		const raw: unknown = await tool.execute(CALL_ID, validated);
		return { output: toJsonForm(raw, "output", dropped), dropped };
	} catch (error) {
		const kind = error instanceof Error && error.name.length > 0 ? error.name : "Error";
		const message = error instanceof Error ? error.message : String(error);
		return { error: { kind, message }, dropped };
	}
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
	for (const [key, item] of Object.entries(value)) {
		converted[rebind(key, bindings) as string] = rebind(item, bindings);
	}
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

/** Absolute-looking paths in the outcome that no recorded root rebinds. */
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

async function runCase(spec: CaseSpec, base: string): Promise<CaseRun> {
	fs.rmSync(base, { recursive: true, force: true });
	const workspace = path.join(base, "workspace");
	const sessionDir = path.join(base, "session");
	restoreFiles(workspace, spec.files ?? {});
	restoreFiles(sessionDir, spec.sessionFiles ?? {});
	restoreTimes(workspace, spec.files ?? {}, spec.fileTimes?.workspace);
	restoreTimes(sessionDir, spec.sessionFiles ?? {}, spec.fileTimes?.session_dir);
	const initial = { workspace: snapshotFiles(workspace), session_dir: snapshotFiles(sessionDir) };
	const tool = buildTool(spec.tool, buildSession(workspace));
	const outcome = await callTool(tool, spec.params);
	const final = { workspace: snapshotFiles(workspace), session_dir: snapshotFiles(sessionDir) };
	const { dropped, ...recorded } = outcome;
	return {
		roots: { workspace, session_dir: sessionDir },
		initial,
		outcome: recorded,
		final,
		droppedUndefined: dropped,
		foreignPaths: "output" in recorded ? foreignAbsolutePaths(recorded.output, [workspace, sessionDir]) : [],
	};
}

interface Verification {
	stable: boolean;
	detail: string;
}

function verifyRuns(first: CaseRun, others: CaseRun[]): Verification {
	for (const [index, other] of others.entries()) {
		const bindings: [string, string][] = [
			[first.roots.workspace, other.roots.workspace],
			[first.roots.session_dir, other.roots.session_dir],
		];
		const expectedInitial = {
			workspace: rebind(first.initial.workspace, bindings),
			session_dir: rebind(first.initial.session_dir, bindings),
		};
		const expectedOutcome = rebind(first.outcome, bindings);
		const expectedFinal = {
			workspace: rebind(first.final.workspace, bindings),
			session_dir: rebind(first.final.session_dir, bindings),
		};
		if (canonical(expectedInitial) !== canonical(other.initial)) {
			return { stable: false, detail: `run ${index + 2} initial file maps differ from run 1` };
		}
		if (canonical(expectedOutcome) !== canonical(other.outcome)) {
			return {
				stable: false,
				detail: `run ${index + 2} outcome differs: ${canonical(expectedOutcome)} != ${canonical(other.outcome)}`,
			};
		}
		if (canonical(expectedFinal) !== canonical(other.final)) {
			return { stable: false, detail: `run ${index + 2} file effects differ from run 1` };
		}
	}
	return { stable: true, detail: `${others.length + 1} runs agree` };
}

// ─────────────────────────────────────────────────────────────────────────────
// Contract self-check (mirrors os/test/elixos/toolset_differential_test.exs)

/** Mirrors the replay driver's input_strings/1: bytes for {"base64": ...}, text otherwise. */
function inputStrings(value: Json | string | Buffer): (string | Buffer)[] {
	if (typeof value === "string") return [value];
	if (Buffer.isBuffer(value)) return [value];
	if (isRecord(value) && typeof value.base64 === "string") return [Buffer.from(value.base64, "base64")];
	if (Array.isArray(value)) return value.flatMap(item => inputStrings(item));
	if (value === null || typeof value !== "object") return [];
	return Object.entries(value).flatMap(([key, item]) => [...inputStrings(key), ...inputStrings(item)]);
}

function assertContract(spec: CaseSpec, run: CaseRun): void {
	const outcomeKeys = ["output", "error"].filter(key => key in run.outcome);
	if (outcomeKeys.length !== 1) throw new Error("fixture needs exactly one output or error");
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
	if (spec.coverage.includes("nominal") && !("output" in run.outcome)) {
		throw new Error("nominal coverage needs an output");
	}
	if (spec.coverage.includes("malformed") && !("error" in run.outcome)) {
		throw new Error("malformed coverage needs an error");
	}
	const inputs: Json[] = [spec.params, run.initial.workspace, run.initial.session_dir];
	const strings = inputStrings(inputs);
	if (spec.coverage.includes("unicode")) {
		const ok = strings.some(value => {
			const text = typeof value === "string" ? value : Buffer.from(value).toString("utf8");
			const validUtf8 = typeof value === "string" || Buffer.from(text, "utf8").equals(value);
			return validUtf8 && /[^\x00-\x7F]/.test(text);
		});
		if (!ok) throw new Error("unicode coverage needs a non-ASCII input");
	}
	if (spec.coverage.includes("large_payload")) {
		const ok = strings.some(
			value => (typeof value === "string" ? Buffer.byteLength(value, "utf8") : value.length) >= LARGE_PAYLOAD_BYTES,
		);
		if (!ok) throw new Error(`large_payload coverage needs >= ${LARGE_PAYLOAD_BYTES} input bytes`);
	}
	if (spec.coverage.includes("numeric_boundaries")) {
		const boundary = spec.numericBoundary;
		if (!boundary || boundary.path.length === 0 || !Number.isFinite(boundary.limit)) {
			throw new Error("numeric_boundaries coverage needs a boundary {path, limit, relation}");
		}
		let value: unknown = spec.params;
		for (const key of boundary.path) {
			value = isRecord(value) ? value[key] : undefined;
		}
		if (typeof value !== "number") throw new Error("numeric boundary path does not resolve to a number");
		const ok =
			boundary.relation === "below"
				? value < boundary.limit
				: boundary.relation === "at"
					? value === boundary.limit
					: value > boundary.limit;
		if (!ok) throw new Error(`numeric boundary ${boundary.relation} not satisfied by ${value} vs ${boundary.limit}`);
	}
	if (spec.privacyProbe !== undefined && JSON.stringify(run.outcome).includes(spec.privacyProbe)) {
		throw new Error("privacy probe leaked into the outcome");
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// The recorded cases

function buildLargeText(totalBytes: number): string {
	const line = `${"0123456789abcdef".repeat(3)}\n`;
	const lines: string[] = [];
	let size = 0;
	while (size + line.length <= totalBytes) {
		lines.push(line);
		size += line.length;
	}
	if (size < totalBytes) lines.push(`${"z".repeat(totalBytes - size - 1)}\n`);
	const text = lines.join("");
	if (Buffer.byteLength(text, "utf8") !== totalBytes) throw new Error("large text size mismatch");
	return text;
}

const LARGE_TEXT = buildLargeText(LARGE_PAYLOAD_BYTES);
const GLOB_RANK_FILES: FileMap = {
	"alpha/older.txt": "older\n",
	"alpha/newest.txt": "newest\n",
	"beta/middle.txt": "middle\n",
};
const GLOB_RANK_TIMES = {
	"alpha/older.txt": 1_710_000_000,
	"alpha/newest.txt": 1_710_000_120,
	"beta/middle.txt": 1_710_000_060,
};
const GLOB_CAP_FILES: FileMap = {};
const GLOB_CAP_TIMES: Record<string, number> = {};
for (let index = 0; index < 205; index++) {
	const name = `docs/item-${String(index).padStart(3, "0")}.txt`;
	GLOB_CAP_FILES[name] = `${index}\n`;
	GLOB_CAP_TIMES[name] = 1_710_000_000 + index * 60;
}

const CASES: CaseSpec[] = [
	// read ────────────────────────────────────────────────────────────────────
	{
		tool: "read",
		name: "nominal-lines",
		coverage: ["nominal"],
		files: { "notes/greeting.txt": "hello world\nsecond line\nthird line\n" },
		params: { path: "notes/greeting.txt" },
	},
	{
		tool: "read",
		name: "line-selector",
		coverage: ["nominal"],
		files: { "notes/greeting.txt": "hello world\nsecond line\nthird line\n" },
		params: { path: "notes/greeting.txt:2-3" },
	},
	{
		tool: "read",
		name: "unicode-content",
		coverage: ["nominal", "unicode"],
		files: { "notes/日本語.txt": "héllo wörld\n日本語テスト\nemoji: 🚀\n" },
		params: { path: "notes/日本語.txt" },
	},
	{
		tool: "read",
		name: "large-file",
		coverage: ["nominal", "large_payload"],
		files: { "logs/payload.txt": LARGE_TEXT },
		params: { path: "logs/payload.txt" },
	},
	{
		tool: "read",
		name: "missing-file",
		coverage: ["malformed"],
		params: { path: "missing/not-there.txt" },
	},
	{
		tool: "read",
		name: "invalid-params",
		coverage: ["malformed"],
		params: {},
		note: "SDK argument validation rejects the missing required path.",
	},

	// write ───────────────────────────────────────────────────────────────────
	{
		tool: "write",
		name: "new-file",
		coverage: ["nominal"],
		params: { path: "src/app.txt", content: "first line\nsecond line\n" },
	},
	{
		tool: "write",
		name: "overwrite-file",
		coverage: ["nominal"],
		files: { "docs/readme.md": "# old title\ntext\n" },
		params: { path: "docs/readme.md", content: "# new title\nbody\n" },
	},
	{
		tool: "write",
		name: "unicode-content",
		coverage: ["nominal", "unicode"],
		params: { path: "docs/日本語.md", content: "你好，世界\n🚀 launch\n" },
	},
	{
		tool: "write",
		name: "large-content",
		coverage: ["nominal", "large_payload"],
		params: { path: "data/large.txt", content: LARGE_TEXT },
	},
	{
		tool: "write",
		name: "missing-content",
		coverage: ["malformed"],
		params: { path: "notes/new.txt" },
	},

	// glob ────────────────────────────────────────────────────────────────────
	// Mtimes are explicit inputs (ADR-073), so multi-match ranking and true
	// result-limit behavior remain reproducible without normalizing outputs.
	{
		tool: "glob",
		name: "grouped-newest-first",
		coverage: ["nominal"],
		files: GLOB_RANK_FILES,
		fileTimes: { workspace: GLOB_RANK_TIMES },
		params: { path: "**/*.txt" },
	},
	{
		tool: "glob",
		name: "single-match",
		coverage: ["nominal"],
		files: { "src/main.ts": "export const x = 1;\n", "docs/guide.md": "# Guide\n" },
		params: { path: "**/*.ts" },
	},
	{
		tool: "glob",
		name: "no-match",
		coverage: ["nominal"],
		files: { "alpha/one.txt": "one\n" },
		params: { path: "**/*.rs" },
	},
	{
		tool: "glob",
		name: "limit-below-cap",
		coverage: ["nominal", "numeric_boundaries"],
		numericBoundary: { path: ["limit"], limit: 200, relation: "below" },
		files: GLOB_RANK_FILES,
		fileTimes: { workspace: GLOB_RANK_TIMES },
		params: { path: "**/*.txt", limit: 2 },
	},
	{
		tool: "glob",
		name: "limit-at-cap",
		coverage: ["nominal", "numeric_boundaries"],
		numericBoundary: { path: ["limit"], limit: 200, relation: "at" },
		files: GLOB_CAP_FILES,
		fileTimes: { workspace: GLOB_CAP_TIMES },
		params: { path: "**/*.txt", limit: 200 },
	},
	{
		tool: "glob",
		name: "limit-above-cap",
		coverage: ["nominal", "numeric_boundaries"],
		numericBoundary: { path: ["limit"], limit: 200, relation: "above" },
		files: GLOB_CAP_FILES,
		fileTimes: { workspace: GLOB_CAP_TIMES },
		params: { path: "**/*.txt", limit: 201 },
	},
	{
		tool: "glob",
		name: "hidden-included",
		coverage: ["nominal"],
		files: { ".config/app.json": "{}\n", "src/main.ts": "export {};\n" },
		params: { path: "**/*.json" },
		note: "hidden defaults to true, so the dot-directory match is returned.",
	},
	{
		tool: "glob",
		name: "hidden-excluded",
		coverage: ["nominal"],
		files: { ".secret.txt": "s\n", "visible.txt": "v\n" },
		params: { path: "*.txt", hidden: false },
	},
	{
		tool: "glob",
		name: "gitignore-exclusion",
		coverage: ["nominal"],
		files: {
			".gitignore": "ignored.txt\n",
			"ignored.txt": "secret\n",
			"visible.txt": "ok\n",
		},
		params: { path: "*.txt" },
	},
	{
		tool: "glob",
		name: "missing-path",
		coverage: ["malformed"],
		params: { path: "missing/*.ts" },
	},
	{
		tool: "glob",
		name: "invalid-params",
		coverage: ["malformed"],
		params: { path: "*.txt", limit: "many" },
		note: "SDK argument validation rejects the non-numeric limit.",
	},

	// grep ────────────────────────────────────────────────────────────────────
	{
		tool: "grep",
		name: "multi-file-matches",
		coverage: ["nominal"],
		files: { "lib/a.js": "const alpha = 1;\n", "lib/b.js": "let beta = 2;\nconst alpha = 3;\n" },
		params: { pattern: "alpha" },
	},
	{
		tool: "grep",
		name: "case-insensitive",
		coverage: ["nominal"],
		files: { "lib/a.js": "const alpha = 1;\nconst BETA = 2;\n" },
		params: { pattern: "beta", case: false },
	},
	{
		tool: "grep",
		name: "no-match",
		coverage: ["nominal"],
		files: { "lib/a.js": "const alpha = 1;\n" },
		params: { pattern: "zzz-absent" },
	},
	{
		tool: "grep",
		name: "unicode-pattern",
		coverage: ["nominal", "unicode"],
		files: { "i18n/ja.txt": "日本語テスト\nカタカナ\n" },
		params: { pattern: "日本語" },
	},
	{
		tool: "grep",
		name: "single-file-scope",
		coverage: ["nominal"],
		files: { "lib/a.js": "const alpha = 1;\nconst alpha2 = 2;\n", "lib/b.js": "const alpha = 3;\n" },
		params: { pattern: "alpha", path: "lib/a.js" },
	},
	{
		tool: "grep",
		name: "skip-page-boundary",
		coverage: ["nominal", "numeric_boundaries"],
		numericBoundary: { path: ["skip"], limit: 2, relation: "at" },
		files: { "lib/a.js": "const alpha = 1;\n", "lib/b.js": "const alpha = 2;\n" },
		params: { pattern: "alpha", skip: 2 },
		note: "skip equals the number of matching files: exactly one page past the end.",
	},
	{
		tool: "grep",
		name: "blank-pattern",
		coverage: ["malformed"],
		files: { "lib/a.js": "const alpha = 1;\n" },
		params: { pattern: "   " },
	},
	{
		tool: "grep",
		name: "missing-path",
		coverage: ["malformed"],
		params: { pattern: "alpha", path: "missing/file.txt" },
	},

	// think ───────────────────────────────────────────────────────────────────
	{
		tool: "think",
		name: "scratchpad",
		coverage: ["nominal"],
		params: { thoughts: "private plan: probe the pinned SDK and record raw outcomes (zZ-secret-9f3a)" },
		privacyProbe: "zZ-secret-9f3a",
		note: "Scratchpad privacy: the private thought text never appears in the result.",
	},
	{
		tool: "think",
		name: "unicode-scratchpad",
		coverage: ["nominal", "unicode"],
		params: { thoughts: "検討中: 数値の境界と 🚀 を確認する" },
	},
	{
		tool: "think",
		name: "invalid-params",
		coverage: ["malformed"],
		params: {},
	},
];

// ─────────────────────────────────────────────────────────────────────────────
// Report and main

interface Observations {
	reference: typeof REFERENCE;
	source: { checkout: string; commit: string; packageVersion: string; source: string };
	invocation: { command: string; bun: string; runs: number; scratch: string };
	toolSchemas: Record<string, unknown>;
	cases: Record<string, Json>[];
	failures: string[];
	retained: string[];
	notes: string[];
}

function outcomeLabel(outcome: ReaderOutcome): string {
	return "output" in outcome ? "output" : `error:${outcome.error.kind}`;
}

async function main(): Promise<void> {
	const options = parseOptions(process.argv.slice(2));
	const commit = assertPinnedSource();
	console.log(`  scratch ${options.scratch}`);
	console.log(`  fixtures ${options.fixtures}`);
	console.log(`  runs per case ${options.runs}`);

	const observations: Observations = {
		reference: REFERENCE,
		source: { checkout: UPSTREAM, commit, packageVersion: REFERENCE.version, source: REFERENCE_SOURCE },
		invocation: {
			command: `bun scripts/record-omp-fixtures.ts ${process.argv.slice(2).join(" ")}`.trim(),
			bun: Bun.version,
			runs: options.runs,
			scratch: options.scratch,
		},
		toolSchemas: {},
		cases: [],
		failures: [],
		retained: [],
		notes: [
			"output is the exact JSON form of the SDK AgentToolResult (content/details plus isError/useless when present).",
			"error.kind is the thrown Error's name (ToolError, ValidationError, ...); error.message is its message.",
			"glob ranks matches by mtime; multi-match and capped cases restore explicit initial file_times without normalizing output.",
			"think takes no session (HIDDEN_TOOLS.think); accepted scratchpad text is never echoed in its success result.",
		],
	};

	for (const tool of options.only) {
		observations.toolSchemas[tool] = sortKeys(toolWireSchema(buildTool(tool, buildSession(options.scratch))));
	}

	let recorded = 0;
	let failed = 0;
	// Existing fixtures not produced by this invocation remain acceptance
	// evidence. Removing a recorder case must never silently remove its test.
	const writtenFixtures = new Set<string>();
	for (const spec of CASES) {
		if (!options.only.includes(spec.tool)) continue;
		const caseDir = path.join(options.scratch, spec.tool, spec.name);
		const runs: CaseRun[] = [];
		for (let index = 0; index < options.runs; index++) {
			const base =
				index === 0 ? caseDir : path.join(options.scratch, ".verify", String(index + 1), spec.tool, spec.name);
			runs.push(await runCase(spec, base));
		}
		const first = runs[0];
		const verification = verifyRuns(first, runs.slice(1));
		const label = `${spec.tool}/${spec.name}`;
		if (!verification.stable) {
			failed++;
			const detail = `${label}: ${verification.detail}`;
			observations.failures.push(detail);
			console.error(`FAIL ${detail}`);
			observations.cases.push({
				tool: spec.tool,
				name: spec.name,
				status: "unstable",
				detail: verification.detail,
				outcome: outcomeLabel(first.outcome),
			});
			continue;
		}
		try {
			assertContract(spec, first);
		} catch (error) {
			failed++;
			const detail = `${label}: contract self-check failed: ${error instanceof Error ? error.message : String(error)}`;
			observations.failures.push(detail);
			console.error(`FAIL ${detail}`);
			observations.cases.push({ tool: spec.tool, name: spec.name, status: "contract-failed" });
			continue;
		}
		const fixture: Record<string, unknown> = {
			reference: REFERENCE,
			coverage: spec.coverage,
			params: spec.params,
			roots: first.roots,
			workspace: first.initial.workspace,
			session_dir: first.initial.session_dir,
			effects: first.final,
		};
		if (spec.numericBoundary) fixture.numeric_boundary = spec.numericBoundary;
		if (spec.fileTimes) fixture.file_times = spec.fileTimes;
		if ("output" in first.outcome) fixture.output = first.outcome.output;
		else fixture.error = first.outcome.error;
		const fixtureDirectory = path.join(options.fixtures, spec.tool);
		fs.mkdirSync(fixtureDirectory, { recursive: true });
		const fixturePath = path.join(fixtureDirectory, `${spec.name}.json`);
		fs.writeFileSync(fixturePath, `${JSON.stringify(sortKeys(fixture), null, 2)}\n`);
		writtenFixtures.add(fixturePath);
		recorded++;
		console.log(
			`ok   ${label} -> ${outcomeLabel(first.outcome)} (${Object.keys(first.final.workspace).length} workspace files, ${spec.coverage.join("+")})`,
		);
		observations.cases.push({
			tool: spec.tool,
			name: spec.name,
			status: "recorded",
			fixture: path.relative(REPO_ROOT, fixturePath),
			coverage: spec.coverage,
			outcome: outcomeLabel(first.outcome),
			error: "error" in first.outcome ? first.outcome.error : null,
			roots: first.roots,
			effects: {
				workspace: Object.keys(first.final.workspace),
				session_dir: Object.keys(first.final.session_dir),
			},
			dropped_undefined: first.droppedUndefined,
			foreign_absolute_paths: first.foreignPaths,
			note: spec.note ?? null,
		});
	}

	for (const tool of options.only) {
		const directory = path.join(options.fixtures, tool);
		if (!fs.existsSync(directory)) continue;
		for (const name of fs.readdirSync(directory)) {
			if (!name.endsWith(".json")) continue;
			const fixturePath = path.join(directory, name);
			if (writtenFixtures.has(fixturePath)) continue;
			const relative = path.relative(REPO_ROOT, fixturePath);
			observations.retained.push(relative);
			console.log(`retained existing fixture ${relative}`);
		}
	}

	fs.mkdirSync(options.scratch, { recursive: true });
	const observationsPath = path.join(options.scratch, "observations.json");
	fs.writeFileSync(observationsPath, `${JSON.stringify(observations, null, 2)}\n`);

	const upstreamStatus = spawnSync("git", ["-C", UPSTREAM, "status", "--porcelain"], { encoding: "utf8" });
	if (upstreamStatus.status === 0 && upstreamStatus.stdout.trim() !== "") {
		console.log("note upstream checkout has local changes (left untouched by this recorder):");
		console.log(upstreamStatus.stdout.trim());
	}

	console.log(`recorded ${recorded} fixtures, ${failed} failures`);
	console.log(`observations ${observationsPath}`);
	if (failed > 0) process.exitCode = 1;
}

await main();
