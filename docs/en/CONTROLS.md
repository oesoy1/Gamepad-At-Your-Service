# Controller button map

[На русском](../ru/CONTROLS.md) / [Back to README](../../README.md)

Default bindings from `GamepadBindings.cpp` and `gamedata/scripts/`. You can rebind world and menu controls in `Options -> Controls -> Gamepad`.

Gesture shorthand:
- Tap: press and release quickly (`< 300 ms`).
- Hold: keep the button down for `250-300 ms` (`~1 s` on destructive actions with a hold ring).
- Chord (`A + B`): hold the modifier (`LT` or `LB`) first, then press the second button.

## On foot and in combat

| Input | Tap | Hold | Chord |
|---|---|---|---|
| `LS` (left stick) | 360-degree walk/jog (steers within 60 degrees while sprinting; easing below 70% exits sprint) | - | - |
| `L3` (click `LS`) | Start sprint | - | - |
| `RS` (right stick) | Camera look and aim | - | - |
| `R3` (click `RS`) | Lower or raise weapon | - | - |
| `LT` | Aim down sights (ADS) | Keep aiming | `LT + LB` lean left, `LT + RB` lean right |
| `RT` | Fire / throw bolt or grenade | Auto fire | - |
| `A` | Jump | - | - |
| `B` | Crouch | Low crouch (`300 ms`) | `LB + B` freelook |
| `X` | Interact / reload / unjam | Check magazine (`AmmoCheck`) | `LT + X` force reload |
| `Y` | Next weapon / holster | Weapon selector fan (`RS` picks slot) | `LB + Y` quick grenade |
| `LB` | Quick slot / bolt | Quick Action Wheel (`250 ms`) | Modifier for `B`, `Y`, `View`, `D-Pad` |
| `RB` | Quick melee strike | Draw knife or binoculars (`300 ms`) | - |
| `D-Pad Up` | Headlamp | Night vision (`300 ms`) | `LT + Up`: zoom in / Free Zoom |
| `D-Pad Left` | Detector | Throw bolt (`300 ms`) | `LB + D-Pad`: pinned quick slots |
| `D-Pad Right` | Fire mode | Underbarrel launcher (`300 ms`) | `LB + D-Pad`: pinned quick slots |
| `D-Pad Down` | Next ammo type | Ammo wheel (`300 ms`) | `LT + Down`: zoom out |
| `Menu` (Start) | Pause menu | - | - |
| `View` (Back) | Open or close inventory | Fullscreen 2D PDA (`300 ms`) | `LB + View`: control reminder |

Actions available in the Quick Action Wheel (or via manual rebind) that have no dedicated default button: 3D handheld PDA (`Pda3DToggle`), wipe mask (`MaskClean`), and drop-mag fast reload (`FastReload`).

## Inventory, loot, trade, and technician

| Input | Inventory | Loot / stash | Trade | Technician |
|---|---|---|---|---|
| `LS` / `D-Pad` | Move across item cells | Move across item cells | Move across item cells | Navigate items, parts, upgrade tree |
| `RS` (tilt / click) | Scroll descriptions; click toggles 100% stats | Same | Same | Scroll; click toggles 100% stats |
| `View` | Switch Equipment / Backpack | Cycle Container, Equipment, Backpack | Cycle Trader, Equipment, Backpack | Cycle Backpack, Equipment, Technician |
| `LT` / `RT` | Category tabs | Left/right category tabs | Category tabs | Category tabs |
| `A` | Use / equip (`Hold A`: full stack) | Take (`Hold A`: full stack) | Move to cart (`Hold A`: full stack) | Select item or apply upgrade |
| `Y` | Quick move / equip | Quick transfer | Move to/from cart | Toggle upgrade details |
| `X` | Context menu (`Hold X`: disassemble) | Same | Context menu (`Hold X`: secondary action) | Context action |
| `LB` | - | Tap: Take All; Hold: Auto-Looter | Buy cart | - |
| `RB` | Toggle medicine filter | Put All | Sell cart | - |
| `L3` | — | Rename a personal stash | Clear non-empty carts | — |
| `B` / `Menu` | Close menu or inventory | Same | Same | Back / close |

## 2D and 3D PDA

