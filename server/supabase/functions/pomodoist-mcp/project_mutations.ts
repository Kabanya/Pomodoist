import { z } from "zod";
import {
  MutationScope,
  compareProjectOrder,
  mutationPlan,
  mutationSnapshot,
  nextProjectColor,
  projectParents,
  remove,
  requireProject,
  sanitizeTask,
  selectedProjectIds,
  settingsOperation,
  upsert,
} from "./mutation_helpers.ts";
import {
  ToolFailure,
  createProjectSchema,
  entityId,
  inboxId,
  localUserId,
  orderKey,
  outputSchemas,
  string,
  updateProjectSchema,
} from "./tool_core.ts";

export function projectMutations({ define, context, annotations }: MutationScope) {
  define(
    "create_project",
    {
      inputSchema: createProjectSchema,
      outputSchema: outputSchemas.mutation,
      annotations: annotations.closed,
    },
    async (arguments_) => {
      const snapshot = await mutationSnapshot(context);
      if (
        snapshot.projects.some((project) =>
          string(project.name).toLowerCase() ===
            arguments_.name.toLowerCase()
        )
      ) {
        throw new ToolFailure("conflict", "Project name already exists.");
      }
      const now = new Date().toISOString();
      const id = crypto.randomUUID();
      const projectColor = arguments_.color ??
        nextProjectColor(snapshot.projects);
      return mutationPlan( [
        upsert("project", id, {
          schemaVersion: 1,
          commandType: "project.create",
          id,
          userId: localUserId,
          name: arguments_.name,
          color: projectColor,
          parentId: null,
          viewStyle: "list",
          isFavorite: false,
          isArchived: false,
          isDeleted: false,
          orderKey: orderKey(),
          createdAt: now,
          updatedAt: now,
        }, now),
      ], { id });
    },
  );

  define(
    "update_project",
    {
      inputSchema: updateProjectSchema,
      outputSchema: outputSchemas.mutation,
      annotations: annotations.closed,
    },
    async (arguments_) => {
      if (arguments_.project_id === inboxId) {
        throw new ToolFailure("forbidden", "Inbox cannot be changed.");
      }
      const snapshot = await mutationSnapshot(context);
      const project = requireProject(snapshot, arguments_.project_id);
      const now = new Date().toISOString();
      return mutationPlan( [
        upsert("project", project.id, {
          ...project,
          commandType: "project.update",
          ...(arguments_.color !== undefined
            ? { color: arguments_.color }
            : {}),
          ...(arguments_.is_favorite !== undefined
            ? { isFavorite: arguments_.is_favorite }
            : {}),
          updatedAt: now,
        }, now),
      ], { id: project.id });
    },
  );

  define(
    "delete_project",
    {
      inputSchema: z.object({ project_id: entityId }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: annotations.destructive,
    },
    async ({ project_id }) => {
      if (project_id === inboxId) {
        throw new ToolFailure("forbidden", "Inbox cannot be deleted.");
      }
      const snapshot = await mutationSnapshot(context);
      const project = requireProject(snapshot, project_id);
      const now = new Date().toISOString();
      const operations = snapshot.tasks
        .filter((task) => task.projectId === project_id)
        .map((task) =>
          upsert(
            "task",
            task.id,
            sanitizeTask({
              ...task,
              commandType: "task.move",
              projectId: inboxId,
              sectionId: null,
              updatedAt: now,
            }),
            now,
          )
        );
      const projects = snapshot.projects.filter((row) => !row.isDeleted)
        .sort((a, b) => compareProjectOrder(a, b));
      const parents = projectParents(projects);
      const parentId = parents.get(project_id) ?? null;
      const children = projects.filter((row) =>
        parents.get(string(row.id)) === project_id
      );
      const siblings = projects.filter((row) =>
        row.id !== inboxId && parents.get(string(row.id)) === parentId
      )
        .flatMap((row) => row.id === project_id ? children : [row]);
      siblings.forEach((row, index) => {
        const key = String((index + 1) * 1024).padStart(20, "0");
        if ((row.parentId ?? null) === parentId && row.orderKey === key) return;
        operations.push(upsert("project", string(row.id), {
          ...row,
          parentId,
          orderKey: key,
          commandType: "project.update",
          updatedAt: now,
        }, now));
      });
      const selected = selectedProjectIds(snapshot.settings)
        .filter((id) => id !== project_id);
      if (selected.length === 0) selected.push(inboxId);
      if (
        JSON.stringify(selected) !==
          JSON.stringify(selectedProjectIds(snapshot.settings))
      ) {
        operations.push(settingsOperation(
          snapshot.settings,
          { selectedProjectIdsJson: JSON.stringify(selected) },
          now,
        ));
      }
      operations.push(remove("project", project.id, {
        commandType: "project.delete",
        id: project.id,
      }, now));
      return mutationPlan( operations, { id: project.id });
    },
  );
}
