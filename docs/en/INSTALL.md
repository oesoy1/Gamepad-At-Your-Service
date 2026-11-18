# Installation and uninstall

[На русском](../ru/INSTALL.md) / [Back to README](../../README.md)

Download one of the `.zip` archives from [Releases](../../../releases):
- `Gamepad-At-Your-Service-vX.Y.Z-gamma-monolith.zip` for standard S.T.A.L.K.E.R. G.A.M.M.A. (`AnomalyDX11AVX.exe` / `AnomalyDX11.exe`).
- `Gamepad-At-Your-Service-vX.Y.Z-gamma-monolith-dlss.zip` for G.A.M.M.A. with the DX12 bridge, DLSS, Frame Generation, and FSR 3 (`AnomalyDX12-DLSS.exe`). If you turn on Frame Generation, enable Hardware-Accelerated GPU Scheduling (HAGS) in Windows graphics settings and set `r__framelimit` to twice your target FPS.

Close the game and Mod Organizer 2 before copying files, and keep a backup of your `<Anomaly>\bin\` folder.

## Installing in G.A.M.M.A.

1. Back up your original `AnomalyDX11AVX.exe`, `AnomalyDX11.exe` (and `SDL3.dll`, if present) from `<Anomaly>\bin\`, then copy everything from `1_Copy_To_Anomaly_bin\` into `<Anomaly>\bin\`. For the `gamma-monolith-dlss` edition, point your MO2 launch shortcut to `<Anomaly>\bin\AnomalyDX12-DLSS.exe`.
2. Copy `GAMMA Gamepad & Tactical UI` from `2_Install_In_MO2_mods\` into `<GAMMA>\mods\` (or install it as an archive in MO2). Press `F5` in MO2, enable `GAMMA Gamepad & Tactical UI`, and move it to the bottom of the load order right above `G.A.M.M.A. End of List_separator`. Leave `446- Quick Action Wheel - HarukaSai` and `G.A.M.M.A. Quick Action Wheel Balance` enabled above it.
3. Disable Steam Input (`Properties -> Controller -> Disable Steam Input`) and close DS4Windows, reWASD, or x360ce when playing over USB or the Xbox Wireless Adapter so buttons do not register twice.

If you want to double-check paths and MO2 order before starting the game, run the read-only verifier:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "3_Verify_Installation_ReadOnly\verify.ps1" -AnomalyRoot "D:\Anomaly" -Mo2Root "D:\GAMMA"
```

After launching the game, open `Options -> Controls -> Gamepad -> Other Settings` to pick your `Dot Marks` button icons and test your sticks and triggers in `Button Test` (hold `B` for 1 second to close). In the Zone, press `LB + View` anytime to bring up the control reminder.

## After updating G.A.M.M.A.

Running `Install / Update` in `G.A.M.M.A. Launcher` overwrites `<Anomaly>\bin\AnomalyDX11AVX.exe` with the upstream binary. Your controller profile (`appdata\gamepad\profile.ltx`) and saves stay intact; just copy `1_Copy_To_Anomaly_bin\` back into `<Anomaly>\bin\`.

## Uninstalling

1. Uncheck or delete `GAMMA Gamepad & Tactical UI` in MO2.
2. Restore your backed-up `.exe` inside `<Anomaly>\bin\`.
3. Optionally delete `<Anomaly>\appdata\gamepad\` and `<Anomaly>\appdata\gamepad_last_error.log`.

Save files (`.scop` and `.scoc`) contain no mod data and load normally after removal.
