================================================================================
GAMEPAD AT YOUR SERVICE — NATIVE GAMEPAD CONTROLS & TACTICAL UI
Installation, Verification, Update & Clean Uninstall Guide (v0.2.0)
================================================================================

OVERVIEW & TARGET COMPATIBILITY
--------------------------------------------------------------------------------
This mod adds true native analog gamepad support (powered by SDL3, zero WASD or
mouse-emulation hacks), aim assist, radial quick-action wheel, full controller
navigation for inventory, PDA, workshops, and dialogs, virtual on-screen
keyboard, in-game button remapping, and seamless instant switching between
gamepad and keyboard/mouse.

PRIMARY TARGETS (gamma-monolith / anomaly-vanilla packages):
  1) Original S.T.A.L.K.E.R. G.A.M.M.A. (themrdemonized X-Ray Monolith engine,
     DirectX 11: AnomalyDX11AVX.exe / AnomalyDX11.exe).
  2) Original vanilla S.T.A.L.K.E.R. Anomaly 1.5.2 / 1.5.3 (DirectX 11;
     offline automated checks passed, awaiting live in-game verification).

OPTIONAL BUILD (separate pbr-dx12-optional archive):
  - Experimental PBR + DX12 bridge + DLSS fork (AnomalyDX12.exe). Standard
    G.A.M.M.A. and Anomaly players do NOT need the PBR archive — install the
    main gamma-monolith package instead!

Why is installation split into two steps?
Mod Organizer 2 (MO2) virtualizes only gamedata\ and cannot virtualize binaries
inside Anomaly\bin\. Therefore:
  - Step 1 copies the gamepad-enabled engine executable and SDL3.dll into
    Anomaly\bin\ (one-time manual copy).
  - Step 2 installs the UI scripts, strings, and textures as a normal MO2 mod
    (or into Anomaly\gamedata\ for standalone Anomaly without MO2).


================================================================================
PACKAGE LAYOUT
================================================================================
  1_Copy_To_Anomaly_bin\
      AnomalyDX11AVX.exe       — X-Ray Monolith executable with gamepad support
                                 (or AnomalyDX12.exe in optional PBR package)
      SDL3.dll                 — SDL3 runtime library (zlib license)
      THIRD-PARTY-NOTICES.txt  — open-source license attributions

  2_Install_In_MO2_mods\
      GAMMA Gamepad & Tactical UI\
          meta.ini
          gamedata\...         — Lua scripts, localization (EN/RU/UK), UI textures

  3_Verify_Installation_ReadOnly\
      verify.ps1               — strictly read-only installation checker
      manifest.sha256.json     — SHA-256 hashes of all packaged files
      SHA256SUMS.txt           — plain-text SHA-256 checksum list

  THIRD_PARTY\                 — full third-party license texts


================================================================================
STEP 1 (MANUAL, 1 MINUTE): UPDATE Anomaly\bin\
================================================================================
1. Close the game, Anomaly Launcher, and Mod Organizer 2 completely.
2. Open your base Anomaly\bin\ folder (for example: D:\Stalker\Anomaly\bin\).
3. BACK UP YOUR ORIGINAL EXECUTABLE FIRST:
   Rename the existing file (do NOT delete it):
     AnomalyDX11AVX.exe  --->  AnomalyDX11AVX.exe.orig
   (For the optional PBR package:
     AnomalyDX12.exe     --->  AnomalyDX12.exe.orig)
4. Copy the contents of 1_Copy_To_Anomaly_bin\ into Anomaly\bin\:
     - AnomalyDX11AVX.exe (or AnomalyDX12.exe for optional PBR)
     - SDL3.dll
     - THIRD-PARTY-NOTICES.txt


================================================================================
STEP 2 (VIA MO2 OR STANDALONE): INSTALL THE MOD & LOAD ORDER
================================================================================
Option A — G.A.M.M.A. or Anomaly with Mod Organizer 2 (recommended):
1. Copy "GAMMA Gamepad & Tactical UI" from 2_Install_In_MO2_mods\ into your
   MO2 mods\ folder (for example: D:\Stalker\GAMMA\mods\).
2. Open MO2 and press F5 (Refresh).
3. Move "GAMMA Gamepad & Tactical UI" to the VERY BOTTOM of the left pane
   (highest priority) and enable its checkbox.
4. Quick Action Wheel note for G.A.M.M.A.:
   Keep "446- Quick Action Wheel - HarukaSai" and "G.A.M.M.A. Quick Action
   Wheel Balance" ENABLED above our mod — our overlay automatically adds native
   gamepad support to them. On vanilla Anomaly (where Haru QAW is absent), our
   built-in radial wheel activates automatically.

Option B — Standalone Vanilla Anomaly without MO2:
1. Copy gamedata\ from "2_Install_In_MO2_mods\GAMMA Gamepad & Tactical UI\"
   into your Anomaly\ root folder (backing up any existing gamedata\ first).


================================================================================
STEP 3 (OPTIONAL): READ-ONLY INSTALLATION VERIFICATION
================================================================================
verify.ps1 is STRICTLY READ-ONLY (never modifies your game or MO2 files) and
verifies installed files against manifest.sha256.json:

  powershell -NoProfile -ExecutionPolicy Bypass `
    -File ".\3_Verify_Installation_ReadOnly\verify.ps1" `
    -AnomalyRoot "D:\Stalker\Anomaly" `
    -Mo2Root "D:\Stalker\GAMMA"

Exit codes:
  0 — installation verified (PASS)
  2 — playable with minor warnings (WARN)
  1 — installation error detected; clear fix instructions printed (FAIL)


================================================================================
STARTUP SELF-DIAGNOSTICS & SURVIVING G.A.M.M.A. UPDATES
================================================================================
On every launch, gp_compat runs automatic startup self-diagnostics:
- When you update G.A.M.M.A. via "G.A.M.M.A. Installer" (Install / Update),
  the updater downloads a fresh XRay-Monolith-MT.zip and overwrites
  Anomaly\bin\AnomalyDX11AVX.exe with the stock binary.
- Your game WILL NOT CRASH: self-diagnostics displays one clear message and
  safely disables gamepad hooks while keeping keyboard and mouse working.
- Simply repeat Step 1 (re-copy 1_Copy_To_Anomaly_bin\ into Anomaly\bin\) to
  re-enable gamepad support after a G.A.M.M.A. update.
- All gamepad bindings and settings are stored separately in:
    Anomaly\appdata\gamepad\profile.ltx
  They survive both mod updates and G.A.M.M.A. updates untouched, and your base
  Anomaly\appdata\user.ltx remains clean.


================================================================================
3-STEP CLEAN UNINSTALL / ROLLBACK (SAVE-SAFE)
================================================================================
Saves (.scop / .scoc) contain no hard dependencies on this mod — saves created
with the mod load cleanly in unmodded G.A.M.M.A. and Anomaly after removal.

1. Uncheck "GAMMA Gamepad & Tactical UI" in MO2.
2. In Anomaly\bin\, delete the modded AnomalyDX11AVX.exe and rename your backup
   back:
     AnomalyDX11AVX.exe.orig  --->  AnomalyDX11AVX.exe
   Delete SDL3.dll (unless another tool uses it).
3. Optionally delete Anomaly\appdata\gamepad\profile.ltx (or keep it for later).
================================================================================
