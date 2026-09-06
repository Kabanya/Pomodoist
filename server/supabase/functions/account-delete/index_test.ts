import { assertEquals } from "jsr:@std/assert@1";

import { type AccountDeleteDeps, handleAccountDelete } from "./index.ts";

Deno.test("account-delete requires Authorization", async () => {
  const response = await handleAccountDelete(request(true), deps());

  assertEquals(response.status, 401);
});

Deno.test("account-delete requires confirmation", async () => {
  const response = await handleAccountDelete(request(false, true), deps());

  assertEquals(response.status, 400);
});

Deno.test("account-delete rejects an invalid session", async () => {
  const response = await handleAccountDelete(
    request(true, true),
    deps({ signedIn: false }),
  );

  assertEquals(response.status, 401);
});

Deno.test("account-delete removes storage objects and deletes the auth user", async () => {
  const calls: TestCalls = { deletedUsers: [], removedPaths: [] };
  const response = await handleAccountDelete(
    request(true, true),
    deps({ calls }),
  );
  const payload = await response.json();

  assertEquals(response.status, 200);
  assertEquals(payload.deleted, true);
  assertEquals(payload.userId, "user-1");
  assertEquals(payload.storageObjectsRemoved, 2);
  assertEquals(calls.deletedUsers, ["user-1"]);
  assertEquals(calls.removedPaths, [
    "nottica-vaults:user-1/root.md",
    "nottica-vaults:user-1/Notes/a.md",
  ]);
});

type TestCalls = {
  deletedUsers: string[];
  removedPaths: string[];
};

function request(confirm: boolean, authorized = false) {
  return new Request("https://functions.test/account-delete", {
    method: "POST",
    headers: authorized ? { Authorization: "Bearer test" } : undefined,
    body: JSON.stringify({ confirm }),
  });
}

function deps({
  signedIn = true,
  calls = { deletedUsers: [], removedPaths: [] },
}: {
  signedIn?: boolean;
  calls?: TestCalls;
} = {}): AccountDeleteDeps {
  return {
    createAuthClient: () => ({
      auth: {
        getUser: async () => ({
          data: { user: signedIn ? { id: "user-1" } : null },
          error: null,
        }),
      },
    }),
    createAdminClient: () => ({
      auth: {
        admin: {
          deleteUser: async (userId: string) => {
            calls.deletedUsers.push(userId);
            return { data: {}, error: null };
          },
        },
      },
      storage: {
        from: (bucketId: string) => fakeBucket(bucketId, calls),
      },
    }),
  };
}

function fakeBucket(bucketId: string, calls: TestCalls) {
  const objects: Record<
    string,
    Array<{
      name: string;
      id?: string | null;
      metadata?: unknown;
    }>
  > = {
    "nottica-vaults:user-1": [
      { name: "root.md", id: "object-root", metadata: {} },
      { name: "Notes", id: null, metadata: null },
    ],
    "nottica-vaults:user-1/Notes": [
      { name: "a.md", id: "object-a", metadata: {} },
    ],
  };
  return {
    list: async (prefix = "") => ({
      data: objects[`${bucketId}:${prefix}`] ?? [],
      error: null,
    }),
    remove: async (paths: string[]) => {
      calls.removedPaths.push(...paths.map((path) => `${bucketId}:${path}`));
      return { data: {}, error: null };
    },
  };
}

Deno.test("account-delete supports an installation without a storage service", async () => {
  const previous = Deno.env.get("ACCOUNT_STORAGE_BUCKETS");
  Deno.env.set("ACCOUNT_STORAGE_BUCKETS", "");
  try {
    const calls: TestCalls = { deletedUsers: [], removedPaths: [] };
    const response = await handleAccountDelete(request(true, true), deps({ calls }));
    assertEquals(response.status, 200);
    assertEquals(calls.deletedUsers, ["user-1"]);
    assertEquals(calls.removedPaths, []);
    assertEquals((await response.json()).storageObjectsRemoved, 0);
  } finally {
    if (previous === undefined) Deno.env.delete("ACCOUNT_STORAGE_BUCKETS");
    else Deno.env.set("ACCOUNT_STORAGE_BUCKETS", previous);
  }
});
