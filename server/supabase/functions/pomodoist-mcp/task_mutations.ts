import { z } from "zod";
import {
  MutationScope,
  assignment,
  completeOperations,
  deleteTaskOperations,
  descendants,
  dueJson,
  labelAdditions,
  mutationPlan,
  mutationSnapshot,
  requireProject,
  requireTask,
  restoreOperations,
  sanitizeTask,
  taskAction,
  upsert,
  validateParent,
} from "./mutation_helpers.ts";
import {
  ToolFailure,
  backlogId,
  createTaskSchema,
  entityId,
  inboxId,
  localUserId,
  nullableString,
  orderKey,
  outputSchemas,
  string,
  updateTaskSchema,
} from "./tool_core.ts";

export function taskMutations({ define, context, annotations }: MutationScope) {
  define(
    "create_task",
    {
      inputSchema: createTaskSchema,
      outputSchema: outputSchemas.mutation,
      annotations: annotations.closed,
    },
    async (arguments_) => {
      const snapshot = await mutationSnapshot(context);
      const now = new Date().toISOString();
      const id = crypto.randomUUID();
      const projectId = arguments_.project_id ?? inboxId;
      requireProject(snapshot, projectId);
      if (arguments_.parent_id) {
        const parent = requireTask(snapshot, arguments_.parent_id);
        if (parent.projectId !== projectId) {
          throw new ToolFailure(
            "conflict",
            "Parent task belongs to another project.",
          );
        }
      }
      const operations = [
        upsert("task", id, {
          schemaVersion: 1,
          commandType: "task.create",
          id,
          userId: localUserId,
          content: arguments_.content,
          description: arguments_.description ?? null,
          projectId,
          sectionId: null,
          parentId: arguments_.parent_id ?? null,
          priority: arguments_.priority ?? 4,
          dueJson: arguments_.schedule ? dueJson(arguments_.schedule) : null,
          status: "open",
          estimatedFocusIntervals: arguments_.estimate ?? null,
          completedFocusIntervals: 0,
          totalFocusSeconds: 0,
          orderKey: orderKey(),
          dayOrder: null,
          isCollapsed: false,
          isDeleted: false,
          createdAt: now,
          updatedAt: now,
          completedAt: null,
        }, now),
        assignment(id, backlogId, now),
        ...labelAdditions(snapshot, id, arguments_.label_names, now),
      ];
      return mutationPlan( operations, { id });
    },
  );

  define(
    "update_task",
    {
      inputSchema: updateTaskSchema,
      outputSchema: outputSchemas.mutation,
      annotations: annotations.closed,
    },
    async (arguments_) => {
      const snapshot = await mutationSnapshot(context);
      const task = requireTask(snapshot, arguments_.task_id);
      const now = new Date().toISOString();
      const projectId = arguments_.project_id ?? string(task.projectId);
      requireProject(snapshot, projectId);
      const nextParent = arguments_.parent_id === undefined
        ? nullableString(task.parentId)
        : arguments_.parent_id;
      validateParent(snapshot, string(task.id), nextParent, projectId);
      const subtree = descendants(snapshot.tasks, task.id);
      const changedTasks = arguments_.project_id === undefined
        ? [task]
        : subtree;
      const operations = changedTasks.map((row) => {
        const root = row.id === task.id;
        return upsert(
          "task",
          row.id,
          sanitizeTask({
            ...row,
            commandType: arguments_.project_id !== undefined
              ? "task.move"
              : "task.update",
            ...(root && arguments_.content !== undefined
              ? { content: arguments_.content }
              : {}),
            ...(root && arguments_.description !== undefined
              ? { description: arguments_.description }
              : {}),
            ...(root && arguments_.priority !== undefined
              ? { priority: arguments_.priority }
              : {}),
            ...(root && arguments_.estimate !== undefined
              ? { estimatedFocusIntervals: arguments_.estimate }
              : {}),
            ...(root && arguments_.schedule !== undefined
              ? {
                dueJson: arguments_.schedule === null
                  ? null
                  : dueJson(arguments_.schedule),
              }
              : {}),
            ...(arguments_.project_id !== undefined
              ? { projectId, sectionId: null }
              : {}),
            ...(root ? { parentId: nextParent } : {}),
            updatedAt: now,
          }),
          now,
        );
      });
      operations.push(
        ...labelAdditions(
          snapshot,
          string(task.id),
          arguments_.label_names ?? [],
          now,
        ),
      );
      return mutationPlan( operations, { id: task.id });
    },
  );

  taskAction(
    define,
    "complete_task",
    annotations.closed,
    context,
    completeOperations,
  );

  taskAction(
    define,
    "restore_task",
    annotations.closed,
    context,
    restoreOperations,
  );

  define(
    "delete_task",
    {
      inputSchema: z.object({
        task_id: entityId,
        recurrence_scope: z.enum([
          "selected",
          "selected_and_following",
        ]).default("selected"),
      }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: annotations.destructive,
    },
    async ({ task_id, recurrence_scope }) => {
      const snapshot = await mutationSnapshot(context);
      const task = requireTask(snapshot, task_id);
      const now = new Date().toISOString();
      const operations = await deleteTaskOperations(
        snapshot,
        task,
        recurrence_scope,
        now,
      );
      return mutationPlan( operations, { id: task.id });
    },
  );
}
