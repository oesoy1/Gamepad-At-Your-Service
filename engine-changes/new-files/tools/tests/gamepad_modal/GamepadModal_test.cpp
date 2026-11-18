#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <string>
#include <vector>

#include "GamepadModalStack.h"

using namespace gpfocus;
using namespace gpmodal;

namespace
{
    int g_total_tests     = 0;
    int g_passed_tests    = 0;
    int g_failed_tests    = 0;
    int g_old_regressions = 0;

    uint32_t FocusedNodeIdOf(const FocusGraph& g)
    {
        const FocusNode* n = g.GetFocusedNode();
        return n ? n->node_id : kInvalidNodeId;
    }

    void CheckCase(
        const char* case_id,
        const char* description,
        bool        new_passed,
        bool        evaluate_old = false,
        bool        old_passed   = true)
    {
        ++g_total_tests;
        if (new_passed)
        {
            ++g_passed_tests;
            if (evaluate_old && !old_passed)
            {
                ++g_old_regressions;
                std::printf("[PASS] %-38s | %-56s | OLD_BEHAVIOR: FAIL (REGRESSION CAUGHT)\n",
                    case_id, description);
            }
            else
            {
                std::printf("[PASS] %-38s | %s\n", case_id, description);
            }
        }
        else
        {
            ++g_failed_tests;
            std::printf("[FAIL] %-38s | %s\n", case_id, description);
        }
    }

