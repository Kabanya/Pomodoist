import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type User = {
  id: string;
};

type AuthClientLike = {
  auth: {
    getUser: () => Promise<{
      data: { user: User | null };
      error?: { message: string } | null;
    }>;
  };
};

type StorageObject = {
  name: string;
  id?: string | null;
  metadata?: unknown;
};

type StorageBucketLike = {
  list: (
    prefix?: string,
    options?: Record<string, unknown>,
  ) => Promise<{
    data: StorageObject[] | null;
    error: { message: string } | null;
  }>;
  remove: (paths: string[]) => Promise<{
    data: unknown;
    error: { message: string } | null;
  }>;
};

type AdminClientLike = {
  auth: {
    admin: {
      deleteUser: (userId: string) => Promise<{
        data: unknown;
        error: { message: string } | null;
      }>;
    };
  };
  storage: {
    from: (bucketId: string) => StorageBucketLike;
  };
};

export type AccountDeleteDeps = {
  createAuthClient?: (authorization: string) => AuthClientLike;
  createAdminClient?: () => AdminClientLike;
};


export async function handleAccountDelete(
  req: Request,
  deps: AccountDeleteDeps = {},
) {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    return json({ error: "Authorization is required." }, 401);
  }

  const body = await readJson(req);
  if (!body.ok) {
    return json({ error: body.error }, 400);
  }
  if ((body.value as { confirm?: unknown }).confirm !== true) {
    return json({ error: "Deletion confirmation is required." }, 400);
  }

  const authClient = deps.createAuthClient?.(authorization) ??
    createAuthClient(authorization);
  const { data, error } = await authClient.auth.getUser();
  if (error || !data.user) {
    return json({ error: error?.message ?? "User is not signed in." }, 401);
  }

  const admin = deps.createAdminClient?.() ?? createAdminClient();
  let storageObjectsRemoved = 0;
  try {
    storageObjectsRemoved = await deleteAccountStorage(admin, data.user.id);
  } catch (storageError) {
    return json({ error: `Storage cleanup failed: ${storageError}` }, 500);
  }
  const deleted = await admin.auth.admin.deleteUser(data.user.id);
  if (deleted.error) {
    return json({ error: deleted.error.message }, 500);
  }

  return json({
    deleted: true,
    userId: data.user.id,
    storageObjectsRemoved,
  });
}

async function deleteAccountStorage(
  admin: AdminClientLike,
  userId: string,
) {
  let removed = 0;
  for (const bucketId of (Deno.env.get("ACCOUNT_STORAGE_BUCKETS") ?? "nottica-vaults")
    .split(",").map((value) => value.trim()).filter(Boolean)) {
    const bucket = admin.storage.from(bucketId);
    const paths = await listObjectPaths(bucket, userId);
    for (let index = 0; index < paths.length; index += 100) {
      const chunk = paths.slice(index, index + 100);
      if (chunk.length === 0) {
        continue;
      }
      const result = await bucket.remove(chunk);
      if (result.error) {
        throw new Error(result.error.message);
      }
      removed += chunk.length;
    }
  }
  return removed;
}

async function listObjectPaths(
  bucket: StorageBucketLike,
  prefix: string,
): Promise<string[]> {
  const { data, error } = await bucket.list(prefix, {
    limit: 1000,
    offset: 0,
    sortBy: { column: "name", order: "asc" },
  });
  if (error) {
    throw new Error(error.message);
  }
  const paths: string[] = [];
  for (const item of data ?? []) {
    const path = `${prefix}/${item.name}`;
    if (isStorageFolder(item)) {
      paths.push(...await listObjectPaths(bucket, path));
    } else {
      paths.push(path);
    }
  }
  return paths;
}

function isStorageFolder(item: StorageObject) {
  return item.id == null && item.metadata == null;
}

type JsonReadResult =
  | { ok: true; value: Record<string, unknown> }
  | { ok: false; error: string };

async function readJson(req: Request): Promise<JsonReadResult> {
  try {
    const value = await req.json();
    if (value && typeof value === "object" && !Array.isArray(value)) {
      return { ok: true, value: value as Record<string, unknown> };
    }
    return { ok: false, error: "Request body must be a JSON object." };
  } catch (_) {
    return { ok: false, error: "Request body must be valid JSON." };
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function createAuthClient(authorization: string): AuthClientLike {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authorization } } },
  );
}

function createAdminClient(): AdminClientLike {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
}

if (import.meta.main) {
  Deno.serve((req) => handleAccountDelete(req));
}
