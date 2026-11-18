# `gamedata/`

This folder holds the Mod Organizer 2 (`GAMMA Gamepad & Tactical UI`) files:

- `scripts/`: 48 Lua modules (`gp_*.script`, `ui_gp_*.script`, `ui_options_gamepad.script`, `modxml_gp_workshop.script`). Vanilla and G.A.M.M.A. scripts are left intact; our code attaches at runtime through callbacks, function wrappers (`gp_hooks_vanilla.script`), and DXML (`modxml_gp_workshop.script`).
- `configs/text/{eng,rus,ukr}/`: English, Russian, and Ukrainian string tables.
- `configs/ui/` and `textures/ui/`: XML layouts, font metrics (`gp_font_metrics.ltx`), and `Dot Marks` `.dds` button icon atlases.

## File encoding

Text files in this repository are stored in UTF-8 without BOM so Russian and Ukrainian strings are readable on GitHub. The X-Ray engine itself expects single-byte `Windows-1251` without BOM (`Windows-1252` for Western European folders). When you download a `.zip` from [Releases](../../releases) or run `tools/package/build_release.ps1`, every `.script`, `.ltx`, and `.xml` file is converted to `Windows-1251` automatically.
