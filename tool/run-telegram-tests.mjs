// Deno-compatible unit tests can also run in an offline Node 22 workspace.
import { test } from 'node:test';
globalThis.Deno = { test };
for (const path of process.argv.slice(2)) await import(new URL(path, `file://${process.cwd()}/`));
