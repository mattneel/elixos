// OMP 18.10.1's complete TodoTool state machine, unchanged. The build removes
// only the unrelated /todo filesystem-path helper by AST declaration span.
import { TodoTool } from "../../build/upstream/oh-my-pi/packages/coding-agent/src/tools/todo.ts";
import type { Tool, ToolSession } from "../../build/upstream/oh-my-pi/packages/coding-agent/src/tools/index.ts";
import type { TodoPhase } from "../../build/upstream/oh-my-pi/packages/tui/src/tools/todo.ts";

export interface TodoMemoryState {
  phases: TodoPhase[];
}

/** Session-owned callbacks; persistence belongs to the calling lifecycle. */
export function createTodoTool(state: TodoMemoryState, sessionFile: string | null): Tool {
  return new TodoTool({
    getSessionFile: () => sessionFile,
    getTodoPhases: () => state.phases,
    setTodoPhases: phases => { state.phases = phases; },
  } as ToolSession);
}
