# License

Gamepad At Your Service is free for non-commercial use in the S.T.A.L.K.E.R. modding community.

## Original code and custom icon atlases

All original Lua scripts (`gamedata/scripts/gp_*.script`, `ui_gp_*.script`, `ui_options_gamepad.script`, `modxml_gp_workshop.script`), original UI XML/LTX configs, procedural button glyph atlases, and standalone C++ gamepad files (`Gamepad*`, `PauseTokenManager*`, `GpHintXray*`) written for this project are released under the MIT License, subject to GSC Game World's non-commercial rule when linked or shipped with X-Ray Engine code:

```text
MIT License (original project scripts, configs, glyphs, and standalone gamepad modules)

Permission is hereby granted, free of charge, to any person obtaining a copy
of the original gamepad scripts, UI definitions, and standalone gamepad modules
in this repository to deal in them without restriction, including the rights to
use, copy, modify, merge, publish, and distribute copies, subject to the
following conditions:

1. The above notice and this permission notice shall be included in all copies
   or substantial portions of the software.
2. When linked with or distributed alongside X-Ray Engine, OpenXRay, or Anomaly
   code, GSC Game World's non-commercial condition applies ("Neither binary nor
   source code redistributions may be used for any commercial purposes").

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
```

## Upstream engine and third-party libraries

- X-Ray Engine 1.6 (GSC Game World) and `xray-monolith` (`themrdemonized`, Anomaly Team, OpenXRay contributors): non-commercial X-Ray license terms apply to engine patches and executables.
- SDL3 (`3.4.18`): Copyright (c) Sam Lantinga et al., zlib License.
- OpenAL Soft: dynamically linked through `soft_oal.dll` (LGPL-2.1-or-later).
- VectorGamepad (`Dot Marks` by `TheHoodieGuy02`): CC0 1.0 Public Domain.
- Quick Action Wheel (`HarukaSai`): MIT License (hooked at runtime via `gp_qaw_patch.script`).

Full library attributions are listed in [docs/en/CREDITS.md](docs/en/CREDITS.md) and [docs/ru/CREDITS.md](docs/ru/CREDITS.md).
