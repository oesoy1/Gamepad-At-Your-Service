# Установка и удаление

[In English](../en/INSTALL.md) / [На главную](../../README.ru.md)

Скачайте нужный архив `.zip` в разделе [Releases](../../../releases):
- `Gamepad-At-Your-Service-vX.Y.Z-gamma-monolith.zip` для обычной S.T.A.L.K.E.R. G.A.M.M.A. (`AnomalyDX11AVX.exe`, `AnomalyDX11.exe`, `SDL3.dll`).
- `Gamepad-At-Your-Service-vX.Y.Z-gamma-monolith-dlss.zip` для G.A.M.M.A. с DX12-мостом, DLSS, генерацией кадров и FSR 3 (`AnomalyDX12-DLSS.exe`, `SDL3.dll`, библиотеки DLSS/FSR/Streamline/D3D12 и патч шейдеров DLSS). Для генерации кадров включите планирование GPU с аппаратным ускорением (HAGS) в настройках графики Windows и отключите MSAA с вертикальной синхронизацией в игре.

Перед установкой или обновлением файлов движка полностью закройте игру.

## Установка в G.A.M.M.A.

1. Перетащите скачанный `.zip` прямо в окно Mod Organizer 2 (или нажмите `Install a new mod from an archive`) и подтвердите имя мода `GAMMA Gamepad & Tactical UI`. Поставьте галочку напротив мода и перетащите его в самый низ левого списка прямо над `G.A.M.M.A. End of List_separator`. Моды `446- Quick Action Wheel - HarukaSai` и `G.A.M.M.A. Quick Action Wheel Balance` оставьте включёнными выше.
2. Нажмите правой кнопкой по моду `GAMMA Gamepad & Tactical UI` в MO2, выберите `Open in Explorer` (Открыть в проводнике) и запустите `Установить_движок.cmd` (или `Install_Engine.cmd`). Скрипт сам найдёт папку вашей Anomaly через `ModOrganizer.ini`, сохранит оригинальные файлы в `<Anomaly>\bin\_gamepad_backup\` и установит файлы движка с проверкой контрольных сумм. Для версии `gamma-monolith-dlss` выберите в MO2 запуск файла `<Anomaly>\bin\AnomalyDX12-DLSS.exe`.
3. Выключите систему ввода Steam (`Свойства -> Контроллер -> Отключить систему ввода Steam`) и закройте DS4Windows, reWASD и x360ce при подключении по кабелю или через адаптер Xbox, чтобы нажатия не задваивались.

Проверить правильность путей, контрольные суммы и порядок модов перед запуском можно из папки мода (скрипт работает только на чтение):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\verify.ps1"
```

В игре откройте `Настройки -> Управление -> Геймпад -> Другие настройки`, выберите значки `Dot Marks` и проверьте отклик осей и кнопок в окне `Проверка кнопок` (выход по удержанию `B` на 1 секунду). В мире памятка по кнопкам открывается сочетанием `LB + View`.

## После обновления через G.A.M.M.A. Launcher

Кнопка `Install / Update` в `G.A.M.M.A. Launcher` возвращает стандартный `.exe` в `<Anomaly>\bin\`. Настройки геймпада (`appdata\gamepad\profile.ltx`) и сохранения при этом не затрагиваются: откройте папку мода в проводнике и снова запустите `Установить_движок.cmd`. Скрипт обновит резервную копию новым стоковым файлом и вернёт движок с поддержкой геймпада. Повторный запуск `Установить_движок.cmd` никогда не затирает чистый бэкап файлами мода.

## Удаление мода

1. Откройте папку мода `GAMMA Gamepad & Tactical UI` из MO2 (`Open in Explorer`) и запустите `Вернуть_оригинал.cmd` (или `Restore_Original.cmd`). Он вернёт все оригинальные файлы из `<Anomaly>\bin\_gamepad_backup\`, удалит добавленные файлы мода и очистит папку `_gamepad_backup\`.
2. Снимите галочку с `GAMMA Gamepad & Tactical UI` в MO2 (или удалите мод).
3. При желании удалите папку `<Anomaly>\appdata\gamepad\` и лог `<Anomaly>\appdata\gamepad_last_error.log`.

В файлы сохранений `.scop` и `.scoc` мод ничего не пишет, сейвы загружаются без него как обычно.
