# Crash report tool

[На русском](../ru/CRASH-REPORT.md) / [Back to README](../../README.md)

If the game crashes or a controller screen misbehaves, you can pack the relevant logs with one click using our read-only script in `tools\crashreport\`.

## One-click collection

1. Open `tools\crashreport\` and double-click `Собрать_отчёт.cmd`. The script only reads files and never modifies your game or MO2 folder.
2. Wait for the `DONE` message. A `.zip` archive is saved to your `Documents` folder:
   ```text
   Documents\GAMMA-Gamepad-report-YYYYMMDD-HHmmss.zip
   ```
3. Attach that `.zip` to your bug report along with your controller model, connection type (USB, Bluetooth, Xbox adapter), game edition (`gamma-monolith` or `gamma-monolith-dlss`), and what you were doing right before the issue.

If your Anomaly or MO2 folders are in custom locations that were not detected automatically, pass them explicitly:

```bat
Собрать_отчёт.cmd -GameRoot "D:\Games\Anomaly" -Mo2Root "D:\Games\GAMMA"
```

## What goes into the zip (and privacy scrubbing)

The archive collects `appdata\logs\xray_*.log`, the latest `.mdmp` crash minidump (if it fits inside the 25 MB archive cap; pass `-IncludeMinidump:$false` to skip it), `gamepad_last_error.log`, `appdata\gamepad\profile.ltx`, `user.ltx`, your MO2 `modlist.txt`, and SHA-256 hashes of the `.exe` and `.script` files.

Before zipping, `collect.ps1` strips your Windows username, computer name, and `C:\Users\<USER>\...` paths from logs and filenames, replacing them with `<USER>` and `<PC>`.