    // =========================================================================
    // Блок 1: Вложенность стека модальных окон 1..3 уровней, закрытие строго
    //         одного верхнего окна по B и возврат фокуса на вызвавший узел
    // =========================================================================
    void TestBlock1_ModalNestingAndFocusRestore()
    {
        std::printf("\n--- Block 1: Modal Stack Nesting 1..3 Levels & Focus Return (13 cases) ---\n");

        FocusModalTestController ctrl;
        ctrl.PopulateSyntheticItems(18, 1, 100);

        // 1.1 Открытие уровня 1 (корневой список)
        ctrl.OpenRootModal(101, 0, 100);
        CheckCase(
            "B1.1_open_root_level1",
            "Open root modal level 1 -> depth=1, token=101, focus=node 1",
            ctrl.GetModalStack().GetDepth() == 1 &&
            ctrl.GetModalStack().GetTopLayer()->pause_token_id == 101 &&
            FocusedNodeIdOf(ctrl.GetActiveGraph()) == 1 &&
            ctrl.GetModalStack().GetTopDispatcherContextTag() == "GPModalStack:L1:gp_modal_L1_list#1");

        // 1.2 Перемещаем фокус на 5-й элемент (индекс 4, node_id=5) и открываем уровень 2
        for (int i = 0; i < 4; ++i)
            ctrl.StepNavigation(NavDir::Down, static_cast<uint32_t>(110 + i * 10));
        const uint32_t callerNodeL1 = FocusedNodeIdOf(ctrl.GetActiveGraph());
        const uint16_t callerObjL1  = ctrl.GetActiveGraph().GetFocusedNode()->stable_id.object_id;

        ctrl.OpenLevel2ActionModal(102, ModalButtonMask(ModalButton::A), 200);
        CheckCase(
            "B1.2_open_level2_action_modal",
            "Open level 2 over item #5 -> depth=2, saved caller node_id=5, distinct dispatcher tag",
            ctrl.GetModalStack().GetDepth() == 2 &&
            callerNodeL1 == 5 &&
            ctrl.GetModalStack().GetTopLayer()->pause_token_id == 102 &&
            ctrl.GetModalStack().GetTopLayer()->caller_focus.node_id == 5 &&
            ctrl.GetModalStack().GetTopLayer()->caller_focus.stable_id.object_id == callerObjL1 &&
            ctrl.GetModalStack().GetTopDispatcherContextTag() == "GPModalStack:L2:gp_modal_L2_actions#2");

        // 1.3 Внутри уровня 2 переходим на 2-й пункт (node_id=2) и открываем уровень 3
        ctrl.StepNavigation(NavDir::Down, 220);
        const uint32_t callerNodeL2 = FocusedNodeIdOf(ctrl.GetActiveGraph());

        ctrl.OpenLevel3ConfirmModal(103, ModalButtonMask(ModalButton::A), 300);
        CheckCase(
            "B1.3_open_level3_confirm_modal",
            "Open level 3 over L2 node 2 -> depth=3, saved caller node_id=2, distinct dispatcher tag",
            ctrl.GetModalStack().GetDepth() == 3 &&
            callerNodeL2 == 2 &&
            ctrl.GetModalStack().GetTopLayer()->pause_token_id == 103 &&
            ctrl.GetModalStack().GetTopLayer()->caller_focus.node_id == 2 &&
            ctrl.GetModalStack().GetTopDispatcherContextTag() == "GPModalStack:L3:gp_modal_L3_confirm#3");

        // 1.4 Навигация внутри уровня 3 («Да» -> «Нет», node_id=2) не затрагивает уровни 1 и 2
        ctrl.StepNavigation(NavDir::Down, 320);
        CheckCase(
            "B1.4_navigate_inside_level3_isolated",
            "Navigate inside L3 -> L3 focused=2, L1 focused remains 5",
            FocusedNodeIdOf(ctrl.GetActiveGraph()) == 2 &&
            FocusedNodeIdOf(ctrl.GetRootGraph()) == 5);

        // 1.5 Нажатие B на уровне 3: закрывает СТРОГО ТОЛЬКО уровень 3 (3 -> 2) и возвращает фокус на узел 2 в L2
        // (Старое поведение HideDialog без стека закрывало сразу весь экран: depth 3 -> 0)
        uint32_t releasedTok = 0;
        const bool pop3 = ctrl.CancelTopModal(ModalButtonMask(ModalButton::B), 10, 400, &releasedTok);
        CheckCase(
            "B1.5_cancel_B_pops_only_L3_to_L2",
            "Press B at L3 -> depth 3->2, token 103 released, focus restored to L2 caller node 2",
            pop3 &&
            ctrl.GetModalStack().GetDepth() == 2 &&
            releasedTok == 103 &&
            FocusedNodeIdOf(ctrl.GetActiveGraph()) == 2,
            true,
            false);

        // 1.6 Повторный вызов CancelTopModal в ТОТ ЖЕ КАДР (frame_id=10) блокируется защитой кадра
        uint32_t secondTokSameFrame = 0;
        const bool popSameFrame = ctrl.CancelTopModal(ModalButtonMask(ModalButton::B), 10, 400, &secondTokSameFrame);
        CheckCase(
            "B1.6_same_frame_double_pop_blocked",
            "Second B cancel in the exact same frame_id=10 is blocked (depth remains 2)",
            !popSameFrame &&
            ctrl.GetModalStack().GetDepth() == 2 &&
            secondTokSameFrame == 0,
            true,
            false);

        // 1.7 Отпускаем B на кадре 11 и нажимаем B снова на кадре 12: закрывает строго уровень 2 (2 -> 1), фокус на узле 5
        ctrl.GetModalStackMutable().BeginFrameButtons(0, 11, 416);
        const bool pop2 = ctrl.CancelTopModal(ModalButtonMask(ModalButton::B), 12, 432, &releasedTok);
        CheckCase(
            "B1.7_cancel_B_pops_only_L2_to_L1",
            "Release & press B at L2 -> depth 2->1, token 102 released, focus restored to L1 caller node 5",
            pop2 &&
            ctrl.GetModalStack().GetDepth() == 1 &&
            releasedTok == 102 &&
            FocusedNodeIdOf(ctrl.GetActiveGraph()) == 5 &&
            ctrl.GetActiveGraph().GetFocusedNode()->stable_id.object_id == callerObjL1,
            true,
            false);

        // 1.8 Если вызывавший предмет #5 в L1 был удалён пока было открыто окно L2, при закрытии L2 фокус восстанавливается по правилам F1.1
        ctrl.OpenLevel2ActionModal(104, 0, 450);
        ctrl.DeleteItemAtListIndex(4, 460); // удаляем вызывавший элемент #5 (индекс 4)
        ctrl.GetModalStackMutable().BeginFrameButtons(0, 13, 470);
        const bool pop2DeletedCaller = ctrl.CancelTopModal(ModalButtonMask(ModalButton::B), 14, 480, &releasedTok);
        const FocusNode* focusedAfterCallerDel = ctrl.GetActiveGraph().GetFocusedNode();
        CheckCase(
            "B1.8_cancel_L2_when_caller_item_deleted",
            "If caller item was deleted while L2 was open, closing L2 restores valid neighbor in L1",
            pop2DeletedCaller &&
            ctrl.GetModalStack().GetDepth() == 1 &&
            releasedTok == 104 &&
            focusedAfterCallerDel != nullptr &&
            focusedAfterCallerDel->kind == FocusNodeKind::Item,
            true,
            false);

        // 1.9 Закрытие последнего уровня L1 (1 -> 0) освобождает корневой токен 101
        ctrl.GetModalStackMutable().BeginFrameButtons(0, 15, 500);
        const bool pop1 = ctrl.CancelTopModal(ModalButtonMask(ModalButton::B), 16, 516, &releasedTok);
        CheckCase(
            "B1.9_cancel_B_pops_L1_to_empty",
            "Press B at L1 -> depth 1->0, root token 101 released",
            pop1 &&
            ctrl.GetModalStack().IsEmpty() &&
            releasedTok == 101);

        // 1.10 Нажатие B при пустом стеке безопасно возвращает false
        const bool popEmpty = ctrl.CancelTopModal(ModalButtonMask(ModalButton::B), 17, 532, &releasedTok);
        CheckCase(
            "B1.10_cancel_B_on_empty_stack_noop",
            "Press B on empty modal stack returns false without underflow",
            !popEmpty && ctrl.GetModalStack().IsEmpty());

        // 1.11 (Audit M3): если вызывавший предмет L1 был удалён/перестроен, пока открыто L2, а current_node_id в L1 указывает на другой узел,
        //                  RestoreToGraph сбрасывает current_node_id перед RebuildGroupItems и восстанавливает соседа вызывавшего предмета!
        {
            FocusModalTestController ctrlM3;
            ctrlM3.PopulateSyntheticItems(8, 1, 600);
            ctrlM3.OpenRootModal(301, 0, 605);
            ctrlM3.GetRootGraphMutable().SetFocusedNode(0, 4, true); // предмет #4 (индекс 3, obj_id=503)
            ctrlM3.OpenLevel2ActionModal(302, 0, 610);

            // Удаляем вызывавший предмет #4 (индекс 3) в фоне и искусственно переставляем current_node_id в L1 на предмет #1 (node_id=1)
            ctrlM3.DeleteItemAtListIndex(3, 615, true);
            ctrlM3.GetRootGraphMutable().SetFocusedNode(0, 1, true);

            uint32_t tokM3 = 0;
            const bool poppedM3 = ctrlM3.CancelTopModal(ModalButtonMask(ModalButton::B), 20, 620, &tokM3);
            const FocusNode* restoredM3 = ctrlM3.GetRootGraph().GetFocusedNode();
            CheckCase(
                "B1.11_caller_deleted_with_hijacked_current_node_restores_caller_neighbor",
                "When L1 caller item (idx 3) was deleted and L1 current_node_id points to idx 0, Pop L2 restores neighbor at idx 3 (obj_id=504)",
                poppedM3 && tokM3 == 302 &&
                restoredM3 != nullptr &&
                restoredM3->stable_id.object_id == 504 &&
                restoredM3->key.list_index == 3);
        }

        // 1.12 (Audit M2): ConfirmAndCloseToRoot на уровне L3 закрывает L3 и L2 в один кадр, возвращает оба токена в LIFO-порядке и взводит барьер на A
        {
            FocusModalTestController ctrlM2;
            ctrlM2.PopulateSyntheticItems(6, 1, 700);
            ctrlM2.OpenToDepth(3, { 401, 402, 403 }, 0, 710);
            std::vector<uint32_t> confirmTokens;
            const bool confirmed = ctrlM2.ConfirmAndCloseToRoot(ModalButtonMask(ModalButton::A), 25, 720, &confirmTokens);
            CheckCase(
                "B1.12_confirm_close_to_root_L3_to_L1_single_frame",
                "ConfirmAndCloseToRoot at L3 pops L3+L2 to L1 in one frame, returns tokens [403, 402], and arms barrier on A",
                confirmed &&
                ctrlM2.GetModalStack().GetDepth() == 1 &&
                confirmTokens.size() == 2 && confirmTokens[0] == 403 && confirmTokens[1] == 402 &&
                ctrlM2.GetModalStack().IsButtonConsumedByBarrier(ModalButton::A));
        }

        // 1.13 (Audit M1): повторный вызов OpenLevel2ActionModal с глубины 3 возвращает токен сброшенного L3/L2 в out_released_tokens
        {
            FocusModalTestController ctrlM1;
            ctrlM1.PopulateSyntheticItems(6, 1, 800);
            ctrlM1.OpenToDepth(3, { 501, 502, 503 }, 0, 810);
            std::vector<uint32_t> reOpenReleased;
            ctrlM1.OpenLevel2ActionModal(504, 0, 820, &reOpenReleased);
            CheckCase(
                "B1.13_reopen_L2_from_L3_collects_released_tokens",
                "Calling OpenLevel2ActionModal when at depth 3 pops L3+L2 and collects their tokens [503, 502]",
                ctrlM1.GetModalStack().GetDepth() == 2 &&
                reOpenReleased.size() == 2 && reOpenReleased[0] == 503 && reOpenReleased[1] == 502);
        }
    }

