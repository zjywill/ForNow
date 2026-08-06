# Window Spike Manual Matrix

Date: 2026-08-03

## Support Contract

| Dimension | Supported behavior |
|---|---|
| Single or dual display | All modes target the pointer's current display and remain inside `visibleFrame`. |
| Same or different Space | Standard moves to the active ordinary Space; menu-style panels join all Spaces. |
| Windowed foreground app | All modes show and focus the editor. |
| Full-screen foreground app | Menu-style panels overlay as auxiliaries; standard mode does not claim overlay behavior. |
| Standard, pseudo menu, dropdown | All retain one draft model and one visible window. |
| Pin off/on | Standard changes normal/floating level; menu-style full-screen capability is unchanged. |
| Auto-hide off/on | Auto-hide requires inactive, unpinned, visible, and no suspension. |
| Owned panel none/settings/save/permission | Every owned panel suspends auto-hide until close/completion. |
| Dock/Menu/Both/Neither | All four retain global invocation; Neither retains commands in the window. |
| Stage Manager off/on | Collection and focus policy is unchanged; manual confirmation is required. |

## Executed Cells

| Test ID | Environment | Modes / state | Result | Evidence |
|---|---|---|---|---|
| `MT-WIN-001` | macOS 26.6, one display, Finder foreground | standard, unpinned, auto-hide off | PASS | Option-A hid with flush, then showed the same window; app and editor became focused. |
| `MT-WIN-002` | macOS 26.6, one display | all modes; Dock/Menu/Both/Neither | PASS | Exact source survived standard -> floating -> dropdown. The actual dropdown frame followed configured dimensions down to 360 by 280. Dock and status-item surfaces matched all four presence modes; Neither retained every in-app command. |
| `MT-WIN-003` | macOS 26.6 real UI plus automated state matrix | Command-P; pin; auto-hide; settings/save/permission suspensions | PASS | Command-P changed CoreGraphics layer 0 -> 3 -> 0. Every owned panel kept the main window visible while Finder was active; release then flushed and hid. `WindowSpikeTests` also passed 10/10. |
| `MT-WIN-004A` | one display, windowed app | standard | PASS | Frame was fully visible; screenshot captured. |
| `MT-WIN-004B` | synthetic dual display with negative origin | all placement styles | PASS | Oversized dropdowns clamped inside both visible frames. |
| `MT-WIN-004C` | physical dual display | all modes | PENDING | No simultaneous second display was available. Phase 1 continuation was owner-approved on 2026-08-04 without treating this cell as passed. |
| `MT-WIN-004D` | two real macOS Spaces | standard | PASS | Created Desktop 2, switched away from the existing window, and invoked twice. Standard moved to the active ordinary Space at 760 by 620, retained `SPACE-STANDARD-20260803` plus CJK source, and exposed `AXFocused=true`. |
| `MT-WIN-004E` | two real macOS Spaces | floating/dropdown | PASS | CoreGraphics assigned both panels to Space IDs 1 and 59. Floating remained on-screen at layer 3 and dropdown at layer 25 after switching Desktops; Option-A restored exact source and editor focus in each Space. |
| `MT-WIN-004F` | Safari `about:blank`, `AXFullScreen=true`, Space ID 70 | standard/floating/dropdown | PASS | Standard correctly did not claim the Safari full-screen Space. Key-capable nonactivating floating and dropdown panels joined Space 70, overlaid Safari at layers 3 and 25, retained 36 UTF-16 source units, and reported `AXFocused=true`. See `assets/window-spike-fullscreen-dropdown.png`. |
| `MT-WIN-004G` | Stage Manager off/on | all modes | PASS | With `GloballyEnabled=0` and then `1`, all three modes restored the exact source and focused editor from Finder/Safari foreground. Twenty Stage Manager-on global toggles left one visible standard window. The original off setting was restored. |
| `MT-WIN-004H` | macOS 26.6, Finder foreground | settings/save/permission open; auto-hide on | PASS | Each owned panel held one suspension. Focus loss left the main window visible; closing/completing the panel released the suspension and allowed flush-before-hide. |
| `MT-WIN-005` | macOS 26.6, Finder foreground | Command-O, Command-W, global and status-item toggles | PASS | Every path flushed before hide/close. Option-A restored exact source and focus; 20 repeated global toggles left one visible window. |

## OS-Version Diagnostic Matrix

| OS | Candidate | Expected | Verification |
|---|---|---|---|
| macOS 15.0 | Option-A | Option-only workaround diagnostic; previous binding retained | Automated PASS |
| macOS 15.1 | Option-A | Option-only workaround diagnostic; previous binding retained | Automated policy equivalent to 15.0 |
| macOS 15.2+ | Option-A conflict | Generic conflict; previous binding retained | Automated PASS |
| macOS 26.6 | Option-A free | Registration succeeds | Manual PASS |
