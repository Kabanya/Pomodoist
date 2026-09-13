# Pomodoist application monorepo implementation plan

Approved option B: one Flutter package and a shared modular server, released in
two minor updates. Baseline `71a9814` on `develop`; work directly in the current
checkout. No commits, push, deployment or publication are part of implementation.
The [compatibility contract](../../architecture/compatibility.md) and
[repository architecture](../../architecture/repository.md) describe the result.

## Scope

Preserve Flutter, Riverpod, Drift, existing dependency versions, UI, storage
formats, native identities, dates, entitlement rules and AI quotas. No extra
packages or microservices. Include the draft-batch data-loss correction and
architecture/path checks. Date or access-policy changes are separate work.

Latest validation constraint: unit tests, static analysis and simple automated
checks only, with no manual intervention or manual UI/device testing.

## 1. Capture behavior

- Run original Flutter, server, companion and helper checks. Record preexisting
  failures separately from path changes made during implementation.
- Preserve examples for analysis, task creation, Focus, sync and authorization in
  `tool/tests/fixtures`; reuse current regression tests.
- Record application IDs, app groups, storage names/directories, schema versions
  and configuration sources.

## 2. Repair draft batch persistence

- Reproduce shared `opId` deduplication with several drafts and labels.
- Use existing `command.id` for retry identity. Every operation in the batch must
  be distinct; task identities remain stable when the same request is retried.
- Test real SQL receipts, relationships and atomic rollback, including a lost
  HTTP response after successful commit.
- Recognize accepted legacy commands without creating duplicate tasks or orphan
  links. Historical lost-data recovery is excluded.
- Add a new migration if required; do not edit installation history.

## 3. Extract common server behavior

- Move AI prompts, provider routing, fallbacks and validation out of Watch.
- Extract product state and task/Focus operations as functions with explicit
  dependencies. Keep helpers flat for the hosted assembler.
- Keep authentication, request translation and response envelopes in adapters.
- Make Telegram and MCP/OpenClaw consume common functions. Remove HTTP mutation
  interception and fake tool registration, preserving authorization, revision,
  argument hash and durable request receipts.
- Add `pomodoist-ai`; old Watch analysis remains a compatible entry to the same
  implementation. Preserve guest StoreKit verification and signed-in access.
- Update manifest/config and verify dependency closure in packaged sources.

## 4. Separate Flutter responsibilities

- Keep composition, startup and navigation in `app`; remove reverse business
  dependencies and handwritten import cycles.
- Move recording/analysis/draft orchestration from Quick Add's large widget into
  one host-owned controller. Preserve overlay singleton, account lifetime,
  collapse/close/abort behavior, retries and edited drafts.
- Separate billing models, store/server gateway, controller/provider and paywall.
  Preserve pending purchases, restore, account generation and active rights.
- Extract synchronization mapping from account orchestration. Preserve queue
  ownership, local-change/queue transactions, null patches, cursors and repair.
- Reduce task reads with equivalent status/project predicates; keep complete
  hierarchies, ordering, date interpretation and literal search behavior.
- Prepare one explicit R2 endpoint build selection, defaulting to R1 Watch.
  Missing new endpoint gives upgrade guidance, preserving input with no replay.

## 5. Move source trees and build paths

- Move the entire Flutter package to `apps/flutter`: sources, tests, resources,
  platform projects, shared Apple source, StoreKit and Drift history/configs.
- Move Mini App and Chrome to `apps`, OpenClaw to `tool/openclaw`.
- Update Make, Docker, CI, native references, code generation, version readers,
  package sources and artifact paths with each move.
- Preserve root Make entrypoints and root SDK/environment configuration. Name
  repository, Flutter and artifact roots explicitly.
- Update documentation links in English and narrowly allow approved architecture
  documents in Git.

## 6. Enforce and verify

- Reject shared-server imports of adapters and pure-domain imports of UI, DB or
  composition; reject handwritten cycles with a small standard-library checker.
- Run unit suites and simple fully automated checks in the final layout.
- Check dependency resolution and path assumptions in a clean temporary copy;
  check public/self-hosted and hosted manifest dependency completeness.
- Record inherited failures and external release gates without presenting them
  as successful checks.

## Behavior acceptance

| Area | Contract |
| --- | --- |
| AI | Normal/Smart, provider failures/timeouts/malformed JSON, existing auth, both entries |
| Tasks | Multiple drafts/labels, stable retry, lost response, no lost or duplicate operations |
| Focus | Start/pause/resume/finish and stale-device conflicts |
| Voice | Retained input/edits, cancellation/disposal, account changes, one controller |
| Billing | Restore, pending purchase, account changes and preserved access |
| Sync | Offline queue/retry, deleted rows, cursor and account isolation |
| Integration | Watch/widget, Telegram/Mini App, Chrome, MCP/OpenClaw contracts |
| Packaging | Root commands, app paths, pinned dependencies, manifest closure |

## Release and rollback

R1 contains the full structure/shared implementation. Apply its additive migration
first, then compatible server functions, then clients. R1 clients retain the Watch
AI route by default. R2 builds select the AI route and require server R1 or newer.
No error triggers automatic replay against a different paid/mutating endpoint.

The old external Watch API remains supported through both releases. Removing it
requires a separate decision. Before release, platform/staging validation and
observability comparisons remain separate release actions. Do not log transcripts
or secrets. Local automated checks do not prove production behavior.
