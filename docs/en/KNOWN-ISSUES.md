# Known issues and test status

[На русском](../ru/KNOWN-ISSUES.md) / [Back to README](../../README.md)

## Hardware testing scope

Xbox Series X|S (`045e:0b12`) is tested in-game on both `MT-TEST 2026.05.15` builds (`gamma-monolith` and `gamma-monolith-dlss`).

DualSense, DualShock 4, Xbox One, Elite Series 2, Xbox 360, Switch Pro, Steam Deck, and 8BitDo (in X-Input mode) use SDL3 `3.4.18` native mappings and pass our offline test suite, awaiting live reports on physical hardware. On Nintendo layouts, controls stay positional (bottom button confirms/jumps, right button cancels/crouches) while on-screen labels match Nintendo's `B`/`A`/`Y`/`X` markings.

Generic DirectInput USB gamepads (Class C) depend on OS drivers and require manual mapping through `Options -> Controls -> Gamepad -> Other Settings -> Class C Setup Wizard`.

## Vanilla S.T.A.L.K.E.R. Anomaly 1.5.2 / 1.5.3

The `anomaly-vanilla` build (`PORT-A`) passes offline automated tests (`luatest` and `verify.ps1`), using standard `reload_weapon()` and the built-in `gp_wheel_arm` wheel, and awaits full in-game playtesting. Do not copy G.A.M.M.A. `.exe` files into a clean Anomaly install.

## MO2 order and external mappers

Keep `446- Quick Action Wheel - HarukaSai` and `G.A.M.M.A. Quick Action Wheel Balance` enabled above this mod in MO2, and keep `GAMMA Gamepad & Tactical UI` at the bottom of the load order. Leaving Steam Input, DS4Windows (on USB), reWASD, or x360ce running causes duplicate button presses.

## DLSS edition notes

Frame Generation in `gamma-monolith-dlss` requires a DirectX 12 GPU, Windows HAGS enabled, and both MSAA and VSync turned off in video settings. When Frame Generation is active, `r__framelimit` already caps the final displayed framerate including generated frames.

## Script error recovery and ultrawide HUDs

Non-fatal Lua UI errors are caught by `gp_safe_guard` and written to `<Anomaly>\appdata\gamepad_last_error.log` so a broken third-party UI hook does not crash a raid. If a custom HUD mod shifts prompt positions on an ultrawide monitor, enable `UI Layout Editor` in `Other Settings` and press `F10` in-game to nudge elements.
