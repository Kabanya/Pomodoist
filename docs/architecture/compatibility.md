# Compatibility policy

The Flutter MVVM architecture targets the current application and server
contracts. Internal Dart APIs, local schemas and persisted formats may change
without migration adapters, legacy wrappers or parallel implementations.

Product behavior, supported platforms, localization, design, application IDs,
deep links and development/staging/production environments remain part of the
current product contract. A release may still require platform builds, signing,
staging and deployment checks; those gates are separate from architecture
validation and are not established by local tests.

Architecture work is validated with static analysis, unit/widget tests and
fully automated repository checks. Manual UI, emulator, device and visual
acceptance are excluded.
