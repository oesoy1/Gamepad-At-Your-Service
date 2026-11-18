# `engine-changes/`

[Porting guide (English)](../docs/en/DEVELOPERS.md) / [Инструкция по переносу (Русский)](../docs/ru/DEVELOPERS.md)

This folder separates our C++ work from the rest of the X-Ray source tree so other engine maintainers can read or apply it directly:

- `new-files/src/xrEngine/`: `GamepadDeviceManager`, `GamepadBindings`, `GamepadMath`, `GamepadHaptics`, `GamepadGlyphs`, `GamepadErrorGuard`, `GamepadAtomicFile`.
- `new-files/src/xrGame/`: `GamepadContextDispatcher`, `PauseTokenManager`, `GamepadAimAssist`, `GamepadFocusGraph`, `GamepadModalStack`, `GamepadWidgets`, `GamepadTxnDispatcher`, `GamepadOnScreenKeyboard`, `GamepadCalibrationWnd`, `GamepadRemapWnd`, `GpHintXray`, and `ui/UIButton*Glyphs*.inc`.
- `new-files/tools/tests/`: 10 standalone console unit tests for stick math, bindings, focus navigation, modal stack, OSK, PDA, cursor, widgets, transactions, and error handling.
- `patches/gamma-monolith-gamepad.patch`: complete C++ diff against `themrdemonized/xray-monolith` commit `3d4dcca52` (`MT-TEST 2026.05.15`), with third-party SDL3 binaries excluded so the file contains code only.
- `patches/gamma-monolith-dlss-bridge.patch`: optional DX12 presentation bridge and DLSS / FSR 3 / Streamline Frame Generation diff on top of `gp-release-mt-may` (`sdk/` headers and binaries excluded).

For the full Visual Studio 2022 project tree, see [`oesoy1/xray-monolith-gamepad`](https://github.com/oesoy1/xray-monolith-gamepad).
