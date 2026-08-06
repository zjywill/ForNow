# Step 0.1 - Create The Repository

- Status: `DONE`
- Started: 2026-08-03
- Completed: 2026-08-03
- Evidence reviewed: `AN-POS-002`, `AN-POS-003`
- Requirements implemented: project foundation; no functional requirement yet
- Tests: smoke unit test, launch UI test, performance target smoke benchmark

## Files Changed

- `project.yml` and generated `ForNow.xcodeproj`
- `App/`
- `Packages/`
- `Tests/`, `UITests/`, and `PerformanceTests/`
- `scripts/`
- `.github/workflows/ci.yml`

## Dependency Review

| Dependency | Version | License | Role | Network behavior |
| --- | --- | --- | --- | --- |
| GRDB.swift | 7.11.1 | MIT | SQLite access | None at runtime |
| KeyboardShortcuts | 1.10.0 | MIT | Global shortcut adapter | None |
| XcodeGen | 2.45.4 | MIT | Reproducible project generation | Build tool only |

All three upstream repositories showed maintenance activity in 2026 when this
step began. Dependencies are source packages or a downloaded source-project
tool release; no binary runtime dependency is embedded in ForNow.

## Commands Run

- `scripts/bootstrap.sh`
- `scripts/format.sh`
- `scripts/build.sh`
- `CONFIGURATION=Release scripts/build.sh`
- `scripts/test.sh`
- `xcodebuild -scheme ForNowPerformanceTests ... build-for-testing`
- direct application launch plus window screenshot capture
- repeat-generation content-hash comparison
- `git diff --check`

## Automated Test Results

- Debug build: passed.
- Release build without signing: passed for arm64 and x86_64; the final app
  executable is a universal binary containing both architectures.
- `SmokeTests.testApplicationEnvironmentUsesForNowName`: passed.
- Performance test target `build-for-testing`: passed.
- Project generation determinism: passed; consecutive project-tree hashes were
  both `aa320012d64785b6f1495b39c7bfd9e24e73d7767c787bd60e55be5643f5c3af`.
- Package lock: GRDB 7.11.1 and KeyboardShortcuts 1.10.0 revisions recorded in
  `ForNow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Manual Test Results

- The Debug application launched on macOS 26.6 and presented one resizable
  scratchpad window with the editor focused on appearance.
- Screenshot inspected at `/tmp/fornow-step01.png`; no blank canvas, clipping,
  overlap, or offscreen placement was observed.
- No AntiNote source, branding, icon, screenshot, or proprietary asset appears
  in the application or package source trees.

## Deviations And Open Questions

- XcodeGen 2.46.0 was the latest stable release at execution time. The project
  remains pinned to the documented 2.45.4 baseline and verifies the release
  archive SHA-256 before use.
- Architecture research named KeyboardShortcuts 2.x/2.4.0, but the upstream
  stable release line was 1.x and the newest tag was 1.10.0. The project pins
  1.10.0 and corrects the architecture version statement.
- The development Mac has no Apple Development signing identity. On macOS 26.6,
  Apple System Policy kills an ad-hoc-signed UI Test Runner before XCTest can
  connect. The unit-test gate remains runnable; `scripts/test-ui.sh` reports the
  missing prerequisite immediately, and the UI target is retained for a signed
  machine or CI environment.
