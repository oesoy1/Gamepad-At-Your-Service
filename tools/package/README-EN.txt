================================================================================
GAMEPAD AT YOUR SERVICE — NATIVE GAMEPAD CONTROLS & TACTICAL UI
Installation, Verification, Update & Clean Uninstall Guide (v0.2.2)
================================================================================

OVERVIEW & EDITIONS
--------------------------------------------------------------------------------
This mod adds true native analog gamepad support (powered by SDL3, zero WASD or
mouse-emulation hacks), aim assist, radial quick-action wheel, full controller
navigation for inventory, PDA, workshops, MCM, and dialogs, virtual on-screen
keyboard, button remapping, and seamless switching with keyboard/mouse.

Two primary editions for S.T.A.L.K.E.R. G.A.M.M.A. (X-Ray Monolith engine):
  1) gamma-monolith (recommended for most players):
     Standard S.T.A.L.K.E.R. G.A.M.M.A. on DirectX 11 (bundles
     AnomalyDX11AVX.exe, fallback AnomalyDX11.exe, and SDL3.dll).
  2) gamma-monolith-dlss:
     Edition with DX12 bridge, DLSS, FSR 3, and Frame Generation (bundles
     AnomalyDX12-DLSS.exe, SDL3.dll, DLSS/FSR/Streamline/D3D12 runtime DLLs,
     and the DLSS menu + shader compatibility patch).


================================================================================
PACKAGE LAYOUT (READY FOR DIRECT IMPORT IN MOD ORGANIZER 2)
================================================================================
  GAMMA Gamepad & Tactical UI\
      meta.ini                   - Mod Organizer 2 metadata
      gamedata\...               - Lua scripts, RU/EN/UK strings, UI textures
      engine_files\              - Engine binaries & DLLs for <Anomaly>\bin\
          engine_helper.ps1      - Automated installer & rollback helper script
      tools\
          verify.ps1             - Strictly read-only installation verifier
      Install_Engine.cmd         - One-click engine installer (English)
      Restore_Original.cmd       - One-click original engine rollback (English)
      Установить_движок.cmd      - One-click engine installer (Russian)
      Вернуть_оригинал.cmd       - One-click original engine rollback (Russian)
      README-EN.txt              - This guide in English
      README-RU.txt              - Guide in Russian
      THIRD-PARTY-NOTICES.txt    - Third-party software attributions
      THIRD_PARTY\               - Full third-party license texts
      manifest.sha256.json       - SHA-256 manifest of every file in the archive
      SHA256SUMS.txt             - Plain-text SHA-256 checksum list


================================================================================
INSTALLING IN G.A.M.M.A. (2 STEPS)
================================================================================
Close the game completely before installing.

Step 1. Import the .zip archive directly into Mod Organizer 2:
  1. Drag the downloaded .zip into Mod Organizer 2 (or click "Install a new
     mod from an archive") and confirm the mod name "GAMMA Gamepad & Tactical UI".
  2. Enable the checkbox next to the mod in MO2's left pane and move it to the
     VERY BOTTOM of the load order (right above G.A.M.M.A. End of List_separator).
  3. Keep "446- Quick Action Wheel - HarukaSai" and "G.A.M.M.A. Quick Action
     Wheel Balance" enabled above it — our mod adds gamepad controls to them.

Step 2. Install engine files in one click:
  1. Right-click "GAMMA Gamepad & Tactical UI" in MO2 and choose
     "Open in Explorer".
  2. Double-click "Install_Engine.cmd" (or "Установить_движок.cmd").
  3. The helper automatically detects your <Anomaly> folder from MO2's
     ModOrganizer.ini, backs up original files to <Anomaly>\bin\_gamepad_backup\,
     and copies the modded engine files with SHA-256 verification.
  4. For the gamma-monolith-dlss edition: set MO2's launch executable to
     <Anomaly>\bin\AnomalyDX12-DLSS.exe. If you enable Frame Generation, turn on
     Hardware-Accelerated GPU Scheduling (HAGS) in Windows Graphics Settings.
     Note that r__framelimit counts generated frames too, so set it to your
     desired final display FPS (or 0 for uncapped).

Controller note:
  Disable Steam Input (Properties -> Controller -> Disable Steam Input) and
  close DS4Windows, reWASD, or x360ce over USB or Xbox Wireless Adapter so
  buttons do not register twice.

Standalone Anomaly without MO2:
  Copy gamedata\ into your Anomaly\ root folder and run "Install_Engine.cmd";
  when prompted, choose your Anomaly root folder (the folder containing bin\).


================================================================================
OPTIONAL: READ-ONLY VERIFICATION
================================================================================
tools\verify.ps1 is STRICTLY READ-ONLY (never modifies your game or MO2 files)
and checks engine binaries, backup state, mod files, and MO2 load order.
Run from inside the installed mod folder:

  powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\verify.ps1"

Exit codes: 0 = PASS, 2 = WARN, 1 = FAIL (prints exact fix steps).


================================================================================
AFTER UPDATING G.A.M.M.A. OR UPDATING THE MOD
================================================================================
- If G.A.M.M.A. Launcher overwrites Anomaly\bin\AnomalyDX11AVX.exe with a new
  stock build, the game will NOT crash: startup diagnostics shows one clear
  notice and falls back to keyboard & mouse.
- Run "Install_Engine.cmd" inside the mod folder again: it updates the backup
  with the new stock binary and restores gamepad engine support.
- Re-running "Install_Engine.cmd" NEVER overwrites your clean stock backup with
  modded binaries.
- Your bindings in <Anomaly>\appdata\gamepad\profile.ltx remain untouched across
  both mod updates and G.A.M.M.A. updates.


================================================================================
CLEAN UNINSTALL & ROLLBACK (SAVE-SAFE)
================================================================================
Saves (.scop / .scoc) contain no mod data and load normally after removal.

1. Right-click the mod in MO2 -> "Open in Explorer" and run
   "Restore_Original.cmd" (or "Вернуть_оригинал.cmd"). It restores every
   original file from _gamepad_backup\, deletes files added by the mod, and
   cleans up _gamepad_backup\.
2. Uncheck or remove "GAMMA Gamepad & Tactical UI" in MO2.
3. Optionally delete <Anomaly>\appdata\gamepad\.
================================================================================
