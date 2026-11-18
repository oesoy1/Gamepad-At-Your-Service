# Авторы и лицензии сторонних библиотек

[In English](../en/CREDITS.md) / [На главную](../../README.ru.md)

Gamepad At Your Service распространяется бесплатно для некоммерческого использования с соблюдением некоммерческого правила GSC Game World для X-Ray SDK (Clause 3) и лицензий перечисленных ниже проектов.

## Авторы платформы и аддонов

- GSC Game World: вселенная S.T.A.L.K.E.R. и исходный движок X-Ray 1.6 (некоммерческое условие Clause 3).
- Команда S.T.A.L.K.E.R. Anomaly: платформа Anomaly 1.5.x.
- `themrdemonized` и участники проекта: открытый движок [`xray-monolith`](https://github.com/themrdemonized/xray-monolith) (база `MT-TEST 2026.05.15`).
- Grok и команда G.A.M.M.A.: сборка S.T.A.L.K.E.R. G.A.M.M.A.
- `brodrigz`: DX12-мост и подключение DLSS / FSR 3 / Streamline в версии `gamma-monolith-dlss`.
- HarukaSai: Quick Action Wheel (MIT License), поверх которого в G.A.M.M.A. работает наш адаптер `gp_qaw_patch.script`.
- TheHoodieGuy02: векторные значки VectorGamepad (`Dot Marks`, CC0 1.0 Public Domain), наряду с собственными атласами проекта (MIT).

## Библиотеки движка

- SDL3 (`3.4.18`): zlib License, Copyright (c) Sam Lantinga et al.
- OpenAL Soft (`1.23.1`): LGPL-2.0-or-later (динамическое подключение через заменяемую `soft_oal.dll`).
- LuaJIT, Lua 5.1, Luabind, Dear ImGui: MIT License.
- Библиотеки в составе X-Ray и `xray-monolith`: Intel oneTBB (Apache-2.0), Xiph.Org `libogg`/`libvorbis`/`libtheora` (BSD-3-Clause), ODE (BSD-3-Clause), OPCODE (Pierre Terdiman), IJG `libjpeg 6b`, CxImage / zlib / NVTT, StackWalker (BSD), Unicode ICU, OpenSSL/SSLeay и Oberhumer `minilzo` (GPL-2.0-only, унаследованная распаковка `.db`-архивов). Полные тексты лицензий лежат в папке `THIRD_PARTY/` внутри каждого релизного `.zip`.
- Библиотеки версии `gamma-monolith-dlss`: NVIDIA NGX / DLSS и Streamline (NVIDIA Redistributable Terms), AMD FidelityFX / FSR 3 (MIT License), Microsoft DirectX 12 Agility SDK (Microsoft Distributable Code Agreement). Чужие паки шейдеров PBR/SSS в архивы мода не включаются.
