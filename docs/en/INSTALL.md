# Installation and uninstall

[На русском](../ru/INSTALL.md) / [Back to README](../../README.md)

Download one of the `.zip` archives from [Releases](https://github.com/oesoy1/Gamepad-At-Your-Service/releases):
- `Gamepad-At-Your-Service-vX.Y.Z-GAMMA-Standard.zip` for standard S.T.A.L.K.E.R. G.A.M.M.A. (`AnomalyDX11AVX.exe`, `AnomalyDX11.exe`, `SDL3.dll`). Recommended for most players.
- `Gamepad-At-Your-Service-vX.Y.Z-GAMMA-DLSS-Optional.zip` for G.A.M.M.A. with the DX12 bridge, DLSS, Frame Generation, and FSR 3 (`AnomalyDX12-DLSS.exe`, `SDL3.dll`, DLSS/FSR/Streamline/D3D12 runtime DLLs, DLSS menu, and shader patch). This package is self-contained and does not require a separate DLSS mod (disable any older standalone DLSS mod before installing). If you turn on Frame Generation, enable Hardware-Accelerated GPU Scheduling (HAGS) in Windows graphics settings and turn off MSAA and VSync in video options.

Close the game completely before installing or updating engine files.

## Installing in G.A.M.M.A.

1. Drag the downloaded `.zip` directly into Mod Organizer 2 (or click `Install a new mod from an archive`) and confirm the mod name `GAMMA Gamepad & Tactical UI`. Enable the mod and move it to the bottom of the left pane right above `G.A.M.M.A. End of List_separator`. Leave `446- Quick Action Wheel - HarukaSai` and `G.A.M.M.A. Quick Action Wheel Balance` enabled above it.
2. Right-click `GAMMA Gamepad & Tactical UI` in MO2, choose `Open in Explorer`, and double-click `Install_Engine.cmd` (or `Установить_движок.cmd`) or [copy the engine files manually](#manual-installation-without-cmd). The helper reads `ModOrganizer.ini` automatically to find `<Anomaly>`, backs up existing files into `<Anomaly>\bin\_gamepad_backup\`, and installs the gamepad binaries with SHA-256 verification. For the `gamma-monolith-dlss` edition, set MO2's launch executable to `<Anomaly>\bin\AnomalyDX12-DLSS.exe`.
3. Disable Steam Input (`Properties -> Controller -> Disable Steam Input`) and close DS4Windows, reWASD, or x360ce when playing over USB or the Xbox Wireless Adapter so buttons do not register twice.

If you want to double-check paths, hashes, and MO2 order before starting the game, run the read-only verifier from inside the mod folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\verify.ps1"
```

After launching the game, open `Options -> Controls -> Gamepad -> Other Settings` to pick your `Dot Marks` button icons and test your sticks and triggers in `Button Test` (hold `B` for 1 second to close). In the Zone, press `LB + View` anytime to bring up the control reminder.

## Manual installation without CMD

Import and enable the mod in MO2 as described above. You can do the rest in File Explorer and MO2.

1. Close the game. In MO2, open **Edit Executables** and check the **Binary** field for your usual G.A.M.M.A. launch entry. The folder containing that executable is the game's `bin` folder. Note the original path so you can restore it when uninstalling.
2. Right-click the installed mod in MO2, select **Open in Explorer**, and open `engine_files`. Before replacing anything, make a separate backup copy of the game's `bin` folder. The backup shows which files were already there and which the mod added.
3. Copy the files for your edition from `engine_files` into the game's `<Anomaly>\bin\` folder.

   | Archive | What to copy |
   |---|---|
   | **GAMMA Standard** | `AnomalyDX11AVX.exe`, `AnomalyDX11.exe`, and `SDL3.dll`. |
   | **GAMMA DLSS Optional** | Everything in `engine_files` except `engine_helper.ps1`. Copy the entire `D3D12` and `streamline` folders. |

   Copy the **contents** of `engine_files` directly into `bin`. Once you have a backup, confirm any prompts to replace existing files. For the DLSS edition, `D3D12` and `streamline` should sit next to `AnomalyDX12-DLSS.exe`.
4. Launch the game through MO2. For Standard, use your usual G.A.M.M.A. launch entry. For DLSS, set the **Binary** field to `<Anomaly>\bin\AnomalyDX12-DLSS.exe`.

### Uninstalling after a manual installation

Close the game. For each file you copied, check your `bin` backup. Restore any original file to the same path. Remove any file that was added by the mod. If you changed the **Binary** field for DLSS, restore the original executable path in MO2. Then disable the mod in MO2.

## After updating G.A.M.M.A.

Running `Install / Update` in `G.A.M.M.A. Launcher` overwrites `<Anomaly>\bin\AnomalyDX11AVX.exe` with the upstream binary. Your controller profile (`appdata\gamepad\profile.ltx`) and saves stay intact. Open `GAMMA Gamepad & Tactical UI` in Explorer and run `Install_Engine.cmd` again: it refreshes `<Anomaly>\bin\_gamepad_backup\` with the new stock `.exe` and reinstalls the gamepad executable. Re-running `Install_Engine.cmd` never overwrites your saved stock backup with modded files.

If you installed manually, back up any fresh original files restored by the launcher, then copy the engine files again using the [manual instructions](#manual-installation-without-cmd). Keep your earlier backup for the files the launcher did not replace.

## Uninstalling

If you copied the files in File Explorer, follow the [manual uninstall instructions](#uninstalling-after-a-manual-installation).

1. Open `GAMMA Gamepad & Tactical UI` in Explorer from MO2 and run `Restore_Original.cmd` (or `Вернуть_оригинал.cmd`). It restores your original files from `<Anomaly>\bin\_gamepad_backup\`, deletes files added by the mod, and removes `_gamepad_backup\`.
2. Uncheck or delete `GAMMA Gamepad & Tactical UI` in MO2.
3. Optionally delete `<Anomaly>\appdata\gamepad\` and `<Anomaly>\appdata\gamepad_last_error.log`.

Save files (`.scop` and `.scoc`) contain no mod data and load normally after removal.
