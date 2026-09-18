import { z } from "zod";
import {
  MutationScope,
  assignment,
  completeOperations,
  ensureUniqueStatusName,
  fallbackFocusStatus,
  kanbanStatuses,
  mutationPlan,
  mutationSnapshot,
  remove,
  reorderStatuses,
  reorderedTask,
  requireLabel,
  requireProject,
  requireTask,
  restoreOperations,
  settingsOperation,
  upsert,
} from "./mutation_helpers.ts";
import {
  Operation,
  ToolFailure,
  backlogId,
  createStatusSchema,
  doneId,
  entityId,
  localUserId,
  outputSchemas,
  settingsId,
  string,
  updateStatusSchema,
} from "./tool_core.ts";

export function kanbanMutations({ define, context, annotations }: MutationScope) {
  define(
    "create_kanban_status",
    {
      inputSchema: createStatusSchema,
      outputSchema: outputSchemas.mutation,
      annotations: annotations.closed,
    },
    async ({ name, color }) => {
      const snapshot = await mutationSnapshot(context);
      ensureUniqueStatusName(snapshot, name);
      const now = new Date().toISOString();
      const id = crypto.randomUUID();
      const statuses = kanbanStatuses(snapshot);
      statuses.splice(Math.max(1, statuses.length - 1), 0, {
        id,
        userId: localUserId,
        name,
        color: color ?? null,
        kind: "kanbanStatus",
        systemKey: null,
        orderKey: "",
        isFavorite: false,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      });
      const operations = reorderStatuses(statuses, now, id);
      return mutationPlan( operations, { id });
    },
  );

  define(
    "update_kanban_status",
    {
      inputSchema: updateStatusSchema,
      outputSchema: outputSchemas.mutation,
      annotations: annotations.closed,
    },
    async (arguments_) => {
      const snapshot = await mutationSnapshot(context);
      const status = requireLabel(
        snapshot,
        arguments_.status_id,
        "kanbanStatus",
      );
      if (arguments_.name !== undefined) {
        ensureUniqueStatusName(snapshot, arguments_.name, string(status.id));
      }
      if (
        arguments_.target_index !== undefined &&
        (status.id === backlogId || status.id === doneId)
      ) {
        throw new ToolFailure(
          "forbidden",
          "System Kanban statuses cannot be reordered.",
        );
      }
      const now = new Date().toISOString();
      const operations: Operation[] = [];
      if (
        arguments_.name !== undefined ||
        arguments_.color !== undefined
      ) {
        operations.push(upsert("label", status.id, {
          id: status.id,
          commandType: "kanban.status.rename",
          ...(arguments_.name !== undefined ? { name: arguments_.name } : {}),
          ...(arguments_.color !== undefined
            ? { color: arguments_.color }
            : {}),
          changedAt: now,
        }, now));
      }
      if (arguments_.target_index === undefined) {
        return mutationPlan( operations, {
          id: status.id,
        });
      }
      const statuses = kanbanStatuses(snapshot)
        .filter((item) => item.id !== status.id);
      statuses.splice(
        Math.min(arguments_.target_index, statuses.length - 1),
        0,
        status,
      );
      operations.push(...reorderStatuses(statuses, now));
      return mutationPlan( operations, {
        id: status.id,
      });
    },
  );

  define(
    "delete_kanban_status",
    {
      inputSchema: z.object({ status_id: entityId }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: annotations.destructive,
    },
    async ({ status_id }) => {
      if (status_id === backlogId || status_id === doneId) {
        throw new ToolFailure(
          "forbidden",
          "System Kanban statuses cannot be deleted.",
        );
      }
      const snapshot = await mutationSnapshot(context);
      const status = requireLabel(snapshot, status_id, "kanbanStatus");
      const now = new Date().toISOString();
      const operations = snapshot.assignments
        .filter((link) => link.labelId === status.id)
        .map((link) => assignment(link.taskId, backlogId, now));
      const settings = snapshot.settings;
      if (settings.focusStatusLabelId === status.id) {
        operations.push(settingsOperation(
          settings,
          {
            focusStatusLabelId: fallbackFocusStatus(
              snapshot,
              string(status.id),
            ),
          },
          now,
        ));
      }
      operations.push(remove("label", status.id, {
        commandType: "kanban.status.delete",
        id: status.id,
        isDeleted: true,
        changedAt: now,
      }, now));
      return mutationPlan( operations, { id: status.id });
    },
  );

  define(
    "configure_kanban",
    {
      inputSchema: z.object({
        project_ids: z.array(entityId).min(1).max(100).optional(),
        focus_status_id: entityId.optional(),
      }).strict().refine(
        (value) =>
          value.project_ids !== undefined ||
          value.focus_status_id !== undefined,
        "At least one changed field is required.",
      ),
      outputSchema: outputSchemas.mutation,
      annotations: annotations.closed,
    },
    async ({ project_ids, focus_status_id }) => {
      const snapshot = await mutationSnapshot(context);
      const now = new Date().toISOString();
      const operations: Operation[] = [];
      if (project_ids !== undefined) {
        const unique = [...new Set(project_ids)].sort();
        for (const id of unique) requireProject(snapshot, id);
        operations.push(settingsOperation(
          snapshot.settings,
          { selectedProjectIdsJson: JSON.stringify(unique) },
          now,
        ));
      }
      if (focus_status_id !== undefined) {
        const status = requireLabel(
          snapshot,
          focus_status_id,
          "kanbanStatus",
        );
        if (status.id === doneId) {
          throw new ToolFailure(
            "conflict",
            "Done cannot be the focus status.",
          );
        }
        operations.push(settingsOperation(
          snapshot.settings,
          { focusStatusLabelId: status.id },
          now,
        ));
      }
      return mutationPlan( operations, { id: settingsId });
    },
  );

  define(
    "move_task_on_kanban",
    {
      inputSchema: z.object({
        task_id: entityId,
        status_id: entityId,
        target_index: z.number().int().min(0).optional(),
      }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: annotations.closed,
    },
    async ({ task_id, status_id, target_index }) => {
      const snapshot = await mutationSnapshot(context);
      const task = requireTask(snapshot, task_id);
      const status = requireLabel(snapshot, status_id, "kanbanStatus");
      const now = new Date().toISOString();
      let operations: Operation[];
      if (status.id === doneId && task.status !== "completed") {
        operations = completeOperations(snapshot, task, now);
      } else if (status.id !== doneId && task.status === "completed") {
        operations = restoreOperations(
          snapshot,
          task,
          now,
          string(status.id),
        );
      } else {
        operations = [assignment(task.id, string(status.id), now)];
      }
      if (target_index !== undefined && status.id !== doneId) {
        const row = reorderedTask(
          snapshot,
          task,
          string(status.id),
          target_index,
          now,
        );
        if (row) operations.push(upsert("task", task.id, row, now));
      }
      return mutationPlan( operations, { id: task.id });
    },
  );
}
