import { z } from "zod";
import {
  MutationScope,
  mutationPlan,
  mutationSnapshot,
  remove,
  requireLabel,
  upsert,
  userLabel,
} from "./mutation_helpers.ts";
import {
  ToolFailure,
  entityId,
  name,
  outputSchemas,
  string,
} from "./tool_core.ts";

export function labelMutations({ define, context, annotations }: MutationScope) {
  define(
    "create_label",
    {
      inputSchema: z.object({ name }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: annotations.closed,
    },
    async ({ name }) => {
      const snapshot = await mutationSnapshot(context);
      if (
        snapshot.labels.some((label) =>
          label.kind === "user" &&
          string(label.name).toLowerCase() === name.toLowerCase()
        )
      ) {
        throw new ToolFailure("conflict", "Label name already exists.");
      }
      const now = new Date().toISOString();
      const id = crypto.randomUUID();
      return mutationPlan( [
        upsert("label", id, userLabel(id, name, now), now),
      ], { id });
    },
  );

  define(
    "delete_label",
    {
      inputSchema: z.object({ label_id: entityId }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: annotations.destructive,
    },
    async ({ label_id }) => {
      const snapshot = await mutationSnapshot(context);
      const label = requireLabel(snapshot, label_id, "user");
      const now = new Date().toISOString();
      const operations = snapshot.taskLabels
        .filter((relation) => relation.labelId === label.id)
        .map((relation) =>
          remove("task_label", relation.entityId, {
            commandType: "task.label.delete",
            taskId: relation.taskId,
            labelId: relation.labelId,
          }, now)
        );
      operations.push(remove("label", label.id, {
        commandType: "label.delete",
        id: label.id,
      }, now));
      return mutationPlan( operations, { id: label.id });
    },
  );
}
