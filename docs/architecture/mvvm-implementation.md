# Flutter MVVM implementation notes

The canonical architecture contract is
[Flutter application architecture](flutter-app-architecture.md). It defines the
layers, dependency direction and boundary rules; this document only records
implementation notes specific to the Riverpod/MVVM client.

## ViewModel conventions

- ViewModels are Riverpod `Notifier` or `AsyncNotifier` classes and acquire
  their dependencies inside `build`.
- State is a single immutable class per ViewModel that describes loading,
  data, validation and recoverable errors.
- Actions are typed methods; pending/duplicate-submission guards live in the
  ViewModel state, not in widgets.
- `autoDispose` is used for screen-scoped state. Shared application state
  (account, access, focus, persisted preferences) is owned by repositories and
  outlives any screen.
- A ViewModel ignores late results after disposal or an account-generation
  change instead of publishing them.

## Riverpod conventions

- `config/` owns provider construction and wiring; UI files may hold providers
  that are scoped to a screen or widget.
- Re-exporting a provider does not change the layer of the exported symbol;
  the boundary rules apply to the resolved dependency.
- Widgets read UI values and typed actions, never storage controllers or
  source clients.

The main window and Quick Add window share repository data while each retained
screen instance owns its draft and selection state. Long-running operations
capture stable dependencies before awaiting and dispose subscriptions with
their owner.

## Storage and synchronization notes

Drift and transport details live in services and repository implementations.
Task, Kanban, Focus and outbox mutations that belong together run in one
transaction, and a failure rolls the complete operation back. Synchronization
services own queue draining, push/pull, retry, cursor and remote-application
behavior. Repository implementations use shared local services rather than
depending on one another.

## Validation notes

`tool/check_architecture.py` resolves imports, exports, conditional directives
and part files for the directory-level rules.
`apps/flutter/tool/check_architecture_types.dart` adds resolved-Dart checks for
inferred provider types and concrete implementations. The accepted validation
scope is static analysis, unit/widget tests and other fully automated checks.
Manual UI, emulator, device and visual acceptance are outside this work.
