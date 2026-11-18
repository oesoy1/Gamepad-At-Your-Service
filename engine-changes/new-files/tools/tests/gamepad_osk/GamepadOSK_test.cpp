#define GPOSK_STANDALONE_TEST 1
#include "GamepadOnScreenKeyboard.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

namespace
{
    int g_passed = 0;
    int g_failed = 0;

    void Check(bool cond, const char* testName, const char* detail = "")
    {
        if (cond)
        {
            ++g_passed;
            std::printf("  [PASS] %s\n", testName);
        }
        else
        {
            ++g_failed;
            std::printf("  [FAIL] %s %s\n", testName, detail ? detail : "");
        }
    }
} // namespace

int main()
{
    std::printf("=== [F5.1 Unit Tests] GamepadOnScreenKeyboard (RU/EN, Case, Templates, Windows-1251) ===\n");

    // -------------------------------------------------------------------------
    // TC1: Все 32 заглавные русские буквы А..Я (0xC0..0xDF <-> U+0410..U+042F)
    // -------------------------------------------------------------------------
    {
        bool okUpper32 = true;
        for (uint8_t b = 0xC0; b <= 0xDF; ++b)
        {
            const std::string cp(1, static_cast<char>(b));
            const std::string utf8 = gposk::Cp1251ToUtf8(cp);
            size_t unmapped = 99;
            const std::string back = gposk::Utf8ToCp1251(utf8, &unmapped);
            if (!gposk::IsRussianUpperLetterCp1251(b) ||
                utf8.size() != 2 ||
                utf8.find('?') != std::string::npos ||
                unmapped != 0 ||
                back != cp ||
                back.find('?') != std::string::npos)
            {
                okUpper32 = false;
                break;
            }
        }
        Check(okUpper32, "TC01_all_32_uppercase_A_Ya_cp1251_utf8_roundtrip_no_question_mark");
    }

    // -------------------------------------------------------------------------
    // TC2: Все 32 строчные русские буквы а..я (0xE0..0xFF <-> U+0430..U+044F)
    // -------------------------------------------------------------------------
    {
        bool okLower32 = true;
        for (uint32_t b32 = 0xE0; b32 <= 0xFF; ++b32)
        {
            const uint8_t b = static_cast<uint8_t>(b32);
            const std::string cp(1, static_cast<char>(b));
            const std::string utf8 = gposk::Cp1251ToUtf8(cp);
            size_t unmapped = 99;
            const std::string back = gposk::Utf8ToCp1251(utf8, &unmapped);
            if (!gposk::IsRussianLowerLetterCp1251(b) ||
                utf8.size() != 2 ||
                utf8.find('?') != std::string::npos ||
                unmapped != 0 ||
                back != cp ||
                back.find('?') != std::string::npos)
            {
                okLower32 = false;
                break;
            }
        }
        Check(okLower32, "TC02_all_32_lowercase_a_ya_cp1251_utf8_roundtrip_no_question_mark");
    }

    // -------------------------------------------------------------------------
    // TC3: Буквы Ё (0xA8 <-> U+0401, UTF-8 D0 81) и ё (0xB8 <-> U+0451, UTF-8 D1 91)
    // -------------------------------------------------------------------------
    {
        const std::string yoCapCp(1, static_cast<char>(0xA8));
        const std::string yoSmlCp(1, static_cast<char>(0xB8));
        const std::string yoCapUtf8 = gposk::Cp1251ToUtf8(yoCapCp);
        const std::string yoSmlUtf8 = gposk::Cp1251ToUtf8(yoSmlCp);

        size_t unm1 = 99, unm2 = 99;
        const std::string backCap = gposk::Utf8ToCp1251(yoCapUtf8, &unm1);
        const std::string backSml = gposk::Utf8ToCp1251(yoSmlUtf8, &unm2);

        const bool okYo =
            yoCapUtf8.size() == 2 && static_cast<uint8_t>(yoCapUtf8[0]) == 0xD0 && static_cast<uint8_t>(yoCapUtf8[1]) == 0x81 &&
            yoSmlUtf8.size() == 2 && static_cast<uint8_t>(yoSmlUtf8[0]) == 0xD1 && static_cast<uint8_t>(yoSmlUtf8[1]) == 0x91 &&
            unm1 == 0 && backCap == yoCapCp &&
            unm2 == 0 && backSml == yoSmlCp &&
            gposk::ToLowerCp1251(0xA8) == 0xB8 &&
            gposk::ToUpperCp1251(0xB8) == 0xA8;
        Check(okYo, "TC03_special_letters_Yo_0xA8_and_yo_0xB8_roundtrip_and_case");
    }

    // -------------------------------------------------------------------------
    // TC4: Полная проверка всех 66 русских букв (а..я, А..Я, ё, Ё) одним блоком
    // -------------------------------------------------------------------------
    {
        std::string report;
        const bool ok66 = gposk::VerifyAll66RussianLettersRoundtrip(&report);
        Check(ok66, "TC04_verify_all_66_russian_letters_roundtrip_and_grid_presence", report.c_str());
    }

    // -------------------------------------------------------------------------
    // TC5: Ввод всех 33 строчных русских букв (а..я + ё) нажатиями A на сетке RU (ЙЦУКЕН)
    // -------------------------------------------------------------------------
    {
        gposk::OnScreenKeyboardController ctrl;
        ctrl.OpenSession(gposk::OskTargetKind::GenericEdit, "", 0, 100);
        ctrl.SetLanguage(gposk::OskLanguage::RU);
        ctrl.SetUpperCase(false);

        std::string expectedLower33;
        for (uint32_t b = 0xE0; b <= 0xFF; ++b)
            expectedLower33.push_back(static_cast<char>(b));
        expectedLower33.push_back(static_cast<char>(0xB8)); // 'ё'

        bool allFoundAndTyped = true;
        for (char c : expectedLower33)
        {
            const uint8_t target = static_cast<uint8_t>(c);
            int32_t r = -1, col = -1;
            if (!ctrl.FindCharOnGrid(gposk::OskLanguage::RU, false, target, r, col))
            {
                allFoundAndTyped = false;
                break;
            }
            ctrl.SetFocusCell(r, col);
            ctrl.PressFocusedCell(0);
        }

        Check(allFoundAndTyped && ctrl.GetBufferCp1251() == expectedLower33 &&
              ctrl.GetBufferCp1251().size() == 33 &&
              ctrl.GetBufferCp1251().find('?') == std::string::npos,
              "TC05_type_all_33_lowercase_russian_letters_on_ru_grid");
    }

    // -------------------------------------------------------------------------
    // TC6: Переключение регистра (L3/LT) и ввод всех 33 заглавных русских букв (А..Я + Ё) на сетке RU
    // -------------------------------------------------------------------------
    {
        gposk::OnScreenKeyboardController ctrl;
        ctrl.OpenSession(gposk::OskTargetKind::GenericEdit, "", 0, 200);
        ctrl.SetLanguage(gposk::OskLanguage::RU);
        // Нажимаем L3 для включения верхнего регистра
        ctrl.StepController(0, false, true, false, false, gpfocus::NavDir::Up, 210);
        Check(ctrl.IsUpperCase(), "TC06a_l3_toggles_uppercase_on");

        std::string expectedUpper33;
        for (uint8_t b = 0xC0; b <= 0xDF; ++b)
            expectedUpper33.push_back(static_cast<char>(b));
        expectedUpper33.push_back(static_cast<char>(0xA8)); // 'Ё'

        bool allFoundAndTyped = true;
        for (char c : expectedUpper33)
        {
            const uint8_t target = static_cast<uint8_t>(c);
            int32_t r = -1, col = -1;
            if (!ctrl.FindCharOnGrid(gposk::OskLanguage::RU, true, target, r, col))
            {
                allFoundAndTyped = false;
                break;
            }
            ctrl.SetFocusCell(r, col);
            ctrl.PressFocusedCell(0);
        }

        Check(allFoundAndTyped && ctrl.GetBufferCp1251() == expectedUpper33 &&
              ctrl.GetBufferCp1251().size() == 33 &&
              ctrl.GetBufferCp1251().find('?') == std::string::npos,
              "TC06b_type_all_33_uppercase_russian_letters_on_ru_grid");
    }

    // -------------------------------------------------------------------------
    // TC7: Переключение языка (R3 / LB / RB) на EN (QWERTY) и ввод всех 26 букв a..z и A..Z
    // -------------------------------------------------------------------------
    {
        gposk::OnScreenKeyboardController ctrl;
        ctrl.OpenSession(gposk::OskTargetKind::GenericEdit, "", 0, 300);
        // Нажимаем R3 для переключения RU -> EN
        ctrl.StepController(0, false, false, true, false, gpfocus::NavDir::Up, 310);
        Check(ctrl.GetLanguage() == gposk::OskLanguage::EN, "TC07a_r3_switches_language_to_EN");

        std::string expectedAzLower;
        for (char c = 'a'; c <= 'z'; ++c)
        {
            expectedAzLower.push_back(c);
            int32_t r = -1, col = -1;
            if (ctrl.FindCharOnGrid(gposk::OskLanguage::EN, false, static_cast<uint8_t>(c), r, col))
            {
                ctrl.SetFocusCell(r, col);
                ctrl.PressFocusedCell(0);
            }
        }
        Check(ctrl.GetBufferCp1251() == expectedAzLower, "TC07b_type_all_26_english_lowercase_letters_qwerty");

        ctrl.ClearBuffer();
        ctrl.ToggleCase();
        std::string expectedAzUpper;
        for (char c = 'A'; c <= 'Z'; ++c)
        {
            expectedAzUpper.push_back(c);
            int32_t r = -1, col = -1;
            if (ctrl.FindCharOnGrid(gposk::OskLanguage::EN, true, static_cast<uint8_t>(c), r, col))
            {
                ctrl.SetFocusCell(r, col);
                ctrl.PressFocusedCell(0);
            }
        }
        Check(ctrl.GetBufferCp1251() == expectedAzUpper, "TC07c_type_all_26_english_uppercase_letters_qwerty");
    }

    // -------------------------------------------------------------------------
    // TC8: Цифровой ряд (1..9, 0, -, _)
    // -------------------------------------------------------------------------
    {
        gposk::OnScreenKeyboardController ctrl;
        ctrl.OpenSession(gposk::OskTargetKind::GenericEdit, "", 0, 400);
        for (int32_t col = 0; col < 10; ++col)
        {
            ctrl.SetFocusCell(gposk::OnScreenKeyboardController::kDigitRow, col);
            ctrl.PressFocusedCell(0);
        }
        Check(ctrl.GetBufferCp1251() == "1234567890", "TC08_digit_row_types_1234567890");
    }

    // -------------------------------------------------------------------------
    // TC9: Кнопка Y (пробел) и X (удалить / Backspace с автоповтором 320/90 мс)
    // -------------------------------------------------------------------------
    {
        gposk::OnScreenKeyboardController ctrl;
        ctrl.OpenSession(gposk::OskTargetKind::GenericEdit, "ABCD", 0, 500);

        // Y добавляет пробел
        ctrl.StepController(gpmodal::ModalButtonMask(gpmodal::ModalButton::Y), false, false, false, false, gpfocus::NavDir::Up, 510);
        ctrl.StepController(0, false, false, false, false, gpfocus::NavDir::Up, 520);
        Check(ctrl.GetBufferCp1251() == "ABCD ", "TC09a_button_Y_inserts_space");

        // Удержание X: на t=600 удаляет ' ', на t=925 (+325 мс >= 320 мс) удаляет 'D', на t=1020 (+95 мс >= 90 мс) удаляет 'C'
        const uint32_t xMask = gpmodal::ModalButtonMask(gpmodal::ModalButton::X);
        ctrl.StepController(xMask, false, false, false, false, gpfocus::NavDir::Up, 600);
        Check(ctrl.GetBufferCp1251() == "ABCD", "TC09b_button_X_initial_press_deletes_one_char");

        ctrl.StepController(xMask, false, false, false, false, gpfocus::NavDir::Up, 800); // 200 ms < 320 ms
        Check(ctrl.GetBufferCp1251() == "ABCD", "TC09c_button_X_before_320ms_no_repeat");

        ctrl.StepController(xMask, false, false, false, false, gpfocus::NavDir::Up, 925); // 325 ms >= 320 ms
        Check(ctrl.GetBufferCp1251() == "ABC", "TC09d_button_X_repeat_after_320ms");

        ctrl.StepController(xMask, false, false, false, false, gpfocus::NavDir::Up, 1020); // +95 ms >= 90 ms
        Check(ctrl.GetBufferCp1251() == "AB", "TC09e_button_X_repeat_step_90ms");
    }

    // -------------------------------------------------------------------------
    // TC10: Подтверждение по Start и по кнопке «Готово» (A на row=5, col=5)
    // -------------------------------------------------------------------------
    {
        gposk::OnScreenKeyboardController ctrl;
        ctrl.OpenSession(gposk::OskTargetKind::StashDialog, "", 0, 1000);
        ctrl.ApplyTemplateIndex(0); // "Оружие"
        ctrl.StepController(0, true, false, false, false, gpfocus::NavDir::Up, 1020); // Start
        Check(!ctrl.IsOpen() && ctrl.WasCommitted() && !ctrl.WasCancelled() &&
              ctrl.GetCommittedTextCp1251() == "\xCE\xF0\xF3\xE6\xE8\xE5",
              "TC10a_start_commits_and_closes_osk");

        ctrl.OpenSession(gposk::OskTargetKind::StashDialog, "", 0, 1100);
        ctrl.ApplyTemplateIndex(2); // "Медицина"
        ctrl.SetFocusCell(gposk::OnScreenKeyboardController::kActionRow, 5); // [Готово (Start)]
        ctrl.StepController(gpmodal::ModalButtonMask(gpmodal::ModalButton::A), false, false, false, false, gpfocus::NavDir::Up, 1120);
        Check(!ctrl.IsOpen() && ctrl.WasCommitted() &&
              ctrl.GetCommittedTextCp1251() == "\xCC\xE5\xE4\xE8\xF6\xE8\xED\xE0",
              "TC10b_action_done_button_A_commits_and_closes_osk");
    }

    // -------------------------------------------------------------------------
    // TC11: Отмена по B закрывает клавиатуру без ввода, сохраняет прежний текст и ставит барьер B (F1.2)
    // -------------------------------------------------------------------------
    {
        gposk::OnScreenKeyboardController ctrl;
        const std::string origCp1251 = "\xD1\xF2\xE0\xF0\xEE\xE5\x20\xE8\xEC\xFF"; // "Старое имя"
        ctrl.OpenSession(gposk::OskTargetKind::SaveDialog, origCp1251, 0, 2000);
        Check(ctrl.GetModalStack().GetDepth() == 1, "TC11a_modal_stack_depth_is_1_when_osk_open");

        // Меняем буфер внутри клавиатуры
        ctrl.ApplyTemplateIndex(1); // "Перед боем"
        Check(ctrl.GetBufferCp1251() != origCp1251, "TC11b_buffer_modified_before_cancel");

        // Нажимаем B (GP_BTN_EAST)
        const uint32_t bMask = gpmodal::ModalButtonMask(gpmodal::ModalButton::B);
        ctrl.StepController(bMask, false, false, false, false, gpfocus::NavDir::Up, 2050);

        Check(!ctrl.IsOpen() && ctrl.WasCancelled() && !ctrl.WasCommitted() &&
              ctrl.GetCommittedTextCp1251() == origCp1251 &&
              ctrl.GetModalStack().GetDepth() == 0 &&
              ctrl.GetModalStack().IsButtonConsumedByBarrier(gpmodal::ModalButton::B),
              "TC11c_button_B_cancels_without_modifying_original_text_and_arms_barrier");
    }

    // -------------------------------------------------------------------------
    // TC12: Входной барьер F1.2: зажатая при открытии кнопка A не печатает букву до отпускания
    // -------------------------------------------------------------------------
    {
        const uint32_t aMask = gpmodal::ModalButtonMask(gpmodal::ModalButton::A);
        gposk::OnScreenKeyboardController ctrl;
        ctrl.OpenSession(gposk::OskTargetKind::GenericEdit, "", aMask, 3000);

        // В первых кадрах A всё ещё физически удерживается после клика по полю ввода
        ctrl.StepController(aMask, false, false, false, false, gpfocus::NavDir::Up, 3016);
        ctrl.StepController(aMask, false, false, false, false, gpfocus::NavDir::Up, 3032);
        Check(ctrl.GetBufferCp1251().empty(), "TC12a_held_A_on_open_is_blocked_by_entry_barrier");

        // Отпускаем A и нажимаем снова — теперь печатает первую букву 'й' (0xE9)
        ctrl.StepController(0, false, false, false, false, gpfocus::NavDir::Up, 3048);
        ctrl.StepController(aMask, false, false, false, false, gpfocus::NavDir::Up, 3064);
        Check(ctrl.GetBufferCp1251().size() == 1 && static_cast<uint8_t>(ctrl.GetBufferCp1251()[0]) == 0xE9,
              "TC12b_repress_A_after_release_types_character");
    }

    // -------------------------------------------------------------------------
    // TC13: Подключение и шаблоны для всех 4 целевых окон из FP.1 п. 7
    // -------------------------------------------------------------------------
    {
        // 1) UISaveDialog (ui_save_dialog.script, edit_filename)
        const auto kSave = gposk::ClassifyEditTarget("edit_filename", "form", "UISaveDialog", true, false);
        Check(kSave == gposk::OskTargetKind::SaveDialog, "TC13a_classify_target_1_UISaveDialog");

        gposk::OnScreenKeyboardController ctrl;
        // Передаём локацию "Кордон" (\xCA\xEE\xF0\xE4\xEE\xED) и дату с точками и двоеточием "07.11 14:30"
        ctrl.OpenSession(kSave, "", 0, 4000, "\xCA\xEE\xF0\xE4\xEE\xED", "07.11 14:30");
        ctrl.ApplyTemplateIndex(0); // <Локация> — <Дата/Время>
        ctrl.CommitSession(0);
        const std::string save0 = ctrl.GetCommittedTextCp1251();
        Check(gposk::IsValidSaveFileNameCp1251(save0) &&
              save0 == "\xCA\xEE\xF0\xE4\xEE\xED \x97 07-11 14-30",
              "TC13b_save_template_location_datetime_cp1251_and_sanitized");

        ctrl.OpenSession(kSave, "", 0, 4010);
        ctrl.ApplyTemplateIndex(1); // "Перед боем"
        ctrl.CommitSession(0);
        Check(ctrl.GetCommittedTextCp1251() == "\xCF\xE5\xF0\xE5\xE4\x20\xE1\xEE\xE5\xEC" &&
              gposk::IsValidSaveFileNameCp1251(ctrl.GetCommittedTextCp1251()),
              "TC13c_save_template_pered_boem_cp1251");

        // 2) UICreateStash (item_backpack.script, fld_input)
        const auto kStash = gposk::ClassifyEditTarget("fld_input", "backpack", "UICreateStash", false, false);
        Check(kStash == gposk::OskTargetKind::StashDialog, "TC13d_classify_target_2_UICreateStash");
        ctrl.OpenSession(kStash, "", 0, 4020);
        ctrl.ApplyTemplateIndex(0); // "Оружие"
        Check(ctrl.GetBufferCp1251() == "\xCE\xF0\xF3\xE6\xE8\xE5", "TC13e_stash_template_0_Oruzhie");
        ctrl.ApplyTemplateIndex(1); // "Детали"
        Check(ctrl.GetBufferCp1251() == "\xC4\xE5\xF2\xE0\xEB\xE8", "TC13f_stash_template_1_Detali");
        ctrl.ApplyTemplateIndex(2); // "Медицина"
        Check(ctrl.GetBufferCp1251() == "\xCC\xE5\xE4\xE8\xF6\xE8\xED\xE0", "TC13g_stash_template_2_Medicina");

        // 3) UIWPSettings / UIPinSettingsWnd (tasks_placeable_waypoints.script)
        const auto kWp = gposk::ClassifyEditTarget("fld_input_name", "dialog", "UIWPSettings", false, false);
        const auto kPin = gposk::ClassifyEditTarget("fld_input98765", "dialog", "UIPinSettingsWnd", false, false);
        Check(kWp == gposk::OskTargetKind::WaypointPin && kPin == gposk::OskTargetKind::WaypointPin,
              "TC13h_classify_target_3_UIWPSettings_and_UIPinSettingsWnd");
        ctrl.OpenSession(kWp, "", 0, 4030);
        ctrl.ApplyTemplateIndex(0); // "Тайник"
        Check(ctrl.GetBufferCp1251() == "\xD2\xE0\xE9\xED\xE8\xEA", "TC13i_waypoint_template_0_Taynik");
        ctrl.ApplyTemplateIndex(1); // "Опасно"
        Check(ctrl.GetBufferCp1251() == "\xCE\xEF\xE0\xF1\xED\xEE", "TC13j_waypoint_template_1_Opasno");

        // 4) UINewGame (ui_mm_faction_select.script, input_name)
        const auto kNewGame = gposk::ClassifyEditTarget("input_name", "dialog", "UINewGame", true, false);
        Check(kNewGame == gposk::OskTargetKind::NewGameName, "TC13k_classify_target_4_UINewGame");
        ctrl.OpenSession(kNewGame, "", 0, 4040);
        ctrl.ApplyTemplateIndex(3); // "Дегтярёв" (с буквой ё = 0xB8)
        Check(ctrl.GetBufferCp1251() == "\xC4\xE5\xE3\xF2\xFF\xF0\xB8\xE2", "TC13l_newgame_template_Degtyaryov_with_yo_0xB8");
    }

    // -------------------------------------------------------------------------
    // TC14: Навигация Вверх/Вниз между 12-колоночной сеткой и 6-колоночным рядом шаблонов
    // -------------------------------------------------------------------------
    {
        gposk::OnScreenKeyboardController ctrl;
        ctrl.OpenSession(gposk::OskTargetKind::SaveDialog, "", 0, 5000);
        ctrl.SetFocusCell(gposk::OnScreenKeyboardController::kDigitRow, 7);
        ctrl.MoveFocus(gpfocus::NavDir::Up); // Переход в ряд шаблонов (col = 7 / 2 = 3)
        Check(ctrl.GetFocusRow() == gposk::OnScreenKeyboardController::kTemplateRow && ctrl.GetFocusCol() == 3,
              "TC14a_move_up_from_digit_col7_to_template_col3");

        ctrl.MoveFocus(gpfocus::NavDir::Down); // Возврат в цифровой ряд с восстановлением col = 7
        Check(ctrl.GetFocusRow() == gposk::OnScreenKeyboardController::kDigitRow && ctrl.GetFocusCol() == 7,
              "TC14b_move_down_restores_exact_key_col7");
    }

    std::printf("=== [F5.1 Summary] Passed: %d, Failed: %d ===\n", g_passed, g_failed);
    return (g_failed == 0) ? 0 : 1;
}
