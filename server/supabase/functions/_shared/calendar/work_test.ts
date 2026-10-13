import { strict as assert } from "node:assert";
import { consumeWork, emptyWork, mergeWork, readRequired } from "./work.ts";
Deno.test("notification bursts coalesce by event without losing later versions", () => {
  let pending = emptyWork();
  for (let i = 0; i < 100; i++) {
    pending = mergeWork(pending, {
      hints: [{ eventId: "e", version: null, kind: "updated" }],
    });
  }
  assert.equal(pending.hints.length, 1);
  assert.equal(pending.generation, 100);
  const newer = mergeWork(pending, {
    hints: [{ eventId: "e", version: "v2", kind: "updated" }],
  });
  assert.equal(consumeWork(newer, pending).hints[0].version, "v2");
});
Deno.test("completing a snapshot preserves a newer unversioned edit of the same event", () => {
  const first = mergeWork(emptyWork(), {
    hints: [{ eventId: "e", version: null, kind: "updated" }],
  });
  const second = mergeWork(first, {
    hints: [{ eventId: "e", version: null, kind: "updated" }],
  });
  assert.equal(consumeWork(second, first).hints.length, 1);
  assert.equal(consumeWork(first, first).hints.length, 0);
});
Deno.test("maintenance alone never requires an event read", () => {
  assert.equal(
    readRequired(mergeWork(emptyWork(), { maintenance: true })),
    false,
  );
  assert.equal(readRequired(mergeWork(emptyWork(), { recovery: true })), true);
});
Deno.test("publish revisions coalesce to latest and are consumed only at claimed generation", () => {
  const first = mergeWork(emptyWork(), { publishRevision: 1 });
  const next = mergeWork(first, { publishRevision: 2 });
  assert.equal(consumeWork(next, first).publishRevision, 2);
  assert.equal(consumeWork(next, next).publishRevision, null);
});