    // =========================================================================
    // Блок 2: Барьер отпускания кнопок consumed_until_release (A и B не пробивают
    //         следующее или предыдущее модальное окно при удержании)
    // =========================================================================
    void TestBlock2_ConsumedUntilReleaseBarrier()
    {
        std::printf("\n--- Block 2: Consumed-Until-Release Barrier for A & B Across Modals (8 cases) ---\n");

        FocusModalTestController ctrl;
        ctrl.PopulateSyntheticItems(10, 1, 1000);

        const uint32_t bitA = ModalButtonMask(ModalButton::A);
        const uint32_t bitB = ModalButtonMask(ModalButton::B);

        // 2.1 Открываем L1 при зажатой кнопке A -> A в барьере до физического отпускания
        ctrl.OpenRootModal(201, bitA, 1000);
        ctrl.GetModalStackMutable().BeginFrameButtons(bitA, 1, 1016);
        CheckCase(
            "B2.1_btnA_held_on_L1_open_is_barred",
            "Holding A when L1 opens -> A is consumed by barrier and not pressed in L1",
            ctrl.GetModalStack().IsButtonConsumedByBarrier(ModalButton::A) &&
            !ctrl.GetModalStack().IsButtonPressedInTopModal(ModalButton::A),
            true,
            false);

        // 2.2 Отпускаем A -> барьер снимается; нажимаем A -> открываем L2
        ctrl.GetModalStackMutable().BeginFrameButtons(0, 2, 1032);
        ctrl.GetModalStackMutable().BeginFrameButtons(bitA, 3, 1048);
        const bool aPressedInL1 = ctrl.GetModalStack().IsButtonPressedInTopModal(ModalButton::A);
        ctrl.OpenLevel2ActionModal(202, bitA, 1048);
        // На следующем кадре игрок всё ещё держит A
        ctrl.GetModalStackMutable().BeginFrameButtons(bitA, 4, 1064);
        CheckCase(
            "B2.2_btnA_opening_L2_does_not_punch_L2",
            "Pressing A in L1 opens L2 and arms barrier so held A does NOT activate L2 item",
            aPressedInL1 &&
            ctrl.GetModalStack().GetDepth() == 2 &&
            ctrl.GetModalStack().IsButtonConsumedByBarrier(ModalButton::A) &&
            !ctrl.GetModalStack().IsButtonPressedInTopModal(ModalButton::A),
            true,
            false);

        // 2.3 Отпускаем A в L2, нажимаем A снова -> открываем L3 с барьером на A
        ctrl.GetModalStackMutable().BeginFrameButtons(0, 5, 1080);
        ctrl.GetModalStackMutable().BeginFrameButtons(bitA, 6, 1096);
        const bool aPressedInL2 = ctrl.GetModalStack().IsButtonPressedInTopModal(ModalButton::A);
        ctrl.OpenLevel3ConfirmModal(203, bitA, 1096);
        ctrl.GetModalStackMutable().BeginFrameButtons(bitA, 7, 1112);
        CheckCase(
            "B2.3_btnA_opening_L3_does_not_punch_L3",
            "Pressing A in L2 opens L3 and arms barrier so held A does NOT confirm L3 dialog",
            aPressedInL2 &&
            ctrl.GetModalStack().GetDepth() == 3 &&
            ctrl.GetModalStack().IsButtonConsumedByBarrier(ModalButton::A) &&
            !ctrl.GetModalStack().IsButtonPressedInTopModal(ModalButton::A),
            true,
            false);

        // 2.4 В L3 отпускаем A и зажимаем B -> L3 закрывается (3 -> 2), B ставится в барьер
        ctrl.GetModalStackMutable().BeginFrameButtons(0, 8, 1128);
        ctrl.GetModalStackMutable().BeginFrameButtons(bitB, 9, 1144);
        const bool bPressedInL3 = ctrl.GetModalStack().IsButtonPressedInTopModal(ModalButton::B);
        uint32_t tok = 0;
        const bool poppedL3 = ctrl.CancelTopModal(bitB, 9, 1144, &tok);
        CheckCase(
            "B2.4_btnB_closes_L3_and_arms_barrier",
            "Pressing B in L3 pops L3->L2 and arms consumed_until_release barrier on B",
            bPressedInL3 && poppedL3 &&
            ctrl.GetModalStack().GetDepth() == 2 &&
            ctrl.GetModalStack().IsButtonConsumedByBarrier(ModalButton::B));

        // 2.5 Удерживаем B в течение следующих 5 кадров (кадры 10..14) -> L2 НЕ закрывается!
        bool anyFalsePopWhileHeld = false;
        for (uint32_t f = 10; f <= 14; ++f)
        {
            ctrl.GetModalStackMutable().BeginFrameButtons(bitB, f, 1144 + (f - 9) * 16);
            if (ctrl.GetModalStack().IsButtonPressedInTopModal(ModalButton::B))
                anyFalsePopWhileHeld = true;
        }
        CheckCase(
            "B2.5_held_B_never_closes_L2_across_frames",
            "Holding B across 5 subsequent frames keeps B in barrier and never triggers press in L2",
            !anyFalsePopWhileHeld &&
            ctrl.GetModalStack().GetDepth() == 2 &&
            ctrl.GetModalStack().IsButtonConsumedByBarrier(ModalButton::B),
            true,
            false);

        // 2.6 Пока B всё ещё удерживается, нажатие другой кнопки (например, Down) работает независимо
        const uint32_t bitDown = ModalButtonMask(ModalButton::Down);
        ctrl.GetModalStackMutable().BeginFrameButtons(bitB | bitDown, 15, 1240);
        CheckCase(
            "B2.6_other_buttons_work_while_B_barred",
            "Unbarred button (Down) registers press normally while B remains in barrier",
            ctrl.GetModalStack().IsButtonConsumedByBarrier(ModalButton::B) &&
            !ctrl.GetModalStack().IsButtonPressedInTopModal(ModalButton::B) &&
            ctrl.GetModalStack().IsButtonPressedInTopModal(ModalButton::Down));

        // 2.7 Физическое отпускание B снимает барьер без ложного срабатывания
        ctrl.GetModalStackMutable().BeginFrameButtons(0, 16, 1256);
        CheckCase(
            "B2.7_physical_release_clears_B_barrier",
            "Physically releasing B clears the barrier without triggering a press",
            !ctrl.GetModalStack().IsButtonConsumedByBarrier(ModalButton::B) &&
            !ctrl.GetModalStack().IsButtonPressedInTopModal(ModalButton::B) &&
            ctrl.GetModalStack().GetDepth() == 2);

        // 2.8 Новое нажатие B после физического отпускания штатно закрывает L2 -> L1
        ctrl.GetModalStackMutable().BeginFrameButtons(bitB, 17, 1272);
        const bool bPressedAfterRelease = ctrl.GetModalStack().IsButtonPressedInTopModal(ModalButton::B);
        const bool poppedL2 = ctrl.CancelTopModal(bitB, 17, 1272, &tok);
        CheckCase(
            "B2.8_repress_B_after_release_pops_L2",
            "Pressing B again after physical release closes L2->L1 (token 202 released)",
            bPressedAfterRelease && poppedL2 &&
            ctrl.GetModalStack().GetDepth() == 1 &&
            tok == 202);
    }

