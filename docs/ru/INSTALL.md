# Установка и удаление

[In English](../en/INSTALL.md) / [На главную](../../README.ru.md)

Скачайте подходящий архив `.zip` в разделе [Releases](../../../releases):
- `Gamepad-At-Your-Service-vX.Y.Z-gamma-monolith.zip` для обычной S.T.A.L.K.E.R. G.A.M.M.A. (`AnomalyDX11AVX.exe` / `AnomalyDX11.exe`).
- `Gamepad-At-Your-Service-vX.Y.Z-gamma-monolith-dlss.zip` для G.A.M.M.A. с DX12-мостом, DLSS, генерацией кадров и FSR 3 (`AnomalyDX12-DLSS.exe`). Для генерации кадров включите планирование GPU с аппаратным ускорением (HAGS) в настройках графики Windows и ставьте `r__framelimit` вдвое выше нужного потолка FPS.

Перед копированием закройте игру и Mod Organizer 2 и сохраните резервную копию папки `<Anomaly>\bin\`.

## Установка в G.A.M.M.A.

1. Сохраните оригинальные `AnomalyDX11AVX.exe`, `AnomalyDX11.exe` (и `SDL3.dll`, если он там был) из `<Anomaly>\bin\`, затем скопируйте содержимое `1_Copy_To_Anomaly_bin\` в `<Anomaly>\bin\` с заменой. Для версии `gamma-monolith-dlss` укажите в MO2 запуск файла `<Anomaly>\bin\AnomalyDX12-DLSS.exe`.
2. Переложите папку `GAMMA Gamepad & Tactical UI` из `2_Install_In_MO2_mods\` в `<GAMMA>\mods\` (или добавьте архивом через MO2). Нажмите `F5` в MO2, поставьте галочку напротив `GAMMA Gamepad & Tactical UI` и перетащите мод в самый низ списка прямо над `G.A.M.M.A. End of List_separator`. Моды `446- Quick Action Wheel - HarukaSai` и `G.A.M.M.A. Quick Action Wheel Balance` оставьте включёнными выше.
3. Выключите систему ввода Steam (`Свойства -> Контроллер -> Отключить систему ввода Steam`) и закройте DS4Windows, reWASD и x360ce при подключении по кабелю или через адаптер Xbox, чтобы нажатия не задваивались.

Проверить правильность путей и порядка модов перед запуском можно проверочным скриптом (он работает только на чтение):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "3_Verify_Installation_ReadOnly\verify.ps1" -AnomalyRoot "D:\Anomaly" -Mo2Root "D:\GAMMA"
```

В игре откройте `Настройки -> Управление -> Геймпад -> Другие настройки`, выберите значки `Dot Marks` и проверьте отклик осей и кнопок в окне `Проверка кнопок` (выход по удержанию `B` на 1 секунду). В мире памятка по кнопкам открывается сочетанием `LB + View`.

## После обновления через G.A.M.M.A. Launcher

Кнопка `Install / Update` в `G.A.M.M.A. Launcher` возвращает стандартный `.exe` в `<Anomaly>\bin\`. Настройки геймпада (`appdata\gamepad\profile.ltx`) и сохранения при этом не затрагиваются: достаточно заново скопировать файлы из `1_Copy_To_Anomaly_bin\` в `<Anomaly>\bin\`.

## Удаление мода

1. Снимите галочку с `GAMMA Gamepad & Tactical UI` в MO2 (или удалите папку мода).
2. Верните сохранённый оригинальный `.exe` в `<Anomaly>\bin\`.
3. При желании удалите папку `<Anomaly>\appdata\gamepad\` и лог `<Anomaly>\appdata\gamepad_last_error.log`.

В файлы сохранений `.scop` и `.scoc` мод ничего не пишет, сейвы загружаются без него как обычно.
