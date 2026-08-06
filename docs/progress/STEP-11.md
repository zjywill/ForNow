# Step 1.1 - App Environment And Dependency Injection

- Status: `DONE`
- Started: 2026-08-04
- Completed: 2026-08-04
- Prerequisite: Phase 0 continuation exception recorded 2026-08-04
- Pending prerequisite evidence: `MT-WIN-004C` remains required before 1.0

## Scope

- Compose production services without global singletons.
- Inject repository, clock, UUID generator, parser, window coordinator,
  clipboard, OCR, notification, and currency-rate provider.
- Provide production, preview, and test variants.
- Centralize startup and shutdown ordering.
- Emit structured lifecycle logs through a closed event enum that cannot carry
  note text.

## Files Changed

- `App/AppEnvironment.swift`
- `App/AppLifecycleLogging.swift`
- `App/AppDelegate.swift`
- `App/ForNowApp.swift`
- `App/ContentView.swift`
- `Packages/ForNowCore/Sources/ForNowCore/Dependencies.swift`
- `Packages/ForNowPersistence/Sources/ForNowPersistence/PersistenceNoteRepository.swift`
- `Packages/ForNowModes/Sources/ForNowModes/SourceParser.swift`
- `Packages/ForNowWindowing/Sources/ForNowWindowing/WindowCoordinator.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/ClipboardService.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/OCRService.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/NotificationService.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/CurrencyRateProvider.swift`
- `Tests/ForNowTests/AppEnvironmentTests.swift`
- `docs/02_ARCHITECTURE.md`

## Composition Contract

- Production defers opening `ForNow.sqlite` until `start()` and leaves network
  rates and clipboard reads disabled pending explicit user opt-in.
- Preview and test environments use no real database or network dependency.
- Startup order is repository, clipboard, notifications, then window
  coordinator.
- Shutdown flushes the repository before any service teardown, then stops the
  window coordinator, notifications, clipboard, and repository in that order.
- A repository preparation failure can still shut down without a second
  not-prepared error.
- `AppLifecycleLogging` accepts only privacy-bounded lifecycle events and never
  accepts arbitrary strings or note source.

## Automated Evidence

- `AppEnvironmentTests`: 7 passed, 0 failed, 0 skipped.
- All nine required dependencies are reachable through the test environment.
- Preview starts and stops with in-memory or disabled dependencies.
- Launch is idempotent and produces one ordered startup sequence.
- A pending draft is flushed before every teardown event.
- Repeated shutdown is idempotent.
- Failed repository preparation does not prevent shutdown.
- Production composition is deferred-open and defaults network/clipboard to
  disabled adapters.
- Editor projection remained 12/12, window spike remained 10/10, and
  persistence remained 15/15 plus both process-kill fault gates.
- Traceability remained 65/65 evidence, 69/69 requirements, and 493 mapped test
  IDs.

## Real Launch Smoke

- The generated Debug application launched as a real process and exposed one
  frontmost `ForNow` window.
- Production startup created `ForNow.sqlite` only after launch.
- A normal application Quit terminated the process through AppDelegate's
  asynchronous termination reply.
- Unified lifecycle logs showed `repository_flushed` before window,
  notification, clipboard, and repository teardown, followed by
  `shutdown_completed`.
- The host has no valid Apple Development signing identity, so the signed
  `scripts/test-ui.sh` gate was unavailable. The real application launch,
  foreground-window check, graceful Quit, and lifecycle log inspection provide
  the Step 1.1 launch evidence; the existing signed UI gate remains available
  when an identity is installed.

## Verification Commands

```bash
scripts/format.sh --fix
scripts/test.sh
scripts/test-editor-projection.sh
scripts/test-window-spike.sh
scripts/test-persistence-spike.sh
scripts/test-traceability.sh
scripts/check-generated-project.sh
scripts/build.sh
CONFIGURATION=Release scripts/build.sh
open -n DerivedData/Build/Products/Debug/ForNow.app
/usr/bin/log show --last 3m --style compact \
  --predicate 'subsystem == "app.fornow.ForNow" AND category == "lifecycle"'
git diff --check
```

## Exit Criteria

- UI previews and tests need no real database or network: `PASS`.
- App shutdown flushes repository before service teardown: `PASS` in automated
  tests and the real application lifecycle log.

## Deferred Manual Evidence

`MT-WIN-004C` remains `PENDING` under the owner-approved Phase 0 continuation
exception. It is not counted as Step 1.1 evidence and remains required before
the 1.0 release gate.
