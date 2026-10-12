#!/usr/bin/env bun
import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import * as path from "node:path";
import type { BunPlugin } from "bun";

const root = path.resolve(import.meta.dir, "..");
const upstream = path.join(root, "build/upstream/oh-my-pi");
const packages = path.join(upstream, "packages");
const expectedCommit = "90701813e5fba6919067848989378b4ee6239c13";
const expectedVersion = "18.10.1";
const commit = spawnSync("git", ["-C", upstream, "rev-parse", "HEAD"], { encoding: "utf8" });
if (commit.status !== 0 || commit.stdout.trim() !== expectedCommit) {
  throw new Error(`OMP core requires the pinned checkout ${expectedCommit}`);
}
const codingAgent = await Bun.file(path.join(packages, "coding-agent/package.json")).json();
if (codingAgent.version !== expectedVersion) throw new Error("OMP core package version differs from the recorded pin");
const standardLibraryRoot = path.join(root, "build/upstream/native-runtime/node_modules/core-js-pure");
const standardLibrary = await Bun.file(path.join(standardLibraryRoot, "package.json")).json();
if (standardLibrary.version !== "3.50.0") throw new Error("OMP core requires core-js-pure 3.50.0");

// Import the exact implementations, not the public barrels that also initialize
// provider clients, log files, process helpers, SQLite and Bun FFI.
const aliases: Record<string, string> = {
  "@oh-my-pi/pi-ai": path.join(packages, "ai/src/utils/validation.ts"),
  "@oh-my-pi/omptype": path.join(packages, "omptype/src/index.ts"),
  "@oh-my-pi/pi-utils": path.join(root, "scripts/omp-core/pure-utils.ts"),
};
const extractions: Record<string, { upstream_sha256: string; excluded: string[] }> = {};
const pureImports: BunPlugin = {
  name: "elixos-omp-pure-exports",
  setup(build) {
    build.onResolve({ filter: /^@oh-my-pi\/(pi-ai|omptype|pi-utils)$/ }, args => ({ path: aliases[args.path] }));
    build.onResolve({ filter: /^\.\.\/error$/ }, args => {
      if (args.importer === path.join(packages, "ai/src/utils/validation.ts")) {
        return { path: path.join(packages, "ai/src/error/validation.ts") };
      }
    });
    build.onLoad({ filter: /\/coding-agent\/src\/tools\/todo\.ts$/ }, args => {
      const extracted = spawnSync("mix", ["run", "--no-compile", path.join(root, "scripts/extract-omp-todo.exs"), args.path], {
        cwd: path.join(root, "os"),
        encoding: "utf8",
      });
      if (extracted.status !== 0) throw new Error(`Todo pure extraction failed: ${extracted.stderr}`);
      const { source, ...provenance } = JSON.parse(extracted.stdout);
      extractions["packages/coding-agent/src/tools/todo.ts"] = provenance;
      return { contents: source, loader: "ts", resolveDir: path.dirname(args.path) };
    });
  },
};
const result = await Bun.build({
  entrypoints: [path.join(root, "scripts/omp-core/entry.ts")],
  target: "browser",
  format: "iife",
  plugins: [pureImports],
});
if (!result.success) {
  for (const diagnostic of result.logs) console.error(diagnostic);
  process.exit(1);
}
const destination = path.join(root, "os/priv/toolset");
mkdirSync(destination, { recursive: true });
const code = await result.outputs[0].text();
const digest = new Bun.CryptoHasher("sha256").update(code).digest("hex");
await Bun.write(path.join(destination, "core.js"), code);
await Bun.write(path.join(destination, "core-source.json"), `${JSON.stringify({
  repository: "https://github.com/can1357/oh-my-pi.git",
  revision: expectedCommit,
  version: expectedVersion,
  sha256: digest,
  standard_library: { name: "core-js-pure", version: "3.50.0", integrity: "sha512-6GP3Pxz4IKyWjAfa747vIu/jilB5z29JWROLqH/b+pXVcpgh6tM06ZIBwSuglgVqzDYURhOK6oEzTrG0bCHitA==" },
  quickbeam: "0.11.3",
  source_extractions: extractions,
}, null, 2)}\n`);
const licenses: Array<[string, string]> = [
  ["Oh-My-Pi", path.join(upstream, "LICENSE")],
  ["omptype", path.join(packages, "omptype/LICENSE")],
  ["QuickBEAM", path.join(root, "os/deps/quickbeam/LICENSE")],
  ["core-js-pure", path.join(standardLibraryRoot, "LICENSE")],
];
const notices: string[] = [];
for (const [name, file] of licenses) notices.push(`${name}\n${await Bun.file(file).text()}`);
await Bun.write(path.join(destination, "THIRD-PARTY-NOTICES"), notices.join("\n\n"));
console.log(`OMP_CORE: ${Buffer.byteLength(code)} bytes; sha256=${digest}; reference=${expectedCommit}`);