    // =========================================================================
    // Блок 3: Полное закрытие всего стека и освобождение всех токенов паузы при
    //         смерти актора, загрузке сохранения или смене уровня
    // =========================================================================
    void TestBlock3_EmergencyClearOnDeathLoadLevelChange()
    {
        std::printf("\n--- Block 3: Emergency Stack Reset on Death, Save Load & Level Change (6 cases) ---\n");

        FocusModalTestController ctrl;
        ctrl.PopulateSyntheticItems(12, 1, 2000);

        // 3.1 Смерть актора при открытых 3 уровнях стека (токены 301, 302, 303)
        ctrl.OpenToDepth(3, { 301, 302, 303 }, 0, 2000);
        std::vector<uint32_t> releasedOnDeath;
        const size_t closedDeath = ctrl.EmergencyCloseAll(
            "actor_dead_on_frame",
            ModalButtonMask(ModalButton::A),
            2100,
            &releasedOnDeath);
        CheckCase(
            "B3.1_emergency_clear_on_actor_death",
            "Actor death at depth 3 -> closes all 3 modals, returns tokens [303,302,301] in LIFO order",
            closedDeath == 3 &&
            ctrl.GetModalStack().IsEmpty() &&
            releasedOnDeath.size() == 3 &&
            releasedOnDeath[0] == 303 &&
            releasedOnDeath[1] == 302 &&
            releasedOnDeath[2] == 301,
            true,
            false);

        // 3.2 После смерти актора зажатая кнопка A оказывается в барьере consumed_until_release
        CheckCase(
            "B3.2_emergency_clear_arms_button_barrier",
            "Emergency reset arms consumed_until_release on held buttons and clears dispatcher tag",
            ctrl.GetModalStack().IsButtonConsumedByBarrier(ModalButton::A) &&
            ctrl.GetModalStack().GetTopDispatcherContextTag().empty());

        // 3.3 Загрузка сохранения (QuickLoad / Disconnect) при открытых 2 уровнях стека
        ctrl.OpenToDepth(2, { 401, 402 }, 0, 2200);
        std::vector<uint32_t> releasedOnLoad;
        const size_t closedLoad = ctrl.EmergencyCloseAll("quick_load", 0, 2250, &releasedOnLoad);
        CheckCase(
            "B3.3_emergency_clear_on_save_load",
            "Save load at depth 2 -> closes both modals and releases tokens [402,401]",
            closedLoad == 2 &&
            ctrl.GetModalStack().IsEmpty() &&
            releasedOnLoad.size() == 2 &&
            releasedOnLoad[0] == 402 &&
            releasedOnLoad[1] == 401);

        // 3.4 Смена уровня (CLevel::net_Stop) при открытых 3 уровнях стека
        ctrl.OpenToDepth(3, { 501, 502, 503 }, 0, 2300);
        std::vector<uint32_t> releasedOnLevelChange;
        const size_t closedLevel = ctrl.EmergencyCloseAll("net_Stop_level_change", 0, 2350, &releasedOnLevelChange);
        CheckCase(
            "B3.4_emergency_clear_on_level_change",
            "Level change (net_Stop) at depth 3 -> closes all 3 modals and releases all 3 tokens",
            closedLevel == 3 &&
            ctrl.GetModalStack().IsEmpty() &&
            releasedOnLevelChange.size() == 3 &&
            ctrl.GetModalStack().GetEmergencyClearCount() == 3);

        // 3.5 Повторный EmergencyCloseAll на уже пустом стеке идемпотентен
        std::vector<uint32_t> releasedEmpty;
        const size_t closedAgain = ctrl.EmergencyCloseAll("redundant_clear", 0, 2400, &releasedEmpty);
        CheckCase(
            "B3.5_emergency_clear_idempotent_when_empty",
            "Calling EmergencyCloseAll on already empty stack returns 0 and releases 0 tokens",
            closedAgain == 0 && releasedEmpty.empty() && ctrl.GetModalStack().IsEmpty());

        // 3.6 Открытие нового стека после аварийного сброса работает чисто
        ctrl.OpenToDepth(2, { 601, 602 }, 0, 2500);
        CheckCase(
            "B3.6_reopen_after_emergency_clear_works",
            "Opening modal stack again after emergency reset works cleanly (depth=2)",
            ctrl.GetModalStack().GetDepth() == 2 &&
            ctrl.GetModalStack().GetTopLayer()->pause_token_id == 602);
    }

