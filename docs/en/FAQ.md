# FAQ

[На русском](../ru/FAQ.md) / [Back to README](../../README.md)

### Buttons fire twice or the stick moves the Windows cursor
Another input mapper is active alongside SDL3. Disable Steam Input (`Properties -> Controller -> Disable Steam Input`) and exit reWASD, DS4Windows, and x360ce when playing on USB or the Xbox Wireless Adapter. Keep DS4Windows running (Xbox 360 mode with `Hide DS4 Controller` checked) only if an older Bluetooth adapter fails to expose DualShock 4 or DualSense HID packets to Windows.

### Controller stopped working after running G.A.M.M.A. Launcher
`G.A.M.M.A. Launcher` restores the stock `<Anomaly>\bin\AnomalyDX11AVX.exe` during updates. Open `GAMMA Gamepad & Tactical UI` in Explorer from MO2 and run `Install_Engine.cmd` (or `Установить_движок.cmd`) again. It updates the backup with the new stock `.exe` and restores gamepad support while keeping your `profile.ltx` settings intact.

### Can I install or remove the mod mid-playthrough?
Yes. Settings are stored in `<Anomaly>\appdata\gamepad\profile.ltx` and nothing is written to `.scop` or `.scoc` saves.

### How do I switch button icons to PlayStation, Nintendo, or Steam Deck?
Go to `Options -> Controls -> Gamepad -> Other Settings`, choose your `Gamepad Type` (`Auto`, `Xbox`, `PlayStation`, `Nintendo`, or `B1-B4` / Steam Deck), and pick a `Dot Marks` color theme (`Light`, `Dark`, `Colored`) and icon scale (`50%-150%`).

### Why don't Xbox Series triggers vibrate on their own on PC?
Windows XInput and Xbox Wireless Adapter drivers report `trig_rumble = 0` (`SDL_PROP_GAMEPAD_CAP_TRIGGER_RUMBLE_BOOLEAN = false`). When trigger motors are unavailable, weapon recoil uses the main grip motors.

### What does `L3` do in Trade and in a personal stash?
In Trade, `L3` clears non-empty carts. In a personal stash, it opens the rename prompt.

### Can I move the Quick Action Wheel to `Y`?
Open `Options -> Controls -> Gamepad -> Other Settings -> Assign Buttons` and click the `Wheel on Y` preset, or rebind any of the 18 slots manually. Holding `X` for 1 second on any gamepad settings tab resets that tab to defaults.

### What settings are needed for DLSS Frame Generation (`gamma-monolith-dlss`)?
Turn on Hardware-Accelerated GPU Scheduling (HAGS) in Windows graphics settings and keep MSAA and VSync turned off in video options. `r__framelimit` caps the final displayed framerate including generated frames (`0` disables the cap).
