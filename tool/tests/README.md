# Shared behavior fixtures

`fixtures/companion_commands.json` records existing text-analysis, draft-commit,
Focus, authorization-error and synchronization envelopes. Values are synthetic.
`fixtures/pomodoist_productivity_parity.json` preserves the pre-refactor date and
productivity cases without changing their interpretation.

Consumers:

- `apps/flutter/test/companion_contract_test.dart`: client analysis request and draft decoding.
- `server/tests/contracts_test.ts`: server draft decoding, task/label plans, Focus state and authorization.
- `apps/flutter/test/productivity_parity_test.dart`: existing Flutter productivity contract.
- `server/tests/database/pomodoist_productivity_parity.inc`: existing SQL parity scenarios.

Run `make test`, or the focused Flutter test from `apps/flutter`. Server fixture
checks use `deno test --config server/supabase/deno.json --allow-env --allow-read
server/tests/contracts_test.ts` from the repository root. SQL receipt tests remain
in `server/tests/database`; they require the explicit disposable local database.

Date discrepancies are preserved for a separate behavior change. Do not silently
regenerate expected results to make a new date policy pass.
