#!/usr/bin/env python3
"""Crash report triage tool for GAMMA Gamepad & Tactical UI (CRASH1).

Opens a crash report .zip created by collect.ps1 (or an unpacked folder / raw
xray_*.log), extracts engine/mod/device metadata, FATAL ERROR blocks, Lua & C++
stack traces, S1/S3 non-fatal gamepad error reports, and matches them against
known crash signatures from docs/kb/29-crash-audit.md and
docs/kb/28-luatest-findings.md.

Supports D64 baseline (2026-11-14):
  Primary target : Original G.A.M.M.A. engine (xray-monolith DX11/AVX) & Anomaly
  Optional target: PBR + DX12 + DLSS build (AnomalyDX12.exe)
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys
import tempfile
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable


def decode_text_auto(raw: bytes) -> str:
    """Decode UTF-8 (with or without BOM) falling back to Windows-1251."""
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw[3:].decode("utf-8", errors="replace")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("cp1251", errors="replace")


@dataclass
class CrashMatch:
    sig_id: str
    kb_ref: str
    severity: str
    status: str
    title_ru: str
    title_en: str
    evidence: str
    advice_ru: str
    advice_en: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.sig_id,
            "kb_ref": self.kb_ref,
            "severity": self.severity,
            "status": self.status,
            "title_ru": self.title_ru,
            "title_en": self.title_en,
            "evidence": self.evidence,
            "advice_ru": self.advice_ru,
            "advice_en": self.advice_en,
        }


@dataclass
class ParsedXrayLog:
    source_name: str
    engine_build: str = ""
    modded_exes_ver: str = ""
    game_started: str = ""
    renderer: str = ""
    sdl3_line: str = ""
    gamepad_devices: list[str] = field(default_factory=list)
    active_devices: list[str] = field(default_factory=list)
    profile_load_line: str = ""
    fatal_blocks: list[dict[str, str]] = field(default_factory=list)
    lua_errors: list[str] = field(default_factory=list)
    stack_traces: list[list[str]] = field(default_factory=list)
    safe_guard_events: list[str] = field(default_factory=list)
    core_armor_events: list[str] = field(default_factory=list)
    clean_shutdown: bool = False
    line_count: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "source_name": self.source_name,
            "engine_build": self.engine_build,
            "modded_exes_ver": self.modded_exes_ver,
            "game_started": self.game_started,
            "renderer": self.renderer,
            "sdl3_line": self.sdl3_line,
            "gamepad_devices": self.gamepad_devices,
            "active_devices": self.active_devices,
            "profile_load_line": self.profile_load_line,
            "fatal_blocks": self.fatal_blocks,
            "lua_errors": self.lua_errors,
            "stack_traces": self.stack_traces,
            "safe_guard_events": self.safe_guard_events,
            "core_armor_events": self.core_armor_events,
            "clean_shutdown": self.clean_shutdown,
            "line_count": self.line_count,
        }


def parse_xray_log(text: str, source_name: str = "xray.log") -> ParsedXrayLog:
    lines = text.splitlines()
    res = ParsedXrayLog(source_name=source_name, line_count=len(lines))

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()

        if not res.engine_build and stripped.startswith("'xrCore' build"):
            res.engine_build = stripped
        elif not res.modded_exes_ver and "Modded Exes" in stripped:
            res.modded_exes_ver = stripped
        elif not res.game_started and stripped.startswith("Game started:"):
            res.game_started = stripped
        elif not res.renderer and "renderer_" in stripped:
            res.renderer = stripped
        elif "SDL3 gamepad subsystem initialized" in stripped:
            res.sdl3_line = stripped
        elif "[Gamepad] Device added:" in stripped:
            res.gamepad_devices.append(stripped)
        elif "[Gamepad] Active device switched:" in stripped:
            res.active_devices.append(stripped)
        elif "gpbind::LoadActiveBindingProfile:" in stripped:
            res.profile_load_line = stripped
        elif "[gp_safe_guard]" in stripped and "caught error" in stripped:
            res.safe_guard_events.append(stripped)
        elif "[Gamepad] S3 Core Armor caught error" in stripped:
            res.core_armor_events.append(stripped)
        elif "[xrLogger] InternalCloseLog called" in stripped:
            res.clean_shutdown = True

        # LUA error lines (both standalone and inside FATAL ERROR descriptions)
        if re.search(r"(?:^|\s)(?:!?\s*\[?LUA\]?\[?ERROR\]?|LUA error:|! Cannot find saved game|attempt to |No such operator \[__eq\])", stripped):
            if stripped not in res.lua_errors:
                res.lua_errors.append(stripped)

        # FATAL ERROR block (xrDebugNew.cpp:149-197)
        if stripped == "FATAL ERROR" or stripped.endswith("FATAL ERROR"):
            block: dict[str, str] = {"raw_header": stripped}
            extra_desc: list[str] = []
            j = i + 1
            while j < n and j < i + 30:
                sub = lines[j].rstrip()
                sub_s = sub.strip()
                if sub_s == "stack trace:" or sub_s.startswith("stack trace:"):
                    break
                if sub_s == "" and j > i + 1 and ("File" in block or "Description" in block or "Arguments" in block):
                    # Peek ahead: extended_description may follow an empty line before stack trace
                    if j + 1 < n and lines[j + 1].strip() in ("", "stack trace:"):
                        j += 1
                        break
                m_kv = re.match(r"^\s*(?:\[error\]\s*)?(Expression|Function|File|Line|Description|Arguments)\s*:\s*(.*)$", sub)
                if m_kv:
                    block[m_kv.group(1)] = m_kv.group(2).strip()
                elif sub_s:
                    extra_desc.append(sub_s)
                j += 1
            if extra_desc:
                block["Extra"] = " | ".join(extra_desc)
            res.fatal_blocks.append(block)
            i = j
            continue

        # stack trace: block (xrDebugNew.cpp:118-132, 219-224)
        if stripped == "stack trace:" or re.match(r"^stack trace:\s*$", stripped, re.IGNORECASE):
            frames: list[str] = []
            j = i + 1
            empty_run = 0
            while j < n and len(frames) < 80:
                sub = lines[j].rstrip()
                sub_s = sub.strip()
                if sub_s == "":
                    empty_run += 1
                    if frames and empty_run >= 2:
                        break
                    j += 1
                    continue
                empty_run = 0
                # Stop if a completely unrelated engine banner starts after stack frames
                if frames and (sub_s.startswith("FATAL ERROR") or sub_s.startswith("[xrLogger]")):
                    break
                frames.append(sub_s)
                j += 1
            if frames:
                res.stack_traces.append(frames)
            i = j
            continue

        # Windows unhandled exception banner without FATAL ERROR header
        if re.search(r"Unhandled exception|Exception code:|EXCEPTION_ACCESS_VIOLATION|stack overflow", stripped, re.IGNORECASE):
            if not any(stripped in b.get("Extra", "") for b in res.fatal_blocks):
                res.fatal_blocks.append({"raw_header": "UNHANDLED_EXCEPTION", "Description": stripped})

        i += 1

    return res


def parse_gamepad_error_log(text: str, source_name: str = "gamepad_last_error.log") -> dict[str, Any]:
    fields: dict[str, str] = {"source_name": source_name}
    for line in text.splitlines():
        m = re.match(
            r"^\s*(stage_tag|origin_layer|error_detail|seh_exception_code|seh_exception_addr|gamepad_context|frame|frame_id|time_ms|time_continual_ms|repeat_count|was_gamepad_source|was_device_paused)\s*:\s*(.+)$",
            line,
        )
        if m:
            fields[m.group(1)] = m.group(2).strip()
    m_what = re.search(r"1\.\s*ЧТО ПРОИЗОШЛО:\s*\r?\n\s*(.+)", text)
    if m_what:
        fields["what_ru"] = m_what.group(1).strip()
    m_when = re.search(r"2\.\s*В КАКОЙ МОМЕНТ ИГРЫ:\s*\r?\n\s*(.+)", text)
    if m_when:
        fields["when_ru"] = m_when.group(1).strip()
    return fields


def parse_mo2_modlist(text: str) -> dict[str, Any]:
    total = 0
    enabled = 0
    disabled = 0
    gamepad_line = ""
    haru_enabled = False
    gamma_qaw_enabled = False
    for raw in text.splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        total += 1
        if s.startswith("+"):
            enabled += 1
        elif s.startswith("-"):
            disabled += 1
        if re.search(r"GAMMA Gamepad|Gamepad & Tactical UI", s, re.IGNORECASE):
            gamepad_line = s
        if re.match(r"^\+.*Quick Action Wheel\s*-\s*HarukaSai", s, re.IGNORECASE):
            haru_enabled = True
        if re.match(r"^\+.*G\.A\.M\.M\.A\.\s*Quick Action Wheel Balance", s, re.IGNORECASE):
            gamma_qaw_enabled = True
    return {
        "total_entries": total,
        "enabled_mods": enabled,
        "disabled_mods": disabled,
        "gamepad_mod_line": gamepad_line,
        "haru_qaw_enabled": haru_enabled,
        "gamma_qaw_balance_enabled": gamma_qaw_enabled,
    }


def _collect_combined_corpus(
    logs: list[ParsedXrayLog],
    gamepad_errors: list[dict[str, Any]],
) -> str:
    chunks: list[str] = []
    for lg in logs:
        for b in lg.fatal_blocks:
            chunks.append(" ".join(f"{k}:{v}" for k, v in b.items()))
        chunks.extend(lg.lua_errors)
        for st in lg.stack_traces:
            chunks.extend(st)
        chunks.extend(lg.safe_guard_events)
        chunks.extend(lg.core_armor_events)
    for ge in gamepad_errors:
        chunks.append(" ".join(f"{k}:{v}" for k, v in ge.items()))
    return "\n".join(chunks)


def match_known_crashes(
    logs: list[ParsedXrayLog],
    gamepad_errors: list[dict[str, Any]],
    manifest: dict[str, Any] | None,
    mo2_summary: dict[str, Any] | None,
    binaries_info: dict[str, Any] | None,
) -> list[CrashMatch]:
    corpus = _collect_combined_corpus(logs, gamepad_errors)
    matches: list[CrashMatch] = []

    def add_match(
        sig_id: str,
        kb_ref: str,
        severity: str,
        status: str,
        title_ru: str,
        title_en: str,
        evidence: str,
        advice_ru: str,
        advice_en: str,
    ) -> None:
        matches.append(
            CrashMatch(
                sig_id=sig_id,
                kb_ref=kb_ref,
                severity=severity,
                status=status,
                title_ru=title_ru,
                title_en=title_en,
                evidence=evidence.strip(),
                advice_ru=advice_ru,
                advice_en=advice_en,
            )
        )

    # 1. Signatures from docs/kb/29-crash-audit.md & docs/kb/28-luatest-findings.md
    m_eq = re.search(r"No such operator \[__eq\] defined in class \[([^\]]+)\]", corpus, re.IGNORECASE)
    if m_eq:
        cls_name = m_eq.group(1)
        sig = "CA-01..CA-07 / F-18"
        if "UICellContainer" in cls_name or "CUIScriptWnd" in cls_name:
            sig = "CA-01 / CA-02 / F-18"
        elif "CUIStatic" in cls_name:
            sig = "F-31"
        add_match(
            sig,
            "docs/kb/29-crash-audit.md §2 Категория A; docs/kb/28-luatest-findings.md (F-18, F-31)",
            "CRITICAL",
            "Исправлено в этапах 2-3 / F-18 / UIDBG (проверьте версию скриптов)",
            f"Ошибка Luabind __eq на C++-объекте класса [{cls_name}]",
            f"Luabind __eq trap on userdata class [{cls_name}]",
            m_eq.group(0),
            "Заменить сравнение == / ~= на rawequal(a, b) или сравнение примитивных ID. Игроку — обновить скрипты мода из свежего релиза.",
            "Replace == / ~= comparisons with rawequal(a, b). Player: update mod scripts to the latest release.",
        )

    m_now = re.search(r"get_now_continual_ms", corpus, re.IGNORECASE)
    if m_now:
        add_match(
            "CB-01 / F-23",
            "docs/kb/29-crash-audit.md (CB-01); docs/kb/28-luatest-findings.md (F-23)",
            "CRITICAL",
            "Исправлено в Этапе 3 (gp_bridge.script)",
            "Вызов несуществующей функции get_now_continual_ms() в транзакциях gp_bridge.script",
            "Call to undefined global get_now_continual_ms() in gp_bridge.script transactions",
            m_now.group(0),
            "Использовать (time_continual and time_continual()) or time_global() or 0. У игрока устаревшая версия gp_bridge.script.",
            "Player has an outdated gp_bridge.script; update to latest release.",
        )

    if re.search(r"device\(\)\.dwFrame|attempt to index.*dwFrame", corpus, re.IGNORECASE):
        add_match(
            "CB-02",
            "docs/kb/29-crash-audit.md (CB-02)",
            "HIGH",
            "Исправлено в Этапе 3 (gp_bridge.script)",
            "Чтение неэкспортированного поля device().dwFrame вместо device().frame",
            "Access to unexported CRenderDevice::dwFrame instead of device().frame",
            "device().dwFrame",
            "Использовать device().frame (script_render_device_script.cpp:73).",
            "Use device().frame instead of dwFrame.",
        )

    m_iter = re.search(
        r"(iterate_inventory|iterate_nearest).*?(lua_pcall_failed|gp_weapon|gp_compat|gp_wheel|gp_bridge)"
        r"|(lua_pcall_failed).*?(gp_weapon|gp_compat|gp_wheel|gp_bridge).*?(iterate_inventory|iterate_nearest)?",
        corpus,
        re.IGNORECASE | re.DOTALL,
    )
    if m_iter or ("lua_pcall_failed" in corpus and re.search(r"iterate_inventory|iterate_nearest", corpus)):
        ev = m_iter.group(0)[:180] if m_iter else "lua_pcall_failed + iterate_inventory/iterate_nearest"
        add_match(
            "CC-01..CC-06",
            "docs/kb/29-crash-audit.md §1.3 и §2 Категория C",
            "CRITICAL",
            "Требует проверки внутренней защиты pcall в колбэке C++-итератора",
            "Исключение внутри Lua-колбэка C++-итератора (iterate_inventory / iterate_nearest)",
            "Lua error inside C++ iterator callback (iterate_inventory / iterate_nearest)",
            ev,
            "Внешний pcall вокруг iterate_inventory/iterate_nearest не спасает — обернуть тело самого колбэка в pcall.",
            "Wrap the callback body inside iterate_inventory/iterate_nearest in an inner pcall.",
        )

    m_is_shown = re.search(r"attempt to call method 'IsShown' \(a nil value\)|get_hud\(\):IsShown", corpus, re.IGNORECASE)
    if m_is_shown:
        add_match(
            "F-09",
            "docs/kb/28-luatest-findings.md (F-09)",
            "HIGH",
            "Исправлено в gp_wheel.script (заменено на main_hud_shown())",
            "Вызов несуществующего метода get_hud():IsShown() в колесе",
            "Call to missing CUIGameCustom:IsShown() method",
            m_is_shown.group(0),
            "Заменить на main_hud_shown(). У игрока старая версия скриптов.",
            "Replaced by main_hud_shown() in current scripts; update mod scripts.",
        )

    m_init_cell = re.search(r"gp_wheel\.script.*init_cell|attempt to perform arithmetic on field 'x' \(a nil value\)", corpus, re.IGNORECASE)
    if m_init_cell:
        add_match(
            "F-10",
            "docs/kb/28-luatest-findings.md (F-10)",
            "HIGH",
            "Исправлено в gp_wheel.script (используются x1/y1/x2/y2)",
            "Чтение .x/.y вместо x1/y1/x2/y2 из utils_xml.get_item_axis()",
            "Reading .x/.y instead of x1/y1/x2/y2 from utils_xml.get_item_axis()",
            m_init_cell.group(0),
            "Обновить gp_wheel.script из актуальной сборки.",
            "Update gp_wheel.script to the latest release.",
        )

    m_comp = re.search(r"cycle_companion_(?:movement|combat|stealth|distance|loot)_type|set_companion_to_move_to_point_state", corpus, re.IGNORECASE)
    if m_comp:
        add_match(
            "F-12",
            "docs/kb/28-luatest-findings.md (F-12)",
            "HIGH",
            "Исправлено (приведено к axr_companions.cycle_companions_*_mode)",
            "Обращение к устаревшим именам функций axr_companions",
            "Call to non-existent axr_companions function names",
            m_comp.group(0),
            "Обновить gp_wheel.script / gp_pda.script до текущей версии.",
            "Update gp_wheel.script / gp_pda.script.",
        )

    if re.search(r"go_to_next_action|lam2\.script.*stack overflow|C stack overflow.*lam2", corpus, re.IGNORECASE):
        add_match(
            "F-25 / FIX-Crash10",
            "docs/kb/28-luatest-findings.md (F-25)",
            "CRITICAL",
            "Исправлено в gp_lifecycle.script (FIX-Crash10)",
            "Рекурсивный цикл lam2.go_to_next_action на паузе (stack overflow)",
            "Recursive lam2.go_to_next_action stack overflow during pause",
            "lam2 / go_to_next_action",
            "Обновить gp_lifecycle.script до версии после FIX-Crash10.",
            "Update gp_lifecycle.script to post-FIX-Crash10 release.",
        )

    if re.search(r"CreateTimeEvent|gp_compat_switch|gp_weapon.*(?:ammo_check|fast_reload)|gp_wheel.*(?:activate_slot|show_detector|hide_detector)", corpus, re.IGNORECASE):
        if re.search(r"FATAL ERROR|LUA error:|caught error", corpus, re.IGNORECASE):
            add_match(
                "CD-04 / CD-12 / CE-03",
                "docs/kb/29-crash-audit.md (CD-04, CD-12, CE-03)",
                "HIGH",
                "Зависит от стека — проверить pcall в таймере CreateTimeEvent",
                "Ошибка в отложенном таймере CreateTimeEvent (исчезнувший предмет или внешний мод)",
                "Error inside CreateTimeEvent callback (destroyed object or foreign mod)",
                "CreateTimeEvent callback failure",
                "Проверить обёртку pcall внутри таймера и повторное получение объекта по level.object_by_id().",
                "Check pcall wrapper and level.object_by_id() re-fetch inside CreateTimeEvent.",
            )

    if re.search(r"ui_gp_qaw_settings.*attempt to index|entries\[index\]", corpus, re.IGNORECASE):
        add_match(
            "F-33",
            "docs/kb/28-luatest-findings.md (F-33)",
            "MEDIUM",
            "Исправлено в ui_gp_qaw_settings.script",
            "Ошибка индексации пустых строк в окне настроек быстрого колеса",
            "Nil index in ui_gp_qaw_settings when fewer than 17 entries exist",
            "ui_gp_qaw_settings",
            "Обновить ui_gp_qaw_settings.script.",
            "Update ui_gp_qaw_settings.script.",
        )

    # Known live error observed on stand during wave 3 testing
    if re.search(r"gp_pda\.(?:script:632|tick).*table index is nil", corpus, re.IGNORECASE):
        add_match(
            "S1-S3-GP-PDA-632",
            "gp_pda.script:632 + gp_safe_guard.script + GamepadErrorGuard.cpp",
            "MEDIUM",
            "Перехвачено защитой S1/S3 (без вылета игры, но требует фикса gp_pda.script:632)",
            "Нефатальный сбой в gp_pda.tick (gp_pda.script:632: table index is nil) — перехвачен S1/S3",
            "Non-fatal Lua error in gp_pda.tick (table index is nil at line 632) caught by S1/S3",
            "gp_pda.script:632: table index is nil",
            "Проверить индексацию таблицы в gp_pda.script:632 при закрытии/смене вкладки КПК.",
            "Check nil table key in gp_pda.script:632 during PDA tick.",
        )

    # Generic S1/S3 caught errors if not matched specifically above
    for ge in gamepad_errors:
        seh = ge.get("seh_exception_code", "")
        if seh and seh != "0x00000000":
            add_match(
                f"SEH-{seh.split()[0]}",
                "xrEngine/GamepadErrorGuard.cpp",
                "HIGH",
                "Перехвачено броней S3 Core Armor (игра не вылетела, управление переведено на КиМ)",
                f"Аппаратное исключение SEH {seh} в подсистеме геймпада ({ge.get('stage_tag', '?')})",
                f"Hardware SEH exception {seh} in gamepad frame ({ge.get('stage_tag', '?')})",
                f"stage={ge.get('stage_tag', '?')} seh={seh} detail={ge.get('error_detail', '?')}",
                "Передать отчёт разработчику для разбора C++-участка по stage_tag и мини-дампу.",
                "Send report to developer to inspect C++ stage_tag and minidump.",
            )
        elif ge.get("stage_tag") and not any(m.sig_id == "S1-S3-GP-PDA-632" for m in matches):
            add_match(
                "S1-S3-CAUGHT",
                "gp_safe_guard.script + gp_error_log.script",
                "MEDIUM",
                "Перехвачено защитой S1/S3 (без вылета игры)",
                f"Перехваченная ошибка геймпада в {ge.get('stage_tag')}",
                f"Caught gamepad error in {ge.get('stage_tag')}",
                f"stage={ge.get('stage_tag')} detail={ge.get('error_detail', '')}",
                "Проверить указанный Lua-скрипт и контекст gamepad_context.",
                "Inspect the reported Lua script stage_tag and gamepad_context.",
            )

    # Generic Lua error in any gp_*.script or ui_gp_*.script not yet categorized
    m_gp_lua = re.search(r"((?:gp_|ui_gp_)[a-zA-Z0-9_]+\.script:\d+:[^\r\n]+)", corpus, re.IGNORECASE)
    if m_gp_lua and not any("gp_pda.script:632" in m.evidence for m in matches):
        add_match(
            "GP-LUA-RUNTIME",
            "docs/kb/29-crash-audit.md §1",
            "HIGH",
            "Ошибка исполнения в скрипте мода геймпада",
            f"Ошибка Lua в скрипте мода: {m_gp_lua.group(1)[:120]}",
            f"Lua runtime error in gamepad mod script: {m_gp_lua.group(1)[:120]}",
            m_gp_lua.group(1),
            "Проверить указанную строку скрипта; убедиться, что внешние вызовы обёрнуты в pcall.",
            "Inspect the indicated script line and ensure external calls are guarded with pcall.",
        )

    # Out of memory / D3D / shader errors
    if re.search(r"Out of memory|Not enough storage|std::bad_alloc|E_OUTOFMEMORY", corpus, re.IGNORECASE):
        add_match(
            "OOM-MEMORY",
            "xrCore/xrDebug.cpp:200",
            "HIGH",
            "Системная ошибка нехватки памяти (ОЗУ/VRAM/файл подкачки)",
            "Нехватка оперативной памяти или файла подкачки (Out of Memory)",
            "Out of memory / pagefile exhaustion",
            "Out of memory",
            "Увеличить файл подкачки Windows (20-32 ГБ для G.A.M.M.A.) и снизить качество текстур/теней.",
            "Increase Windows pagefile size (20-32 GB recommended for G.A.M.M.A.) and lower texture/shadow settings.",
        )

    # 2. Installation & D64 engine checks
    if binaries_info:
        sdl3 = binaries_info.get("sdl3") or {}
        bins = binaries_info.get("binaries") or []
        if sdl3.get("present") is False:
            add_match(
                "INSTALL-NO-SDL3",
                "docs/kb/27-packaging-design.md §3.1; tools/package/verify.ps1",
                "CRITICAL",
                "Проблема установки — отсутствует SDL3.dll",
                "В папке Anomaly\\bin отсутствует библиотека SDL3.dll",
                "SDL3.dll is missing from Anomaly\\bin",
                "sdl3.present = false",
                "Скопируйте SDL3.dll из папки 1_Copy_To_Anomaly_bin архива мода в <Папка Anomaly>\\bin\\.",
                "Copy SDL3.dll from 1_Copy_To_Anomaly_bin into <Anomaly>\\bin\\.",
            )
        # Check if primary DX11/AVX or all Anomaly*.exe are stock without SDL3
        dx11_bins = [b for b in bins if "DX11" in b.get("name", "")]
        any_sdl3 = any(b.get("imports_sdl3") for b in bins)
        stock_hits = [b for b in bins if "Stock" in b.get("classification", "")]
        if bins and not any_sdl3:
            add_match(
                "INSTALL-STOCK-EXE",
                "docs/kb/27-packaging-design.md §4 Сценарий А (D64)",
                "CRITICAL",
                "Скрипты геймпада установлены без пропатченного движка",
                "Ни один EXE в Anomaly\\bin не содержит поддержки геймпада (SDL3.dll не подключён)",
                "No executable in Anomaly\\bin links SDL3.dll (stock engine active)",
                ", ".join(f"{b.get('name')} ({b.get('classification')})" for b in stock_hits or bins[:3]),
                "Если G.A.M.M.A. Launcher обновил игру, заново скопируйте пропатченный AnomalyDX11AVX.exe (или DX11/опц. DX12) и SDL3.dll в Anomaly\\bin\\.",
                "If G.A.M.M.A. Launcher updated the game, re-copy the modded AnomalyDX11AVX.exe (and SDL3.dll) into Anomaly\\bin\\.",
            )
        elif dx11_bins and all(not b.get("imports_sdl3") for b in dx11_bins) and any_sdl3:
            add_match(
                "INSTALL-DX11-STOCK-VS-OPT-DX12",
                "docs/agents/wave3/00-common.md (D64)",
                "WARN",
                "Замечено: основной DX11 EXE стоковый, пропатчен только опциональный DX12 EXE",
                "Основной AnomalyDX11/AVX без геймпада (пропатчен только опциональный AnomalyDX12)",
                "Primary DX11/AVX binary is stock; only optional DX12 binary has gamepad support",
                ", ".join(b.get("name", "") for b in dx11_bins),
                "Для стандартной G.A.M.M.A. установите пропатченный AnomalyDX11AVX.exe, либо убедитесь, что запускаете именно нужный EXE.",
                "Install modded AnomalyDX11AVX.exe for standard G.A.M.M.A., or ensure MO2 launches your intended EXE.",
            )

    if mo2_summary:
        if mo2_summary.get("haru_qaw_enabled") or mo2_summary.get("gamma_qaw_balance_enabled"):
            conflicts = []
            if mo2_summary.get("haru_qaw_enabled"):
                conflicts.append("446- Quick Action Wheel - HarukaSai")
            if mo2_summary.get("gamma_qaw_balance_enabled"):
                conflicts.append("G.A.M.M.A. Quick Action Wheel Balance")
            add_match(
                "MO2-QAW-CONFLICT",
                "docs/kb/27-packaging-design.md §2.3 п.4 (D58)",
                "HIGH",
                "Конфликт модов в MO2",
                f"В MO2 не отключены старые моды колеса: {', '.join(conflicts)}",
                f"Conflicting QAW mods still enabled in MO2: {', '.join(conflicts)}",
                " + ".join(conflicts),
                "Снимите галочки в MO2 с модов '446- Quick Action Wheel - HarukaSai' и 'G.A.M.M.A. Quick Action Wheel Balance'.",
                "Disable '446- Quick Action Wheel - HarukaSai' and 'G.A.M.M.A. Quick Action Wheel Balance' in MO2.",
            )

    return matches


def check_privacy_sanitized(entries: dict[str, bytes]) -> list[str]:
    """Heuristic check for leftover personal paths like C:\\Users\\realname."""
    leaks: list[str] = []
    allowed_names = {"<USER>", "USER", "Public", "Default", "Default User", "All Users"}
    pat = re.compile(r"[A-Za-z]:[\\/]+(?:Users|Пользователи)[\\/]+([^\\/\r\n\"'<>|\s]+)", re.IGNORECASE)
    for name, raw in entries.items():
        if name.lower().endswith(".mdmp"):
            continue
        text = decode_text_auto(raw).replace("\\u003c", "<").replace("\\u003e", ">")
        for m in pat.finditer(text):
            uname = m.group(1)
            if uname not in allowed_names:
                leaks.append(f"{name}: {m.group(0)}")
                break
    return leaks


def triage_zip_or_dir(target: Path) -> dict[str, Any]:
    entries: dict[str, bytes] = {}
    input_kind = "unknown"

    if target.is_file() and target.suffix.lower() == ".zip":
        input_kind = "zip"
        with zipfile.ZipFile(target, "r") as zf:
            for info in zf.infolist():
                if not info.is_dir():
                    entries[info.filename.replace("\\", "/")] = zf.read(info.filename)
    elif target.is_dir():
        input_kind = "dir"
        for p in target.rglob("*"):
            if p.is_file():
                entries[p.relative_to(target).as_posix()] = p.read_bytes()
    elif target.is_file():
        input_kind = "single_log"
        entries[f"logs/{target.name}"] = target.read_bytes()
    else:
        raise FileNotFoundError(f"Input path does not exist: {target}")

    manifest: dict[str, Any] | None = None
    binaries_info: dict[str, Any] | None = None
    mo2_summary: dict[str, Any] | None = None

    if "report_manifest.json" in entries:
        try:
            manifest = json.loads(decode_text_auto(entries["report_manifest.json"]))
            mo2_summary = manifest.get("mo2_summary")
        except json.JSONDecodeError:
            manifest = None

    if "engine/binaries_info.json" in entries:
        try:
            binaries_info = json.loads(decode_text_auto(entries["engine/binaries_info.json"]))
        except json.JSONDecodeError:
            binaries_info = None

    if mo2_summary is None and "mo2/modlist.txt" in entries:
        mo2_summary = parse_mo2_modlist(decode_text_auto(entries["mo2/modlist.txt"]))

    # Parse xray_*.log first, then xray_*.bkp (in case player restarted the game after crashing)
    log_keys = sorted(
        [k for k in entries if re.search(r"(?:^|/)xray_.*\.(?:log|bkp)$", k, re.IGNORECASE)],
        key=lambda x: (0 if x.lower().endswith(".log") else 1, x),
    )
    parsed_logs: list[ParsedXrayLog] = [parse_xray_log(decode_text_auto(entries[k]), k) for k in log_keys]

    err_keys = sorted([k for k in entries if "gamepad_last_error" in k.lower() or "gamepad_errors" in k.lower()])
    gamepad_errors = [parse_gamepad_error_log(decode_text_auto(entries[k]), k) for k in err_keys]

    matches = match_known_crashes(parsed_logs, gamepad_errors, manifest, mo2_summary, binaries_info)
    privacy_leaks = check_privacy_sanitized(entries)

    # Determine primary active log containing a crash (or newest .log)
    primary_log = parsed_logs[0] if parsed_logs else None
    for lg in parsed_logs:
        if lg.fatal_blocks or lg.stack_traces or lg.lua_errors:
            primary_log = lg
            break

    # Overall classification
    has_fatal = any(lg.fatal_blocks for lg in parsed_logs)
    has_lua_err = any(lg.lua_errors for lg in parsed_logs)
    has_guarded = bool(gamepad_errors) or any(lg.safe_guard_events or lg.core_armor_events for lg in parsed_logs)
    if has_fatal:
        verdict = "FATAL_CRASH"
    elif has_lua_err or has_guarded:
        verdict = "NON_FATAL_OR_GUARDED_ERROR"
    elif any(m.severity in ("CRITICAL", "HIGH") for m in matches):
        verdict = "CONFIGURATION_OR_INSTALL_ISSUE"
    elif primary_log and primary_log.clean_shutdown:
        verdict = "CLEAN_SHUTDOWN_NO_CRASH"
    else:
        verdict = "NO_EXPLICIT_CRASH_MARKER"

    return {
        "schema_version": "crash1-triage-v1",
        "input": str(target),
        "input_kind": input_kind,
        "verdict": verdict,
        "entry_count": len(entries),
        "minidumps_in_zip": [k for k in sorted(entries) if k.lower().endswith(".mdmp")],
        "privacy_leaks": privacy_leaks,
        "manifest_summary": {
            "collected_utc": manifest.get("collected_utc") if manifest else "",
            "target_baseline": manifest.get("target_baseline") if manifest else "",
            "mod_line": (mo2_summary or {}).get("gamepad_mod_line", ""),
            "enabled_mods": (mo2_summary or {}).get("enabled_mods", 0),
        },
        "engine_summary": {
            "sdl3_present": (binaries_info or {}).get("sdl3", {}).get("present") if binaries_info else None,
            "binaries": [
                {
                    "name": b.get("name"),
                    "imports_sdl3": b.get("imports_sdl3"),
                    "imports_dx12": b.get("imports_dx12"),
                    "classification": b.get("classification"),
                }
                for b in ((binaries_info or {}).get("binaries") or [])
            ],
        },
        "logs": [lg.to_dict() for lg in parsed_logs],
        "gamepad_error_reports": gamepad_errors,
        "matched_signatures": [m.to_dict() for m in matches],
    }


def format_triage_summary(report: dict[str, Any], lang: str = "ru") -> str:
    out: list[str] = []
    out.append("=" * 78)
    out.append(f"CRASH1 TRIAGE SUMMARY  |  Verdict: {report['verdict']}")
    out.append(f"Input: {report['input']} ({report['input_kind']}, {report['entry_count']} entries)")
    out.append("=" * 78)

    ms = report.get("manifest_summary") or {}
    if ms.get("collected_utc"):
        out.append(f"Collected UTC : {ms['collected_utc']}")
    if ms.get("mod_line"):
        out.append(f"MO2 Mod       : {ms['mod_line']} (enabled mods: {ms.get('enabled_mods', 0)})")

    es = report.get("engine_summary") or {}
    if es.get("sdl3_present") is not None:
        out.append(f"SDL3.dll      : {'PRESENT' if es['sdl3_present'] else 'MISSING'}")
    for b in es.get("binaries") or []:
        if b.get("imports_sdl3") or "Stock" in str(b.get("classification", "")):
            out.append(f"Engine Binary : {b.get('name')} -> {b.get('classification')}")

    if report.get("minidumps_in_zip"):
        out.append(f"Minidump(s)   : {', '.join(report['minidumps_in_zip'])}")

    leaks = report.get("privacy_leaks") or []
    out.append(f"Privacy check : {'OK (no raw C:\\Users\\<name> leaks)' if not leaks else 'WARN leaks: ' + '; '.join(leaks)}")

    for lg in report.get("logs") or []:
        out.append("-" * 78)
        out.append(f"Log: {lg['source_name']} ({lg['line_count']} lines, clean_shutdown={lg['clean_shutdown']})")
        if lg["engine_build"]:
            out.append(f"  Build    : {lg['engine_build']} | {lg['modded_exes_ver']}")
        for dev in lg["gamepad_devices"]:
            out.append(f"  Device   : {dev}")
        if lg["fatal_blocks"]:
            for idx, fb in enumerate(lg["fatal_blocks"], 1):
                out.append(f"  FATAL #{idx}: Expression={fb.get('Expression', '')} | Description={fb.get('Description', '')} | Arguments={fb.get('Arguments', '')}")
                if fb.get("File") or fb.get("Line"):
                    out.append(f"             at {fb.get('File', '?')}:{fb.get('Line', '?')} ({fb.get('Function', '?')})")
        if lg["lua_errors"]:
            out.append(f"  Lua errors ({len(lg['lua_errors'])}):")
            for le in lg["lua_errors"][:5]:
                out.append(f"    * {le}")
        if lg["stack_traces"]:
            for idx, st in enumerate(lg["stack_traces"], 1):
                out.append(f"  Stack trace #{idx} (top 15 frames of {len(st)}):")
                for frame in st[:15]:
                    out.append(f"    {frame}")
        if lg["safe_guard_events"]:
            out.append(f"  S1 SafeGuard events ({len(lg['safe_guard_events'])}): {lg['safe_guard_events'][-1]}")

    for ge in report.get("gamepad_error_reports") or []:
        out.append("-" * 78)
        out.append(f"Gamepad Error Report: {ge['source_name']}")
        out.append(f"  stage_tag : {ge.get('stage_tag', '?')} ({ge.get('origin_layer', '?')})")
        out.append(f"  context   : {ge.get('gamepad_context', '?')} | repeat={ge.get('repeat_count', '?')}")
        out.append(f"  detail    : {ge.get('error_detail', '?')}")
        if ge.get("what_ru"):
            out.append(f"  what      : {ge['what_ru']}")

    matches = report.get("matched_signatures") or []
    out.append("-" * 78)
    out.append(f"Known Signatures Matched ({len(matches)}):")
    if not matches:
        out.append("  (No exact known signature from docs/kb/29-crash-audit.md matched)")
    for m in matches:
        title = m["title_ru"] if lang != "en" else m["title_en"]
        advice = m["advice_ru"] if lang != "en" else m["advice_en"]
        out.append(f"  [{m['severity']}] {m['id']} — {title}")
        out.append(f"      KB      : {m['kb_ref']}")
        out.append(f"      Status  : {m['status']}")
        out.append(f"      Evidence: {m['evidence']}")
        out.append(f"      Action  : {advice}")

    out.append("=" * 78)
    return "\n".join(out)


def _make_synthetic_zip(path: Path, files: dict[str, str]) -> None:
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for k, v in files.items():
            zf.writestr(k, v.encode("utf-8"))


def run_selftest() -> int:
    print("Running CRASH1 triage.py --selftest ...")
    scenarios = [
        {
            "name": "CA-01_luabind_eq_trap",
            "files": {
                "logs/xray_<USER>.log": (
                    "'xrCore' build 9000, Oct 11 2026\n"
                    "Modded Exes MT-TEST version 2026.10.11\n"
                    "* [Gamepad] SDL3 gamepad subsystem initialized (v3.4.18)\n"
                    "* [Gamepad] Device added: id=1 name='Xbox Series X Controller' class=A\n"
                    "FATAL ERROR\n"
                    "Expression    : <no expression>\n"
                    "Function      : CScriptEngine::lua_pcall_failed\n"
                    "File          : D:\\a\\xray-monolith\\src\\xrServerEntities\\script_engine.cpp\n"
                    "Line          : 286\n"
                    "Description   : fatal error\n"
                    "Arguments     : LUA error: ! No such operator [__eq] defined in class [UICellContainer]\n\n"
                    "stack trace:\n\n"
                    "...\\gamedata\\scripts\\gp_bridge.script:891: in function 'cursor_dpad_snap'\n"
                    "0x0000000140123456 AnomalyDX11AVX.exe, CScriptEngine::lua_pcall_failed()\n"
                )
            },
            "expect_verdict": "FATAL_CRASH",
            "expect_sig_prefix": "CA-01",
            "expect_stack_substr": "gp_bridge.script:891",
        },
        {
            "name": "CB-01_missing_get_now_continual_ms",
            "files": {
                "logs/xray_<USER>.log": (
                    "FATAL ERROR\n"
                    "Expression    : <no expression>\n"
                    "Function      : CScriptEngine::lua_error\n"
                    "File          : script_engine.cpp\n"
                    "Line          : 231\n"
                    "Description   : fatal error\n"
                    "Arguments     : LUA error: attempt to call global 'get_now_continual_ms' (a nil value)\n\n"
                    "stack trace:\n\n"
                    "...\\gamedata\\scripts\\gp_bridge.script:4601: in function 'txn_begin'\n"
                )
            },
            "expect_verdict": "FATAL_CRASH",
            "expect_sig_prefix": "CB-01",
            "expect_stack_substr": "gp_bridge.script:4601",
        },
        {
            "name": "CC-03_iterate_inventory_bkp_fallback",
            "files": {
                "logs/xray_<USER>.log": "'xrCore' build 9000\n[xrLogger] InternalCloseLog called, terminating thread\n",
                "logs/xray_<USER>.bkp": (
                    "FATAL ERROR\n"
                    "Expression    : <no expression>\n"
                    "Function      : CScriptEngine::lua_pcall_failed\n"
                    "File          : script_engine.cpp\n"
                    "Line          : 296\n"
                    "Description   : fatal error inside db.actor:iterate_inventory in gp_compat.script\n\n"
                    "stack trace:\n\n"
                    "...\\gamedata\\scripts\\gp_compat.script:500: in function 'get_weapon_ammo_summary'\n"
                ),
            },
            "expect_verdict": "FATAL_CRASH",
            "expect_sig_prefix": "CC-01..CC-06",
            "expect_stack_substr": "gp_compat.script:500",
        },
        {
            "name": "S1_S3_gp_pda_632_and_MO2_QAW_conflict",
            "files": {
                "logs/xray_<USER>.log": (
                    "! [gp_safe_guard] S1 caught error in 'gp_pda.tick': d:/game\\gamedata\\scripts\\gp_pda.script:632: table index is nil\n"
                    "[xrLogger] InternalCloseLog called, terminating thread\n"
                ),
                "errors/appdata_gamepad_last_error.log": (
                    "stage_tag       : gp_pda.tick\n"
                    "origin_layer    : lua:gp_pda\n"
                    "error_detail    : d:/game\\gamedata\\scripts\\gp_pda.script:632: table index is nil\n"
                    "gamepad_context : World_3DPDA\n"
                    "repeat_count    : 3\n"
                ),
                "mo2/modlist.txt": (
                    "+GAMMA Gamepad & Tactical UI\n"
                    "+446- Quick Action Wheel - HarukaSai\n"
                    "-G.A.M.M.A. Quick Action Wheel Balance\n"
                ),
            },
            "expect_verdict": "NON_FATAL_OR_GUARDED_ERROR",
            "expect_sig_prefix": "S1-S3-GP-PDA-632",
            "expect_extra_sig": "MO2-QAW-CONFLICT",
        },
        {
            "name": "SEH_0xC0000005_and_stock_DX11_exe",
            "files": {
                "errors/appdata_gamepad_last_error.log": (
                    "stage_tag            : CInput::GamepadUpdate\n"
                    "origin_layer         : C++ Engine Core (Xr_input / xrGame)\n"
                    "error_detail         : Access violation\n"
                    "seh_exception_code   : 0xC0000005 (EXCEPTION_ACCESS_VIOLATION)\n"
                    "gamepad_context      : MenuUI_Modal\n"
                ),
                "engine/binaries_info.json": json.dumps({
                    "sdl3": {"present": False},
                    "binaries": [
                        {
                            "name": "AnomalyDX11AVX.exe",
                            "imports_sdl3": False,
                            "imports_dx12": False,
                            "classification": "Stock X-Ray Monolith MT 2026.10.11 (G.A.M.M.A. AnomalyDX11AVX.exe, NO gamepad module)",
                        }
                    ],
                }),
            },
            "expect_verdict": "NON_FATAL_OR_GUARDED_ERROR",
            "expect_sig_prefix": "SEH-0xC0000005",
            "expect_extra_sig": "INSTALL-STOCK-EXE",
        },
    ]

    with tempfile.TemporaryDirectory(prefix="crash1_selftest_") as tmp:
        tmp_dir = Path(tmp)
        for sc in scenarios:
            zpath = tmp_dir / f"{sc['name']}.zip"
            _make_synthetic_zip(zpath, sc["files"])
            rep = triage_zip_or_dir(zpath)
            sig_ids = [m["id"] for m in rep["matched_signatures"]]
            assert rep["verdict"] == sc["expect_verdict"], f"{sc['name']}: verdict {rep['verdict']} != {sc['expect_verdict']}"
            assert any(s.startswith(sc["expect_sig_prefix"]) for s in sig_ids), f"{sc['name']}: missing {sc['expect_sig_prefix']} in {sig_ids}"
            if "expect_extra_sig" in sc:
                assert sc["expect_extra_sig"] in sig_ids, f"{sc['name']}: missing {sc['expect_extra_sig']} in {sig_ids}"
            if "expect_stack_substr" in sc:
                all_frames = "\n".join(frame for lg in rep["logs"] for st in lg["stack_traces"] for frame in st)
                assert sc["expect_stack_substr"] in all_frames, f"{sc['name']}: missing stack {sc['expect_stack_substr']}"
            summary = format_triage_summary(rep)
            assert len(summary) > 100
            print(f"  [PASS] {sc['name']} -> verdict={rep['verdict']}, matched={sig_ids}")

    print("SELFTEST PASS (5/5 scenarios)")
    return 0


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="CRASH1 triage analyzer for GAMMA Gamepad crash report ZIPs.")
    parser.add_argument("input", nargs="?", help="Path to crash report .zip, unpacked folder, or xray_*.log")
    parser.add_argument("--selftest", action="store_true", help="Run built-in self-tests across known crash signatures")
    parser.add_argument("--json", action="store_true", help="Print full JSON report instead of human summary")
    parser.add_argument("--out", default="", help="Write report (text or JSON when --json is set) to file")
    parser.add_argument("--lang", choices=["ru", "en"], default="ru", help="Summary output language")
    args = parser.parse_args()

    if args.selftest:
        return run_selftest()

    if not args.input:
        parser.error("Provide an input path (.zip / folder / .log) or --selftest")

    target = Path(args.input)
    report = triage_zip_or_dir(target)
    output_text = json.dumps(report, ensure_ascii=False, indent=2) if args.json else format_triage_summary(report, lang=args.lang)

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output_text, encoding="utf-8")

    print(output_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
