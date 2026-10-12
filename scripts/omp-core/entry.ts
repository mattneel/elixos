import "./platform.ts";
import { validateAgentToolArguments } from "../../build/upstream/oh-my-pi/packages/agent/src/tool-arguments.ts";
import { ToolNotFoundError } from "../../build/upstream/oh-my-pi/packages/ai/src/error/validation.ts";
import { toolWireSchema } from "../../build/upstream/oh-my-pi/packages/ai/src/utils/schema/wire.ts";
import { ThinkTool } from "../../build/upstream/oh-my-pi/packages/coding-agent/src/tools/think.ts";
import type { Tool } from "../../build/upstream/oh-my-pi/packages/coding-agent/src/tools/index.ts";
import { createTodoTool } from "./todo.ts";

import type { TodoMemoryState } from "./todo.ts";

const tools: Record<string, Tool | undefined> = { think: new ThinkTool() };

Object.assign(globalThis, {
  __ompCoreInit(sessionFile: string | null) {
    if (tools.todo !== undefined) throw new Error("Tool session already initialized");
    const state: TodoMemoryState = { phases: [] };
    tools.todo = createTodoTool(state, sessionFile);
  },
  __ompCoreDescribe(name: string) {
    if (!Object.hasOwn(tools, name)) throw new ToolNotFoundError(name);
    const tool = tools[name]!;
    return { name: tool.name, description: tool.description, parameters: toolWireSchema(tool) };
  },
  async __ompCoreCall(name: string, params: Record<string, unknown>) {
    try {
      if (!Object.hasOwn(tools, name)) throw new ToolNotFoundError(name);
      const tool = tools[name]!;
      const call = { type: "toolCall" as const, id: "elixos-tool-call", name, arguments: params };
      const arguments_ = validateAgentToolArguments(tool, call);
      return JSON.stringify({ output: await tool.execute(call.id, arguments_) });
    } catch (error) {
      if (!(error instanceof Error)) throw error;
      return JSON.stringify({ error: { kind: error.name, message: error.message } });
    }
  },
});