| Input | 2D PDA (`Hold View`) | 3D handheld PDA |
|---|---|---|
| `LT` / `RT` | Switch PDA tabs (Tasks, Relations, Contacts, Stats, Messages, Guide, Radio) | - |
| `LS` / `L3` | Move map or cursor; `L3` centers on player | - |
| `LB` / `RB` | Zoom map out / in (or cycle task filters) | - |
| `View` | Tap: Tasks list; Hold: Map legend | - |
| `X` | Open map marker / `PAW` menu (`Hold X` on delete removes custom pin) | - |
| `Y` | Toggle map icon filters | Toggle interactive cursor |
| `A` / `B` | Confirm / close | `B` lowers 3D PDA |

## Quick Action Wheel and weapon fan

Hold `LB` (`250 ms`) to open HarukaSai's Quick Action Wheel. Tilt `RS` to a sector and release `LB` (or press `A`). `LT`/`RT` switch wheel tabs, `D-Pad` uses a pinned slot when `RS` is centered or pins the active sector when `RS` is tilted, and `B` cancels.

Hold `Y` (`300 ms`) to open the weapon selector fan, tilt `RS` to a weapon slot, and release `Y`.

## Workshop, hideout, and other Zone screens

| Screen | Controls |
|---|---|
| Workshop (`UIWorkshop`) | `LT`/`RT` switch State, Repair, Upgrade, Craft tabs; `LS`/`D-Pad` + `A` pick items, parts, or recipes; `LB`/`RB` switch toolkits or filters; `View` toggles recipe instructions; `Hold X` (`1 s`) runs repair, upgrade, or craft; `Y` toggles details; `B` steps back. |
| Hideout placement | `LS` moves on XZ, `RS` rotates and changes Y height (`LB`/`RB` also rotate), hold `LT` for `0.1x` fine movement, `A` places, `X` toggles collision, `Y` snaps to axis, `View` cycles modes, `B` cancels. |
| Placed furniture | Placed workshop: `X` open, `Y` stash, `Hold B` (`1.8 s`) pick up. Lamp / radio / piano: `A` toggle or station, `LB`/`RB` volume, `Y` fuel or play/stop, `Hold X` (`1 s`) pick up. Trading laptop: `A` trade, `X` refresh. |
| Field windows & sleep | Mutant loot, cooking, field repair, melter, sleep: `LS`/`D-Pad` + `A` select, `Hold X` confirm/loot/cook/sleep, `B` close. Camp stove: `X` cook, `Y` stash. |
| NPC dialogs & 21-point | Dialogs: `D-Pad`/`LS` + `A` speak, `X` open trade, `B` leave. 21-point cards: `LS`/`D-Pad` + `A` bet/hit/stand, `Hold X` lock bet, `B` exit. |
| Companions, skills, `MCM` | Companion inventory & squad wheel, `Experience` / `HarukaSkills` (`View` jumps between them, `Hold X` buys perk), laser dialog, `BHS`, color grading, numpad, stash creation, recipes, `NPE` cards, and all 14 `UI_MCM` widget types (`View` swaps tree and options). Press `R3` on any unsupported custom mod window to toggle the analog mouse cursor. |

## On-screen keyboard (`EN` / `RU`)

Opens automatically when activating any text box (save name, stash name, `PAW` pin, character name, `MCM` filter): `LS`/`D-Pad` move across keys and presets, `A` types, `X` deletes (hold to repeat), `Y` inserts space, `L3`/`LT` toggle uppercase, `R3`/`LB`/`RB` switch `EN QWERTY` and `RU ЙЦУКЕН`, `Menu` confirms, `B` cancels.

## Remapping and settings

Open `Options -> Controls -> Gamepad` (`Hold X` for 1 second on any tab resets that tab):
- `World` and `Inventory & Menus`: overview and direct slot bindings.
- `Aiming`: X/Y sensitivity, ADS multiplier, turn boost, response curve (`Linear`, `Smooth`, `S-Curve`), deadzones, and aim assist presets (`Off`, `Low`, `Medium`, `High`) plus slowdown/pull sliders.
- `Other Settings`: five vibration sliders, `Dot Marks` icon family and style, crouch/sprint hold vs. toggle, cursor speed and toggle bind, `Assign Buttons` (18-slot visual remapper with a `Wheel on Y` preset), `Button Test` (19 live indicators), stick calibration, `Class C Setup Wizard`, and the `F10` UI layout editor toggle.
