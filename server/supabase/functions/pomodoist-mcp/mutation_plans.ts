import { kanbanMutations } from "./kanban_mutations.ts";
import { labelMutations } from "./label_mutations.ts";
import type { DefineMutation, MutationDefinition } from "./mutation_helpers.ts";
import { ActionError } from "./openclaw_actions.ts";
import type { PomodoistMcpAuth } from "./pomodoist_mcp.ts";
import { projectMutations } from "./project_mutations.ts";
import { taskMutations } from "./task_mutations.ts";
import {
  type Context,
  type PomodoistToolDependencies,
  RpcFailure,
  rpcErrorCode,
} from "./tool_core.ts";

export function pomodoistMutationPlans(auth: PomodoistMcpAuth, dependencies: PomodoistToolDependencies): MutationDefinition[] {
  const context: Context = { auth, config: dependencies.config, fetcher: dependencies.fetch ?? fetch,
    log: dependencies.log ?? (() => {}) };
  const definitions: MutationDefinition[] = [];
  const define: DefineMutation = (name, config, build) => {
    definitions.push({ name, config, plan: async arguments_ => {
      try { return await build(config.inputSchema.parse(arguments_)); }
      catch (error) {
        if (error instanceof RpcFailure) throw new ActionError(rpcErrorCode(error.status),
          error.status >= 500 ? "Pomodoist service failed." : "Pomodoist request failed.");
        throw error;
      }
    } });
  };
  const scope = {
    define,
    context,
    annotations: {
      closed: { openWorldHint: false },
      destructive: { destructiveHint: true, openWorldHint: false },
    },
  };
  taskMutations(scope);
  projectMutations(scope);
  labelMutations(scope);
  kanbanMutations(scope);
  return definitions;
}
