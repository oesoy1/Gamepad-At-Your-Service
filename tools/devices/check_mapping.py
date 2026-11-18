#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_mapping.py — офлайн-сверка нашей таблицы устройств (device_matrix.json,
машинная часть docs/kb/29-device-matrix.md) с открытыми базами:

  * data/gamecontrollerdb.txt  — mdqinc/SDL_GameControllerDB (раздел "# Windows");
  * data/SDL_gamepad_db.h      — встроенная база SDL3 (секции XINPUT/WGI/DINPUT);
  * data/controller_list.h     — таблица VID/PID -> EControllerType из SDL3;
  * data/SDL_joystick.c        — списки рулей/флайтстиков/РУД/чёрный список SDL3.

Скрипт НЕ запускает SDL и НЕ трогает движок/игру. Он ПОВТОРЯЕТ на Python логику
нашего кода из D:\\GAMMA-Gamepad-Lab\\build\\engine\\src\\xrEngine:
  * ClassifyGamepadType      (GamepadDeviceManager.cpp:46-67)
  * IsViGEmOrVirtualXbox360  (GamepadDeviceManager.cpp:85-101)
  * класс C для не-геймпадов (GamepadDeviceManager.cpp:369-395) и
    исключение класса C из выбора активного (GamepadDeviceManager.cpp:763-764)
  * выбор набора значков     (GamepadGlyphs.cpp:283-325)
и упрощённо — логику SDL выбора типа (SDL_GetGamepadTypeFromVIDPID/FromGUID,
SDL_joystick.c release-3.4.x). Результат — ПРЕДСКАЗАНИЕ (статус «следует из
исходников»), а не проверка на железе.

