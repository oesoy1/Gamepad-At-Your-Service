# Installation and uninstall

[На русском](../ru/INSTALL.md) / [Back to README](../../README.md)

Download one of the `.zip` archives from [Releases](https://github.com/oesoy1/Gamepad-At-Your-Service/releases):
- `Gamepad-At-Your-Service-vX.Y.Z-GAMMA-Standard.zip` for standard S.T.A.L.K.E.R. G.A.M.M.A. (`AnomalyDX11AVX.exe`, `AnomalyDX11.exe`, `SDL3.dll`). Recommended for most players.
- `Gamepad-At-Your-Service-vX.Y.Z-GAMMA-DLSS-Optional.zip` for G.A.M.M.A. with the DX12 bridge, DLSS, Frame Generation, and FSR 3 (`AnomalyDX12-DLSS.exe`, `SDL3.dll`, DLSS/FSR/Streamline/D3D12 runtime DLLs, DLSS menu, and shader patch). This package is self-contained and does not require a separate DLSS mod (disable any older standalone DLSS mod before installing). If you turn on Frame Generation, enable Hardware-Accelerated GPU Scheduling (HAGS) in Windows graphics settings and turn off MSAA and VSync in video options.

Close the game completely before installing or updating engine files.

## Installing in G.A.M.M.A.

1. Drag the downloaded `.zip` directly into Mod Organizer 2 (or click `Install a new mod from an archive`) and confirm the mod name `GAMMA Gamepad & Tactical UI`. Enable the mod and move it to the bottom of the left pane right above `G.A.M.M.A. End of List_separator`. Leave `446- Quick Action Wheel - HarukaSai` and `G.A.M.M.A. Quick Action Wheel Balance` enabled above it.
2. Right-click `GAMMA Gamepad & Tactical UI` in MO2, choose `Open in Explorer`, and double-click `Install_Engine.cmd` (or `Установить_движок.cmd`). The helper reads `ModOrganizer.ini` automatically to find `<Anomaly>`, backs up existing files into `<Anomaly>\bin\_gamepad_backup\`, and installs the gamepad binaries with SHA-256 verification. For the `gamma-monolith-dlss` edition, set MO2's launch executable to `<Anomaly>\bin\AnomalyDX12-DLSS.exe`.
3. Disable Steam Input (`Properties -> Controller -> Disable Steam Input`) and close DS4Windows, reWASD, or x360ce when playing over USB or the Xbox Wireless Adapter so buttons do not register twice.

If you want to double-check paths, hashes, and MO2 order before starting the game, run the read-only verifier from inside the mod folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\verify.ps1"
```

After launching the game, open `Options -> Controls -> Gamepad -> Other Settings` to pick your `Dot Marks` button icons and test your sticks and triggers in `Button Test` (hold `B` for 1 second to close). In the Zone, press `LB + View` anytime to bring up the control reminder.

## After updating G.A.M.M.A.

Running `Install / Update` in `G.A.M.M.A. Launcher` overwrites `<Anomaly>\bin\AnomalyDX11AVX.exe` with the upstream binary. Your controller profile (`appdata\gamepad\profile.ltx`) and saves stay intact. Open `GAMMA Gamepad & Tactical UI` in Explorer and run `Install_Engine.cmd` again: it refreshes `<Anomaly>\bin\_gamepad_backup\` with the new stock `.exe` and reinstalls the gamepad executable. Re-running `Install_Engine.cmd` never overwrites your saved stock backup with modded files.

## Uninstalling

1. Open `GAMMA Gamepad & Tactical UI` in Explorer from MO2 and run `Restore_Original.cmd` (or `Вернуть_оригинал.cmd`). It restores your original files from `<Anomaly>\bin\_gamepad_backup\`, deletes files added by the mod, and removes `_gamepad_backup\`.
2. Uncheck or delete `GAMMA Gamepad & Tactical UI` in MO2.
3. Optionally delete `<Anomaly>\appdata\gamepad\` and `<Anomaly>\appdata\gamepad_last_error.log`.

Save files (`.scop` and `.scoc`) contain no mod data and load normally after removal.
