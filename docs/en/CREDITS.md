# Credits and third-party licenses

[На русском](../ru/CREDITS.md) / [Back to README](../../README.md)

Gamepad At Your Service is free for non-commercial use under GSC Game World's X-Ray SDK terms (Clause 3) and the licenses of the upstream projects below.

## Foundations

- GSC Game World: S.T.A.L.K.E.R. and the original X-Ray 1.6 engine (non-commercial Clause 3).
- S.T.A.L.K.E.R. Anomaly Team: Anomaly 1.5.x platform.
- `themrdemonized` and contributors: [`xray-monolith`](https://github.com/themrdemonized/xray-monolith) (`MT-TEST 2026.05.15` engine base).
- Grok and the G.A.M.M.A. team: S.T.A.L.K.E.R. G.A.M.M.A. modpack.
- `brodrigz`: DX12 presentation bridge and DLSS / FSR 3 / Streamline integration used in `gamma-monolith-dlss`.
- HarukaSai: Quick Action Wheel (MIT License), hooked at runtime in G.A.M.M.A. by `gp_qaw_patch.script`.
- TheHoodieGuy02: VectorGamepad (`Dot Marks`) controller prompts (CC0 1.0 Public Domain), paired with our MIT glyph atlases.

## Engine and runtime libraries

- SDL3 (`3.4.18`): zlib License, Copyright (c) Sam Lantinga et al.
- OpenAL Soft (`1.23.1`): LGPL-2.0-or-later, dynamically linked via replaceable `soft_oal.dll`.
- LuaJIT, Lua 5.1, Luabind, Dear ImGui: MIT License.
- Upstream X-Ray / `xray-monolith` dependencies: Intel oneTBB (Apache-2.0), Xiph.Org `libogg`/`libvorbis`/`libtheora` (BSD-3-Clause), ODE (BSD-3-Clause), OPCODE (Pierre Terdiman), IJG `libjpeg 6b`, CxImage / zlib / NVTT, StackWalker (BSD), Unicode ICU, OpenSSL/SSLeay, and Oberhumer `minilzo` (GPL-2.0-only, inherited `.db` archive decompression). Full license texts are included in `THIRD_PARTY/` inside each release `.zip`.
- `gamma-monolith-dlss` runtime libraries: NVIDIA NGX / DLSS and Streamline (NVIDIA Redistributable Terms), AMD FidelityFX / FSR 3 (MIT License), Microsoft DirectX 12 Agility SDK (Microsoft Distributable Code Agreement). Third-party G.A.M.M.A. PBR/SSS shader packs are not redistributed in our archives.