    // =========================================================================
    // Блок 4: Автоповтор удержания крестовины/стика и плавная прокрутка строго
    //         по реальному времени Device.dwTimeContinual на полной паузе
    //         (Device.Paused() == true, fTimeDelta == 0.0f, 30 FPS vs 75 FPS)
    // =========================================================================
    void TestBlock4_ContinualRepeatAndSmoothScrollOnPause()
    {
        std::printf("\n--- Block 4: Continual Auto-Repeat & Smooth Scroll on Full Pause (8 cases) ---\n");

        // 4.1 ContinualRepeatTimer: первое нажатие на паузе срабатывает мгновенно (is_repeat=false)
        ContinualRepeatTimer timer(320, 90);
        bool isRep = true;
        const uint32_t step0 = timer.Update(true, NavDir::Down, 5000, &isRep);
        CheckCase(
            "B4.1_repeat_timer_initial_press_on_pause",
            "Initial press on pause (dwTimeContinual=5000, fTimeDelta=0) fires immediately",
            step0 == 1 && !isRep && timer.IsActive() && timer.GetActiveDir() == NavDir::Down,
            true,
            false);

        // 4.2 До истечения 320 мс (t=5319) повтор не срабатывает, ровно на t=5320 — 1-й повтор, на t=5410 — 2-й повтор
        const uint32_t before320 = timer.Update(true, NavDir::Down, 5319, &isRep);
        const uint32_t at320 = timer.Update(true, NavDir::Down, 5320, &isRep);
        const bool at320IsRep = isRep;
        const uint32_t before410 = timer.Update(true, NavDir::Down, 5409, &isRep);
        const uint32_t at410 = timer.Update(true, NavDir::Down, 5410, &isRep);
        const bool at410IsRep = isRep;
        CheckCase(
            "B4.2_repeat_timer_exact_320ms_and_90ms",
            "ContinualRepeatTimer fires at +320ms (5320) and +90ms (5410), never 1ms early",
            before320 == 0 && at320 == 1 && at320IsRep && before410 == 0 && at410 == 1 && at410IsRep);

        // 4.3 Одинаковое число шагов при удержании 1200 мс на 30 к/с (шаг 33 мс) и 75 к/с (шаг 13 мс)
        ContinualRepeatTimer timer30(320, 90);
        ContinualRepeatTimer timer75(320, 90);
        uint32_t count30 = 0;
        uint32_t count75 = 0;
        for (uint32_t t = 0; t <= 1200; t += 33)
            count30 += timer30.Update(true, NavDir::Down, 10000 + t);
        for (uint32_t t = 0; t <= 1200; t += 13)
            count75 += timer75.Update(true, NavDir::Down, 10000 + t);
        CheckCase(
            "B4.3_repeat_rate_identical_30fps_vs_75fps",
            "1200ms hold produces identical 11 steps at both 30 FPS (dt=33ms) and 75 FPS (dt=13ms)",
            count30 == 11 && count75 == 11);

        // 4.4 Возврат стика в нейтраль (has_dir=false) сбрасывает таймер, новое отклонение срабатывает сразу
        const uint32_t onNeutral = timer.Update(false, NavDir::Down, 6000);
        const bool inactiveOnNeutral = !timer.IsActive();
        const uint32_t firesAfterNeutral = timer.Update(true, NavDir::Up, 6016, &isRep);
        CheckCase(
            "B4.4_repeat_timer_neutral_reset_and_repress",
            "Returning stick to neutral resets timer; subsequent deflection fires immediate step",
            onNeutral == 0 && inactiveOnNeutral && firesAfterNeutral == 1 && !isRep);

        // 4.5 ContinualSmoothScroller: дискретное следование окна видимости (18 предметов, 6 видимых строк, высота 32px)
        ContinualSmoothScroller scroller;
        scroller.Configure(18, 6, 32.0f);
        scroller.Reset(0);
        scroller.EnsureFocusedVisible(8); // индекс 8 за нижней границей [0..5] -> top становится 8 - 6 + 1 = 3 (96px)
        CheckCase(
            "B4.5_scroller_ensure_index_visible_down",
            "EnsureFocusedVisible(8) in 6-row viewport shifts target_top_index to 3 (target=96px)",
            scroller.GetTargetTopIndex() == 3 &&
            std::fabs(scroller.GetTargetOffsetPx() - 96.0f) < 1e-3f);

        // 4.6 Плавная интерполяция позиции прокрутки по dwTimeContinual (при fTimeDelta == 0 на паузе)
        scroller.Step(10000); // инициализация базовой отметки времени (dt=0)
        scroller.Step(10050); // +50 мс -> экспоненциальное продвижение к 96 px
        const float pxAfter50ms = scroller.GetVisualOffsetPx();
        for (uint32_t t = 10100; t <= 10600; t += 50)
            scroller.Step(t); // сходится к точному целевому 96 px
        const float pxAfter600ms = scroller.GetVisualOffsetPx();
        CheckCase(
            "B4.6_scroller_smooth_interpolation_on_pause",
            "Step(now_continual_ms) smoothly interpolates (0 < px50 < 96) and converges to 96px on pause",
            pxAfter50ms > 10.0f && pxAfter50ms < 95.0f &&
            std::fabs(pxAfter600ms - 96.0f) < 1e-3f &&
            !scroller.IsAnimating(),
            true,
            false);

        // 4.7 Непрерывная аналоговая прокрутка правым стиком на паузе с удержанием в границах [0..maxScrollPx]
        scroller.AddAnalogScrollVelocity(1.0f, 8.0f, 250); // +2 строки (+64 px) -> target=160 px (top=5)
        const float pxTargetMid = scroller.GetTargetOffsetPx();
        scroller.AddAnalogScrollVelocity(1.0f, 8.0f, 5000); // упирается в потолок (18 - 6) * 32 = 384 px (top=12)
        CheckCase(
            "B4.7_scroller_analog_velocity_and_clamp",
            "AddAnalogScrollVelocity moves by axis * rows_per_sec * dt_ms and clamps at max 384px (top=12)",
            std::fabs(pxTargetMid - 160.0f) < 1e-2f &&
            scroller.GetTargetTopIndex() == 12 &&
            std::fabs(scroller.GetTargetOffsetPx() - 384.0f) < 1e-3f);

        // 4.8 Сжатие списка при удалении элементов автоматически поджимает окно видимости без выхода за границы
        scroller.Configure(5, 6, 32.0f); // осталось 5 предметов при 6 видимых строках -> maxTop = 0
        CheckCase(
            "B4.8_scroller_clamps_on_item_deletion",
            "When item count drops to 5 (<= 6 visible rows), target_top_index clamps to 0",
            scroller.GetTargetTopIndex() == 0 &&
            std::fabs(scroller.GetTargetOffsetPx()) < 1e-3f);
    }

