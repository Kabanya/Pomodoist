# Pomodoist Code Signing Policy

## Scope

This policy covers official Pomodoist Windows MSIX bundles published by
FinchForge LLC from Git tags in `Kabanya/Pomodoist`. The client and official
client binaries are distributed under `AGPL-3.0-only`.

Free code signing provided by SignPath.io, certificate by SignPath Foundation.

## Team roles

- Committers and reviewers: [Kabanya](https://github.com/Kabanya), the current
  repository owner and maintainer.
- Submitter: the Pomodoist Windows Release GitHub Actions workflow, using a
  submitter-only SignPath API token stored in the protected
  `windows-production` environment.
- Approver: [Kabanya](https://github.com/Kabanya), acting through a separate
  MFA-protected interactive SignPath account. The CI submitter cannot approve
  its own signing request.

Pomodoist's handling of user and service data is described in the
[Privacy Policy](https://pomodoist.com/privacy/). This includes optional
account, synchronization, telemetry, voice, calendar, CAPTCHA, and billing
integrations that communicate with networked systems when users enable or use
the corresponding functionality.

## Build and signing controls

- Release artifacts are built only by the repository's GitHub Actions release
  workflow on GitHub-hosted x64 and ARM64 runners.
- The workflow accepts tags matching the version in `pubspec.yaml`, builds both
  native architectures, creates one unsigned MSIX bundle, and uploads it as a
  GitHub Actions artifact before submitting it to SignPath.
- SignPath retains the private signing key. No certificate private key is
  stored in this repository or in GitHub Actions secrets.
- Signing requests require a submitter API token and approval under the
  SignPath release policy. Submitters cannot approve their own requests.
- All maintainers, submitters, and approvers must use multi-factor
  authentication. GitHub Actions dependencies are pinned to immutable commits.
- A release remains a private draft until its signature, publisher, package
  identity, architectures, protocol registration, installation, and launch
  smoke tests pass.

## Authorized artifacts

Only `Pomodoist.msixbundle` artifacts with package identity
`com.finchforge.pomodoist`, produced from a `vX.Y.Z` tag by the protected
workflow, may receive the public release signature. Unsigned artifacts are not
published as Pomodoist releases.

## Incident response

Suspected key misuse, unauthorized signing, or compromised release
infrastructure must be reported privately to the maintainers and SignPath.
FinchForge LLC will stop the release workflow, revoke affected credentials or
certificates, remove compromised artifacts, publish remediation guidance, and
rotate submitter access before signing resumes.
