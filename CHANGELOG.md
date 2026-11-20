# Changelog

## v0.2.2 (preview on `MT-TEST 2026.05.15`)

Engine builds:
- `gamma-monolith` (`gp-release-mt-may`): ported onto the standard G.A.M.M.A. `MT-TEST 2026.05.15` multithreaded DX11 engine (`AnomalyDX11AVX.exe` and `AnomalyDX11.exe`) with SDL3 `3.4.18`. Keyboard and mouse input is unchanged when no controller is active.
- `gamma-monolith-dlss` (`gp-release-mt-may-dlss`): same `MT-TEST 2026.05.15` base paired with `brodrigz`'s DX12 presentation bridge for NVIDIA DLSS, Streamline Frame Generation, and AMD FSR 3 (`AnomalyDX12-DLSS.exe`).

November 20 preview refresh:
- Open a companion's inventory from dialogue or from the Quick Action Wheel.
- Choose additional device actions in the wheel settings and turn the on-screen keyboard on or off.
- Fixed crashes when closing certain settings menus and drop-downs, and improved controller handling in the main menu and hideout.
- Fixed a DX12 presentation bridge crash when switching out of fullscreen with Alt+Tab.

Recent fixes (`FIX-LIVE5` through `FIX-LIVE7`):
- Easing the left stick below 70% physical tilt for 150 ms drops out of sprint back to a jog or walk without clicking `L3` again.
- Added a right-stick neutral barrier (`< 0.3` deflection) when closing the Quick Action Wheel, weapon fan, or modal windows so the camera does not snap if the stick was held during selection.
- Pressing `D-Pad` inside an open Quick Action Wheel triggers pinned quick slots when `RS` is centered, and pins a slot when `RS` points at a wheel sector.
- Deferred lazy UI creation in `gp_workshop.script` to the outermost `CUIWindow::Update` call, fixing iterator invalidation and `Busy Hands` errors on the Craft tab.
- Moved `gp_icons` Lua queries off the render thread (`UIMessageBox` and `OSK`), matched dual-hand HUD animation speed to stick tilt, and added a null check for early NPC spawns in `CInventoryOwner::load`.

## v0.2.0

Initial feature-complete build:
- 360-degree analog movement, `L3` sprint steering within 60 degrees, three right-stick response curves, deadzones, and optional `RayQuery` line-of-sight aim assist (disabled in optics above 4x).
- Controller navigation for inventory, loot, trade, and technician (`gp_inv_rework`).
- Controller support for 2D/3D PDA (`PAW` pins), HarukaSai Quick Action Wheel, weapon fan, four-tab workshop, field cooking/repair, mutant loot, sleep, 21-point cards, NPC dialogs, character creation, hideout furniture, companions, `Experience`/`HarukaSkills`, `BHS`, all 14 `UI_MCM` widget types, and an `EN`/`RU` on-screen keyboard.
- Native four-tab `Options -> Controls -> Gamepad` menu, 18-slot button remapper, `Dot Marks` icon sets, 19-indicator button tester, Class C setup wizard, and five vibration channels.
- Separate profile storage in `appdata\gamepad\profile.ltx` (nothing saved in `.scop`/`.scoc`) and `xpcall` error guards (`gp_safe_guard`, `gp_failover`).