    // =========================================================================
    // Блок 5: Операции тестового экрана (удаление первого / среднего /
    //         последнего / единственного / текущего элемента с проверкой F1.1)
    // =========================================================================
    void TestBlock5_TestScreenItemDeletions()
    {
        std::printf("\n--- Block 5: Test Screen Item Deletions & F1.1 Focus Restoration (7 cases) ---\n");

        FocusModalTestController ctrl;
        ctrl.PopulateSyntheticItems(7, 1, 3000);
        ctrl.OpenRootModal(701, 0, 3000);

        // В PopulateSyntheticItems(7): obj_id = 500 + i (500..506)
        // 5.1 Удаление первого элемента (индекс 0 из 7, obj_id=500) -> остаётся 6, фокус на новом первом элементе (бывший #2, obj_id=501)
        const FocusRestoreReason rFirst = ctrl.DeleteFirstItem(3010);
        const FocusNode* fAfterFirst = ctrl.GetRootGraph().GetFocusedNode();
        CheckCase(
            "B5.1_delete_first_item_restores_next",
            "DeleteFirstItem (index 0 of 7) -> 6 items left, focus on former item #2 (obj_id=501)",
            rFirst == FocusRestoreReason::NeighborBelow &&
            ctrl.GetItems().size() == 6 &&
            fAfterFirst != nullptr &&
            fAfterFirst->stable_id.object_id == 501 &&
            fAfterFirst->key.list_index == 0);

        // 5.2 Удаление среднего элемента (индекс 3 из 6, obj_id=504) -> фокус на следующем соседе снизу (obj_id=505)
        const FocusRestoreReason rMid = ctrl.DeleteMiddleItem(3020);
        const FocusNode* fAfterMid = ctrl.GetRootGraph().GetFocusedNode();
        CheckCase(
            "B5.2_delete_middle_item_restores_neighbor",
            "DeleteMiddleItem (index 3 of 6, obj_id=504) -> 5 items left, focus on neighbor obj_id=505",
            rMid == FocusRestoreReason::NeighborBelow &&
            ctrl.GetItems().size() == 5 &&
            fAfterMid != nullptr &&
            fAfterMid->stable_id.object_id == 505 &&
            fAfterMid->key.list_index == 3);

        // 5.3 Удаление последнего элемента (индекс 4 из 5, obj_id=506) -> фокус на предыдущем соседе сверху (obj_id=505)
        const FocusRestoreReason rLast = ctrl.DeleteLastItem(3030);
        const FocusNode* fAfterLast = ctrl.GetRootGraph().GetFocusedNode();
        CheckCase(
            "B5.3_delete_last_item_restores_prev",
            "DeleteLastItem (index 4 of 5, obj_id=506) -> 4 items left, focus on new last obj_id=505",
            rLast == FocusRestoreReason::NeighborAbove &&
            ctrl.GetItems().size() == 4 &&
            fAfterLast != nullptr &&
            fAfterLast->stable_id.object_id == 505 &&
            fAfterLast->key.list_index == 3,
            true,
            false);

        // 5.4 Удаление текущего выбранного элемента (DeleteFocusedItem на индексе 3) -> фокус переходит на новый последний (индекс 2, obj_id=503)
        const FocusRestoreReason rFocused = ctrl.DeleteFocusedItem(3040);
        const FocusNode* fAfterFocused = ctrl.GetRootGraph().GetFocusedNode();
        CheckCase(
            "B5.4_delete_focused_item_restores_prev",
            "DeleteFocusedItem on last element -> 3 items left, focus on obj_id=503 (index 2)",
            rFocused == FocusRestoreReason::NeighborAbove &&
            ctrl.GetItems().size() == 3 &&
            fAfterFocused != nullptr &&
            fAfterFocused->stable_id.object_id == 503 &&
            fAfterFocused->key.list_index == 2);

        // 5.5 Удаление единственного элемента (1 -> 0) -> фокус встаёт на EmptyStatePlaceholder без пропадания курсора
        const FocusRestoreReason rSingle = ctrl.DeleteSingleItem(3050);
        const FocusNode* fAfterSingle = ctrl.GetRootGraph().GetFocusedNode();
        CheckCase(
            "B5.5_delete_single_item_to_empty_placeholder",
            "DeleteSingleItem (1 -> 0) -> focus moves to EmptyStatePlaceholder (EmptyGroupHeader)",
            rSingle == FocusRestoreReason::EmptyGroupHeader &&
            ctrl.GetItems().empty() &&
            fAfterSingle != nullptr &&
            fAfterSingle->kind == FocusNodeKind::EmptyStatePlaceholder,
            true,
            false);

        // 5.6 Встроенный комплексный самотест RunModalStackSelfTest() проходит без единого сбоя
        const SelfTestSummary selfSummary = RunModalStackSelfTest();
        CheckCase(
            "B5.6_embedded_modal_stack_selftest",
            "RunModalStackSelfTest() passes all internal assertions (failed_cases == 0)",
            selfSummary.failed_cases == 0 && selfSummary.passed_cases == selfSummary.total_cases);

        // 5.7 (Audit m4 & m5): удаление НЕвыбранного элемента (focus_target_before_delete=false) сохраняет фокус на выбранном предмете (SameItem),
        //                      а StepNavigationWithRepeat шагает по ContinualRepeatTimer внутри контроллера
        {
            FocusModalTestController ctrlM4;
            ctrlM4.PopulateSyntheticItems(8, 1, 4000);
            ctrlM4.OpenRootModal(801, 0, 4000);
            bool isRep = false;
            const uint32_t navSteps1 = ctrlM4.StepNavigationWithRepeat(true, NavDir::Down, 4000, &isRep);
            const uint32_t navSteps2 = ctrlM4.StepNavigationWithRepeat(true, NavDir::Down, 4350, &isRep);
            // После 2 шагов Down фокус на индексе 2 (предмет #3, obj_id=502); удаляем индекс 0 без перефокусировки
            const FocusRestoreReason rUnfocused = ctrlM4.DeleteItemAtListIndex(0, 4360, false);
            const FocusNode* fAfterUnfocused = ctrlM4.GetRootGraph().GetFocusedNode();
            CheckCase(
                "B5.7_delete_unfocused_keeps_same_item_and_repeat_nav_steps",
                "StepNavigationWithRepeat moves focus to obj_id=502 and deleting index 0 with focus_target_before_delete=false keeps SameItem focus on obj_id=502",
                navSteps1 == 1 && navSteps2 == 1 && isRep &&
                rUnfocused == FocusRestoreReason::SameItem &&
                fAfterUnfocused != nullptr &&
                fAfterUnfocused->stable_id.object_id == 502 &&
                fAfterUnfocused->key.list_index == 1);
        }
    }
} // namespace

int main()
{
    std::printf("================================================================================\n");
    std::printf("GAMMA Gamepad Mod — Step F1.2 Modal Stack, Continual Scroll & Barrier Unit Tests\n");
    std::printf("================================================================================\n");

    TestBlock1_ModalNestingAndFocusRestore();
    TestBlock2_ConsumedUntilReleaseBarrier();
    TestBlock3_EmergencyClearOnDeathLoadLevelChange();
    TestBlock4_ContinualRepeatAndSmoothScrollOnPause();
    TestBlock5_TestScreenItemDeletions();

    std::printf("\n================================================================================\n");
    std::printf("SUMMARY: total=%d | passed=%d | failed=%d | old_behavior_regressions_caught=%d\n",
        g_total_tests, g_passed_tests, g_failed_tests, g_old_regressions);
    std::printf("================================================================================\n");

    return (g_failed_tests == 0) ? 0 : 1;
}