Запуск:  python -I tools/devices/check_mapping.py [--out отчёт.md] [--strict]
Код возврата: 0; с --strict — 1, если есть расхождения (MISMATCH).
"""
import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")

# ---------------------------------------------------------------- парсеры баз

GUID_RE = re.compile(r"^[0-9a-fA-F]{32}$")


def guid_vidpid(guid):
    """VID/PID из GUID SDL (формат 2.0.5+: bus(2) crc(2) vid(2) 0(2) pid(2) 0(2) ver(2) drv(1) sub(1)).
    Возвращает (vid, pid, driver_char) или None для старых/текстовых GUID."""
    if not GUID_RE.match(guid):
        return None
    b = bytes.fromhex(guid)
    if b[6:8] != b"\x00\x00" or b[10:12] != b"\x00\x00":
        return None  # GUID из имени устройства (старый формат) — VID/PID нет
    vid = b[4] | (b[5] << 8)
    pid = b[8] | (b[9] << 8)
    drv = chr(b[14]) if 32 < b[14] < 127 else ""
    return vid, pid, drv


def parse_mapping_line(line):
    parts = [p for p in line.strip().split(",")]
    if len(parts) < 3:
        return None
    guid, name = parts[0], parts[1]
    fields = {}
    for p in parts[2:]:
        if ":" in p:
            k, v = p.split(":", 1)
            fields[k.strip()] = v.strip()
    return guid, name, fields


def load_gamecontrollerdb(path):
    """Только раздел '# Windows' (до '# Mac OS X'), плюс platform:Windows из прочих мест."""
    out = []
    section = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for ln, line in enumerate(f, 1):
            s = line.strip()
            if s.startswith("#"):
                h = s.lstrip("#").strip().lower()
                if h in ("windows", "mac os x", "linux", "android", "ios"):
                    section = h
                continue
            if not s:
                continue
            m = parse_mapping_line(s)
            if not m:
                continue
            guid, name, fields = m
            if fields.get("platform", "").lower() != "windows":
                continue
            out.append({"line": ln, "guid": guid.lower(), "name": name, "fields": fields, "raw": s})
    return out


def load_builtin_db(path):
    """Строки из SDL_gamepad_db.h в секциях, действующих на Windows (PRIVATE/XINPUT/WGI/DINPUT)."""
    out = []
    win_sections = ("SDL_JOYSTICK_PRIVATE", "SDL_JOYSTICK_XINPUT", "SDL_JOYSTICK_WGI", "SDL_JOYSTICK_DINPUT")
    cur = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for ln, line in enumerate(f, 1):
            s = line.strip()
            if s.startswith("#if"):
                cur = s
                continue
            if s.startswith("#endif"):
                cur = None
                continue
            if cur and any(w in cur for w in win_sections) and s.startswith('"'):
                body = s.strip().rstrip(",").strip('"')
                m = parse_mapping_line(body)
                if m:
                    out.append({"line": ln, "guid": m[0].lower(), "name": m[1], "fields": m[2], "section": cur})
    return out


CL_RE = re.compile(r"MAKE_CONTROLLER_ID\(\s*0x([0-9a-fA-F]{4})\s*,\s*0x([0-9a-fA-F]{4})\s*\)\s*,\s*(k_eControllerType_\w+)")


def load_controller_list(path):
    table = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for ln, line in enumerate(f, 1):
            s = line.strip()
            if s.startswith("//"):
                continue  # закомментированные (например G29) не действуют
            m = CL_RE.search(s)
            if m:
                key = (int(m.group(1), 16), int(m.group(2), 16))
                table.setdefault(key, (m.group(3).replace("k_eControllerType_", ""), ln))
    return table


VIDPID_RE = re.compile(r"MAKE_VIDPID\(\s*0x([0-9a-fA-F]{4})\s*,\s*0x([0-9a-fA-F]{4})\s*\)")


def load_sdl_lists(path):
    lists = {}
    cur = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for ln, line in enumerate(f, 1):
            m = re.match(r"\s*static Uint32 initial_(\w+)\[\] = \{", line)
            if m:
                cur = m.group(1)
                lists[cur] = {}
                continue
            if cur:
                if line.strip().startswith("};"):
                    cur = None
                    continue
                if line.strip().startswith("//"):
                    continue
                for mm in VIDPID_RE.finditer(line):
                    lists[cur][(int(mm.group(1), 16), int(mm.group(2), 16))] = ln
    return lists


# ------------------------------------------- модель SDL (упрощённая) и нашего кода

USB_VENDOR_NINTENDO = 0x057E
JOYCON_LEFT = {0x2006, 0x2067}
JOYCON_RIGHT = {0x2007, 0x2066}
JOYCON_PAIR = {0x2008, 0x2068}
JOYCON_GRIP = 0x200E

CT_TO_TYPE = {  # SDL_GetGamepadTypeFromVIDPID(..., forUI=true), SDL_joystick.c:3059-3106
    "XBox360Controller": "xbox360",
    "XBoxOneController": "xboxone",
    "XBoxEliteController": "xboxone",
    "PS3Controller": "ps3",
    "PS4Controller": "ps4",
    "PS5Controller": "ps5",
    "PS5EdgeController": "ps5",
    "XInputPS4Controller": "ps4",
    "SwitchProController": "switchpro",
    "SwitchInputOnlyController": "switchpro",
    "XInputSwitchController": "switchpro",
    "SteamController": "steam",
    "SteamControllerV2": "steam",
    "SteamControllerNeptune": "steam",
    "SteamControllerTriton": "steam",
    "HoriSteamController": "steam",
    "UnknownSteamController": "steam",
}

TYPE_FROM_FIELD = {  # SDL_GetGamepadTypeFromString
    "unknown": "unknown", "standard": "standard", "xbox360": "xbox360", "xboxone": "xboxone",
    "ps3": "ps3", "ps4": "ps4", "ps5": "ps5", "switchpro": "switchpro", "joyconleft": "joyconleft",
    "joyconright": "joyconright", "joyconpair": "joyconpair", "gamecube": "gamecube", "steam": "steam",
}

# Типы, для которых на Windows раскладку без базы даёт драйвер XInput или HIDAPI с умолчаниями SDL_hints.h
# и нашими подсказками HIDAPI_XBOX/_ONE=1 (GamepadDeviceManager.cpp:139-140).
# НЕ входят: PS3Controller (SDL_HINT_JOYSTICK_HIDAPI_PS3 = 0 вне macOS), SteamController/V2
# (SDL_HINT_JOYSTICK_HIDAPI_STEAM = 0), HoriSteam/Triton (не разбирались), Unknown*/Apple/MobileTouch.
DRIVER_MAPPED_CT = {
    "XBox360Controller", "XBoxOneController", "XBoxEliteController", "XInputPS4Controller",
    "XInputSwitchController", "PS4Controller", "PS5Controller", "PS5EdgeController",
    "SwitchProController", "SwitchInputOnlyController", "SwitchJoyConLeft", "SwitchJoyConRight",
    "SwitchJoyConPair", "SteamControllerNeptune", "8BitDoController",
}

CLASS_A_TYPES = {"xbox360", "xboxone", "ps3", "ps4", "ps5", "switchpro", "joyconleft", "joyconright",
                 "joyconpair", "gamecube", "steam"}


def sdl_type_from_vidpid(vid, pid, cl, lists):
    if vid == USB_VENDOR_NINTENDO:
        if pid in JOYCON_LEFT:
            return "joyconleft"
        if pid in JOYCON_RIGHT:
            return "joyconright"
        if pid in JOYCON_PAIR:
            return "joyconpair"
        if pid == JOYCON_GRIP:
            return "joyconright"  # без имени "(L)"/"L+R" — SDL_joystick.c:3042-3049
    if (vid, pid) in lists.get("gamecube_devices", {}):
        return "gamecube"
    ct = cl.get((vid, pid), (None, None))[0]
    return CT_TO_TYPE.get(ct, "standard")


def our_class(sdl_type):
    """ClassifyGamepadType, GamepadDeviceManager.cpp:46-67."""
    return "A" if sdl_type in CLASS_A_TYPES else "B"


def our_glyphs(sdl_type, cls):
    """GamepadGlyphs.cpp:283-325 (без уточнения по face:/меткам, :328-346)."""
    if sdl_type in ("ps3", "ps4", "ps5"):
        return "playstation"
    if sdl_type in ("switchpro", "joyconleft", "joyconright", "joyconpair"):
        return "nintendo"
    if sdl_type == "gamecube":
        return "xbox(AXBY)"
    if sdl_type in ("xbox360", "xboxone", "steam"):
        return "xbox"
    return "generic" if cls == "B" else "xbox"


def ds4w_suppress_risk(vid, pid, sdl_type):
    """IsViGEmOrVirtualXbox360, GamepadDeviceManager.cpp:85-101: 045e:028e c типом xbox360
    подавляется, если одновременно подключено устройство Sony."""
    return sdl_type == "xbox360" and (vid, pid) == (0x045E, 0x028E)


def predict(vid, pid, db_idx, bi_idx, cl, lists):
    """Предсказание: как SDL и наш код увидят устройство с этим VID/PID на Windows."""
    notes = []
    key = (vid, pid)
    if key in lists.get("blacklist_devices", {}):
        return {"sdl": "hidden", "type": None, "cls": None, "glyphs": None, "role": "hidden",
                "notes": ["в чёрном списке SDL (SDL_joystick.c:%d)" % lists["blacklist_devices"][key]]}
    if key in lists.get("rog_gamepad_mice", {}):
        return {"sdl": "hidden", "type": None, "cls": None, "glyphs": None, "role": "hidden",
                "special": [], "mapped_by": [], "cl": cl.get(key),
                "notes": ["мышь ROG Chakram: SDL игнорирует без SDL_HINT_JOYSTICK_ROG_CHAKRAM (SDL_joystick.c:3474-3477)"]}
    if key == (0x28DE, 0x11FF):
        return {"sdl": "hidden", "type": None, "cls": None, "glyphs": None, "role": "steam-only",
                "special": [], "mapped_by": [], "cl": cl.get(key),
                "notes": ["Steam Virtual Gamepad: SDL скрывает его, если не задана переменная SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD (её ставит Steam при запуске игры через Steam) — SDL_gamepad.c:3292-3305"]}
    special = []
    for lname, label in (("wheel_devices", "руль"), ("flightstick_devices", "флайтстик"),
                         ("throttle_devices", "РУД"), ("arcadestick_devices", "аркадный стик"),
                         ("rog_gamepad_mice", "мышь ROG с режимом геймпада")):
        if key in lists.get(lname, {}):
            special.append("%s по списку SDL (SDL_joystick.c:%d)" % (label, lists[lname][key]))
    db_hits = db_idx.get(key, [])
    bi_hits = bi_idx.get(key, [])
    ct = cl.get(key)
    mapped_by = []
    if db_hits:
        mapped_by.append("gamecontrollerdb:%s" % ",".join(str(h["line"]) for h in db_hits[:4]) + ("…" if len(db_hits) > 4 else ""))
    if bi_hits:
        mapped_by.append("встроенная база SDL:%s" % ",".join(str(h["line"]) for h in bi_hits[:4]))
    # тип: поле type: в маппинге важнее таблицы VID/PID
    field_type = None
    for h in db_hits + bi_hits:
        t = h["fields"].get("type")
        if t:
            field_type = TYPE_FROM_FIELD.get(t.lower(), "unknown")
            break
    sdl_type = field_type or sdl_type_from_vidpid(vid, pid, cl, lists)
    is_console_ct = ct is not None and ct[0] in DRIVER_MAPPED_CT
    if special and "руль" in special[0]:
        notes.append("HIDAPI не создаёт автоматическую раскладку для рулей (SDL_gamepad.c:1114-1118)")
    if db_hits or bi_hits:
        sdl = "gamepad"
    elif is_console_ct and not special:
        sdl = "gamepad"
        notes.append("раскладку без базы даёт драйвер HIDAPI/XInput по типу %s (controller_list.h:%d)" % (ct[0], ct[1]))
    else:
        sdl = "joystick"
        if ct is not None:
            notes.append("тип %s (controller_list.h:%d), но драйвер HIDAPI для него на Windows по умолчанию выключен или не разбирался" % (ct[0], ct[1]))
    if sdl == "joystick" and not special and key != (0x28DE, 0x11FF):
        notes.append("если устройство придёт через XInput, SDL всё равно сделает его геймпадом типа xboxone (SDL_gamepad.c:1460-1464, SDL_joystick.c:3115-3119) — офлайн не предсказать")
    if sdl == "gamepad":
        cls = our_class(sdl_type)
        role = "gamepad"
        glyphs = our_glyphs(sdl_type, cls)
    else:
        sdl_type, cls, glyphs, role = "unknown", "C", None, "listed-not-active"
    if ds4w_suppress_risk(vid, pid, sdl_type):
        notes.append("подавляется фильтром DS4Windows при подключённом геймпаде Sony (GamepadDeviceManager.cpp:98)")
    if len({h["raw"].split(",", 2)[2] for h in db_hits}) > 1:
        notes.append("в gamecontrollerdb %d разных раскладок на один VID/PID — SDL возьмёт одну по полному GUID, для остальных клонов кнопки могут перепутаться" % len({h["raw"].split(",", 2)[2] for h in db_hits}))
    return {"sdl": sdl, "type": sdl_type, "cls": cls, "glyphs": glyphs, "role": role,
            "special": special, "mapped_by": mapped_by, "cl": ct, "notes": notes}


def verdict(dev, pr):
    if pr["role"] == "steam-only":
        return "OK*"
    if pr["role"] == "hidden":
        return "MISMATCH" if dev["expect_role"] == "gamepad" else "OK"
    if dev["expect_role"] == "ignore":
        if pr["role"] == "gamepad":
            return "MISMATCH"
        return "OK*"  # класс C: не управляет, но виден в списке и в мастере
    if pr["role"] != "gamepad":
        return "MISMATCH"
    if dev.get("expect_type") and pr["type"] != dev["expect_type"]:
        return "MISMATCH"
    eg = dev.get("expect_glyphs", "any")
    if eg != "any" and pr["glyphs"] and not pr["glyphs"].startswith(eg):
        return "MISMATCH"
    return "OK"


# ------------------------------------------------------------------- отчёт


def fmt_id(vid, pid):
    return "%04x:%04x" % (vid, pid)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--matrix", default=os.path.join(HERE, "device_matrix.json"))
    ap.add_argument("--data", default=DATA)
    ap.add_argument("--out", help="записать отчёт Markdown в файл (UTF-8 без BOM)")
    ap.add_argument("--strict", action="store_true", help="код возврата 1 при расхождениях")
    a = ap.parse_args()

    db = load_gamecontrollerdb(os.path.join(a.data, "gamecontrollerdb.txt"))
    bi = load_builtin_db(os.path.join(a.data, "SDL_gamepad_db.h"))
    cl = load_controller_list(os.path.join(a.data, "controller_list.h"))
    lists = load_sdl_lists(os.path.join(a.data, "SDL_joystick.c"))
    with open(a.matrix, encoding="utf-8") as f:
        matrix = json.load(f)

    def index(entries):
        idx = defaultdict(list)
        noid = 0
        for e in entries:
            v = guid_vidpid(e["guid"])
            if v is None:
                noid += 1
                continue
            e["vid"], e["pid"], e["drv"] = v
            idx[(v[0], v[1])].append(e)
        return idx, noid

    db_idx, db_noid = index(db)
    bi_idx, bi_noid = index(bi)

    L = []
    w = L.append
    w("# Отчёт check_mapping.py")
    w("")
    w("Предсказание по открытым базам (статус: *следует из исходников конкретной версии*), не проверка на железе.")
    w("")
    w("## Входные данные")
    w("")
    w("| База | Записей для Windows | Без VID/PID в GUID | Уникальных VID/PID |")
    w("|---|---|---|---|")
    w("| gamecontrollerdb.txt | %d | %d | %d |" % (len(db), db_noid, len(db_idx)))
    w("| SDL_gamepad_db.h (XINPUT/WGI/DINPUT) | %d | %d | %d |" % (len(bi), bi_noid, len(bi_idx)))
    w("| controller_list.h (VID/PID → тип) | %d | — | %d |" % (len(cl), len(cl)))
    w("| SDL_joystick.c: рули / флайтстики / РУД / аркадные / чёрный список | %d / %d / %d / %d / %d | — | — |" % (
        len(lists.get("wheel_devices", {})), len(lists.get("flightstick_devices", {})),
        len(lists.get("throttle_devices", {})), len(lists.get("arcadestick_devices", {})),
        len(lists.get("blacklist_devices", {}))))
    w("")

    # --- A. наша таблица
    w("## A. Наша таблица (device_matrix.json) против баз")
    w("")
    w("Два варианта: **сейчас** — только встроенная база SDL (в лаборатории gamecontrollerdb.txt не найден: "
      "evidence/batch-4-run2-xray.log:162, загрузка — GamepadDeviceManager.cpp:199-245); "
      "**+gcdb** — если положить gamecontrollerdb.txt в один из путей GamepadDeviceManager.cpp:208-211.")
    w("")
    w("| Устройство | VID:PID | Сейчас: SDL/тип/класс/значки | Итог сейчас | +gcdb: SDL/тип/класс/значки | Итог +gcdb | Ожидали | Пояснения |")
    w("|---|---|---|---|---|---|---|---|")
    counts = Counter()
    counts_db = Counter()
    mism = []
    empty_idx = {}

    def cell(pr):
        return "%s / %s / %s / %s" % (pr["sdl"], pr["type"] or "—", pr["cls"] or "—", pr["glyphs"] or "—")

    for dev in matrix["devices"]:
        for sid in dev["ids"]:
            vid, pid = (int(x, 16) for x in sid.split(":"))
            pr = predict(vid, pid, empty_idx, bi_idx, cl, lists)
            prd = predict(vid, pid, db_idx, bi_idx, cl, lists)
            v = verdict(dev, pr)
            vd = verdict(dev, prd)
            counts[v] += 1
            counts_db[vd] += 1
            exp = "%s/%s/%s" % (dev["expect_role"], dev.get("expect_type") or "—", dev.get("expect_glyphs", "any"))
            expl = "; ".join(prd.get("special", []) + prd.get("mapped_by", []) + prd["notes"])
            w("| %s | %s | %s | **%s** | %s | **%s** | %s | %s |" % (
                dev["name"], sid, cell(pr), v, cell(prd), vd, exp, expl or ""))
            if v == "MISMATCH" or vd == "MISMATCH":
                mism.append((dev, sid, pr, prd, v, vd))
    w("")
    w("Итого строк: %d. Сейчас — OK: %d; OK*: %d; MISMATCH: %d. С gcdb — OK: %d; OK*: %d; MISMATCH: %d." % (
        sum(counts.values()), counts["OK"], counts["OK*"], counts["MISMATCH"],
        counts_db["OK"], counts_db["OK*"], counts_db["MISMATCH"]))
    w("")
    w("OK* — устройство не управляет игрой (класс C, не участвует в выборе активного: GamepadDeviceManager.cpp:763-764, "
      "или скрыто SDL без Steam), но видно в списке устройств и доступно мастеру класса C.")
    w("")

    # --- B. рули/флайтстики в базе раскладок
    w("## B. Рули, флайтстики и РУД, у которых в базах есть раскладка геймпада")
    w("")
    w("Наш код сделает такое устройство классом A/B, и оно сможет стать активным «последним тронутым» (D36). "
      "Аркадные стики — по сути кнопочные геймпады, для них это допустимо; рули/флайтстики/РУД — нет. "
      "Мыши ROG Chakram исключены: SDL скрывает их целиком (SDL_joystick.c:3474-3477).")
    w("")
    special_keys = {}
    for lname in ("wheel_devices", "flightstick_devices", "throttle_devices", "arcadestick_devices", "rog_gamepad_mice"):
        for k in lists.get(lname, {}):
            special_keys.setdefault(k, lname)
    rows_b = []
    for k, lname in sorted(special_keys.items()):
        hits = db_idx.get(k, []) + bi_idx.get(k, [])
        if lname == "rog_gamepad_mice":
            continue  # скрыты SDL целиком (SDL_joystick.c:3474-3477)
        if hits:
            rows_b.append((k, lname, hits))
    w("| VID:PID | Список SDL | Где раскладка | Имя в базе |")
    w("|---|---|---|---|")
    for k, lname, hits in rows_b:
        where = ", ".join(("gcdb:%d" % h["line"]) if "raw" in h else ("builtin:%d" % h["line"]) for h in hits[:5])
        w("| %s | %s | %s | %s |" % (fmt_id(*k), lname, where, hits[0]["name"]))
    w("")
    n_bad = sum(1 for r in rows_b if r[1] in ("wheel_devices", "flightstick_devices", "throttle_devices"))
    w("Найдено: %d VID/PID (из них рули/флайтстики/РУД: %d, аркадные стики: %d) из %d в списках SDL без мышей ROG." % (
        len(rows_b), n_bad, len(rows_b) - n_bad, len([k for k, l in special_keys.items() if l != "rog_gamepad_mice"])))
    w("")

    KW = re.compile(r"wheel|racing|hotas|flight|throttle|pedal|rudder|yoke|t\.16000|extreme 3d|x52|x56|x-56|joystick", re.I)
    kw_hits = [e for e in db if KW.search(e["name"])]
    w("### B2. Записи gamecontrollerdb (Windows) с «рулевыми/лётными» словами в имени")
    w("")
    w("Слова: wheel, racing, hotas, flight, throttle, pedal, rudder, yoke, T.16000, Extreme 3D, X52/X56, joystick. "
      "Слово *joystick* часто встречается и у обычных геймпадов — это кандидаты для ручного просмотра, не вердикт.")
    w("")
    w("| Строка | GUID VID:PID | Имя |")
    w("|---|---|---|")
    for e in kw_hits:
        idt = fmt_id(e["vid"], e["pid"]) if "vid" in e else "—"
        w("| %d | %s | %s |" % (e["line"], idt, e["name"]))
    w("")
    w("Найдено: %d записей." % len(kw_hits))
    w("")

    # --- C. распределение по классам и значкам для всей базы
    w("## C. Как наш код разложит все записи gamecontrollerdb (Windows) с VID/PID")
    w("")
    cls_c = Counter()
    gly_c = Counter()
    supp = []
    for k, hits in db_idx.items():
        pr = predict(k[0], k[1], db_idx, bi_idx, cl, lists)
        cls_c[pr["cls"]] += 1
        gly_c[pr["glyphs"]] += 1
        if ds4w_suppress_risk(k[0], k[1], pr["type"]):
            supp.append(k)
    w("| Класс | VID/PID |")
    w("|---|---|")
    for kk in ("A", "B", "C", None):
        if cls_c.get(kk):
            w("| %s | %d |" % (kk or "скрыто SDL", cls_c[kk]))
    w("")
    w("| Значки | VID/PID |")
    w("|---|---|")
    for g, n in gly_c.most_common():
        w("| %s | %d |" % (g or "—", n))
    w("")

    # --- D. одна и та же модель: разные раскладки во встроенной базе и в gcdb
    w("## D. Один VID/PID — разные раскладки")
    w("")

    def norm(fields):
        return ",".join(sorted("%s:%s" % (k, v) for k, v in fields.items() if k not in ("platform", "crc", "hint", "sdk>=", "sdk<=")))

    dup_gcdb = sum(1 for k, hits in db_idx.items() if len(hits) > 1)
    amb = []
    for k, hits in db_idx.items():
        bmaps = {norm(h["fields"]) for h in bi_idx.get(k, []) if "DINPUT" in h.get("section", "")}
        if not bmaps:
            continue
        gmaps = {norm(h["fields"]) for h in hits}
        if gmaps - bmaps:
            amb.append((k, hits[0]["line"], ",".join(str(h["line"]) for h in bi_idx[k] if "DINPUT" in h.get("section", "")), hits[0]["name"]))
    amb.sort()
    w("Внутри раздела Windows gamecontrollerdb VID/PID с несколькими записями: %d (база держит одну запись на модель)." % dup_gcdb)
    w("")
    w("Если положить gamecontrollerdb.txt, его раскладка заменит встроенную раскладку SDL (секция DINPUT) "
      "у **%d** VID/PID — для них кнопки могут поменяться относительно того, что проверено без базы. "
      "Ниже первые 25 (строка gcdb / строки встроенной базы):" % len(amb))
    w("")
    w("| VID:PID | gcdb | встроенная | Имя |")
    w("|---|---|---|---|")
    for r in amb[:25]:
        w("| %s | %d | %s | %s |" % (fmt_id(*r[0]), r[1], r[2], r[3]))
    w("")

    # --- E. тип по таблице и тип по полю type:
    w("## E. Расхождения «тип по таблице VID/PID» и «поле type: в базе»")
    w("")
    conf = []
    for k, hits in db_idx.items():
        for h in hits:
            t = h["fields"].get("type")
            if t:
                tv = sdl_type_from_vidpid(k[0], k[1], cl, lists)
                tf = TYPE_FROM_FIELD.get(t.lower(), "unknown")
                if tv != "standard" and tv != tf:
                    conf.append((k, h["line"], tv, tf, h["name"]))
    n_type_field = sum(1 for e in db if e["fields"].get("type"))
    n_face_field = sum(1 for e in db if e["fields"].get("face"))
    w("Записей с полем `type:`: %d; с полем `face:`: %d; расхождений с таблицей: %d." % (n_type_field, n_face_field, len(conf)))
    for k, ln, tv, tf, nm in conf[:20]:
        w("- %s строка %d: таблица → %s, поле → %s (%s)" % (fmt_id(*k), ln, tv, tf, nm))
    w("")

    # --- F. 045e:028e
    w("## F. Подавление фильтром DS4Windows")
    w("")
    w("Тип xbox360 с VID:PID 045e:028e подавляется, когда подключён геймпад Sony (GamepadDeviceManager.cpp:85-101, решение D1.1-N3). "
      "Под это попадают: проводной Xbox 360, виртуальный геймпад DS4Windows/ViGEm, 8BitDo и многие клоны в режиме X. "
      "VID/PID из базы с таким риском: %s." % (", ".join(fmt_id(*k) for k in supp) or "нет"))
    w("")

    # --- итог
    w("## Итог")
    w("")
    w("- Наша таблица: %d строк; MISMATCH сейчас: %d; MISMATCH с gcdb: %d." % (sum(counts.values()), counts["MISMATCH"], counts_db["MISMATCH"]))
    for dev, sid, pr, prd, v, vd in mism:
        w("  - %s (%s): сейчас %s → %s; с gcdb %s → %s; ожидали %s/%s/%s" % (
            dev["name"], sid, cell(pr), v, cell(prd), vd,
            dev["expect_role"], dev.get("expect_type") or "—", dev.get("expect_glyphs")))
    w("- Устройства из спецсписков SDL (без мышей ROG) с раскладкой геймпада в базах: %d, из них рули/флайтстики/РУД: %d." % (len(rows_b), n_bad))
    w("- VID/PID, у которых gcdb меняет встроенную раскладку SDL: %d." % len(amb))
    w("")

    text = "\n".join(L) + "\n"
    if a.out:
        with open(a.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("report: %s; rows=%d | now OK=%d OK*=%d MISMATCH=%d | +gcdb OK=%d OK*=%d MISMATCH=%d | special-with-mapping=%d (wheel/flight/throttle=%d); gcdb-overrides-builtin=%d" % (
            a.out, sum(counts.values()), counts["OK"], counts["OK*"], counts["MISMATCH"],
            counts_db["OK"], counts_db["OK*"], counts_db["MISMATCH"], len(rows_b), n_bad, len(amb)))
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stdout.write(text)
    return 1 if (a.strict and (counts["MISMATCH"] or counts_db["MISMATCH"])) else 0


if __name__ == "__main__":
    sys.exit(main())
