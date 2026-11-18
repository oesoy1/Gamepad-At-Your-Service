// D4.1: Console unit test for src/xrEngine/GamepadBindings. No game, no engine runtime required.
// Build & run: tools/tests/gamepad_bindings/build.ps1 -> _build/tests/gamepad_bindings/GamepadBindings_test.exe
#include "../../../src/xrEngine/GamepadBindings.h"
#include "../../../src/xrEngine/GamepadAtomicFile.h"

#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

using namespace gpbind;

static int g_pass = 0;
static int g_fail = 0;

#define CHECK(cond, ...)                                                                                               \
    do                                                                                                                 \
    {                                                                                                                  \
        if (cond)                                                                                                      \
            ++g_pass;                                                                                                  \
        else                                                                                                           \
        {                                                                                                              \
            ++g_fail;                                                                                                  \
            std::printf("FAIL %s:%d: ", __FILE__, __LINE__);                                                           \
            std::printf(__VA_ARGS__);                                                                                  \
            std::printf("\n");                                                                                         \
        }                                                                                                              \
    } while (0)

static std::uint32_t Bit(ButtonId b) { return 1u << static_cast<std::uint32_t>(b); }

// 1. Defaults & Trigger Types (Button, Hold, Chord)
static void TestDefaultsAndTriggerTypes()
{
    BindingProfileModel m;
    CHECK(m.GetSchemaVersion() == limits::kCurrentProfileSchema, "default schema version == %u", limits::kCurrentProfileSchema);

    std::string navErr;
    CHECK(m.VerifyMenuNavigationInvariant(&navErr), "default MenuUI navigation invariant: %s", navErr.c_str());

    const auto allConflicts = m.DetectAllConflicts(false);
    CHECK(allConflicts.empty(), "default bindings must have 0 blocking conflicts, got %zu", allConflicts.size());

    // Verify Button trigger in World_Gameplay (Jump = A)
    const BindingTrigger* jump = m.FindBinding(ContextId::World_Gameplay, ActionId::Jump);
    CHECK(jump != nullptr && jump->type == TriggerType::Button && jump->button == ButtonId::South, "default Jump = Button(A)");

    // Verify Hold trigger in World_Gameplay (LowCrouch = Hold(B, 300ms))
    const BindingTrigger* lowCrouch = m.FindBinding(ContextId::World_Gameplay, ActionId::LowCrouch);
    CHECK(lowCrouch != nullptr && lowCrouch->type == TriggerType::Hold && lowCrouch->button == ButtonId::East &&
              lowCrouch->hold_ms == 300,
          "default LowCrouch = Hold(B, 300)");

    // Verify Chord trigger in World_Gameplay (GAYS v0.2: ForceReload = Chord(LT + X))
    const BindingTrigger* forceReload = m.FindBinding(ContextId::World_Gameplay, ActionId::ForceReload);
    CHECK(forceReload != nullptr && forceReload->type == TriggerType::Chord &&
              forceReload->modifier == ButtonId::LT && forceReload->button == ButtonId::West,
          "GAYS v0.2 default ForceReload = Chord(LT+X)");

    // GAYS v0.2: Verify defaults match live gameplay (AmmoTypeNext/AmmoWheel on DPadDown, UBGL on Hold DPadRight, etc.)
    const BindingTrigger* ammoNext = m.FindBinding(ContextId::World_Gameplay, ActionId::AmmoTypeNext);
    CHECK(ammoNext != nullptr && ammoNext->type == TriggerType::Button && ammoNext->button == ButtonId::DPadDown,
          "GAYS v0.2 default AmmoTypeNext = Button(DPadDown)");
    const BindingTrigger* ammoWheel = m.FindBinding(ContextId::World_Gameplay, ActionId::AmmoWheel);
    CHECK(ammoWheel != nullptr && ammoWheel->type == TriggerType::Hold && ammoWheel->button == ButtonId::DPadDown,
          "GAYS v0.2 default AmmoWheel = Hold(DPadDown, 300)");
    const BindingTrigger* ubgl = m.FindBinding(ContextId::World_Gameplay, ActionId::UnderbarrelToggle);
    CHECK(ubgl != nullptr && ubgl->type == TriggerType::Hold && ubgl->button == ButtonId::DPadRight,
          "GAYS v0.2 default UnderbarrelToggle = Hold(DPadRight, 300)");
    const BindingTrigger* fireMode = m.FindBinding(ContextId::World_Gameplay, ActionId::FireModeNext);
    CHECK(fireMode != nullptr && fireMode->type == TriggerType::Button && fireMode->button == ButtonId::DPadRight,
          "GAYS v0.2 default FireModeNext = Button(DPadRight)");
    const BindingTrigger* bolt = m.FindBinding(ContextId::World_Gameplay, ActionId::QuickBoltOrSlot);
    CHECK(bolt != nullptr && bolt->type == TriggerType::Button && bolt->button == ButtonId::LeftShoulder,
          "GAYS v0.2 default QuickBoltOrSlot = Button(LB)");
    const BindingTrigger* wheel = m.FindBinding(ContextId::World_Gameplay, ActionId::WeaponWheel);
    CHECK(wheel != nullptr && wheel->type == TriggerType::Hold && wheel->button == ButtonId::LeftShoulder,
          "GAYS v0.2 default WeaponWheel = Hold(LB, 250)");
    const BindingTrigger* grenade = m.FindBinding(ContextId::World_Gameplay, ActionId::GrenadeQuick);
    CHECK(grenade != nullptr && grenade->type == TriggerType::Chord &&
              grenade->modifier == ButtonId::LeftShoulder && grenade->button == ButtonId::North,
          "GAYS v0.2 default GrenadeQuick = Chord(LB+Y)");

    // Sanitizer checks for trigger bounds
    BindingTrigger badHold = BindingTrigger::MakeHold(ButtonId::West, 15); // below 100ms
    std::uint32_t fixes = 0;
    CHECK(BindingProfileModel::SanitizeTrigger(badHold, &fixes) && badHold.hold_ms == limits::kMinHoldMs && fixes > 0,
          "hold_ms < 100 clamped to 100");

    BindingTrigger hugeHold = BindingTrigger::MakeHold(ButtonId::West, 9999); // above 2000ms
    fixes = 0;
    CHECK(BindingProfileModel::SanitizeTrigger(hugeHold, &fixes) && hugeHold.hold_ms == limits::kMaxHoldMs && fixes > 0,
          "hold_ms > 2000 clamped to 2000");

    BindingTrigger selfChord = BindingTrigger::MakeChord(ButtonId::West, ButtonId::West);
    CHECK(!BindingProfileModel::SanitizeTrigger(selfChord), "self-chord X+X must be rejected");
}

// 2. Runtime evaluation of Button vs Hold vs Chord
static void TestRuntimeGestureEvaluation()
{
    BindingProfileModel m;
    // In World_Gameplay:
    // - West (X) has: Button(X) -> ContextUseReload, Hold(X, 300) -> AmmoCheck, Chord(LT + X) -> FastReload
    // - South (A) has: Button(A) -> Jump (no Hold on A -> fires immediately on press)

    // Case A: Press South (A) -> Jump fires immediately on press frame
    auto evs = m.EvaluateContextGestures(ContextId::World_Gameplay, Bit(ButtonId::South), 16);
    CHECK(evs.size() == 1 && evs[0].action == ActionId::Jump && evs[0].trigger_type == TriggerType::Button,
          "Button(A) without Hold fires on press");
    evs = m.EvaluateContextGestures(ContextId::World_Gameplay, 0, 16);
    CHECK(evs.empty(), "Release(A) does not double-fire Jump");

    // Case B: Short tap on West (X) for 100 ms (< 300 ms) -> fires ContextUseReload on release, not AmmoCheck
    evs = m.EvaluateContextGestures(ContextId::World_Gameplay, Bit(ButtonId::West), 50);
    CHECK(evs.empty(), "Hold-sharing Button(X) waits while held < 300ms");
    evs = m.EvaluateContextGestures(ContextId::World_Gameplay, Bit(ButtonId::West), 50);
    CHECK(evs.empty(), "Still < 300ms");
    evs = m.EvaluateContextGestures(ContextId::World_Gameplay, 0, 16);
    CHECK(evs.size() == 1 && evs[0].action == ActionId::ContextUseReload && evs[0].trigger_type == TriggerType::Button,
          "Tap(X) < 300ms fires ContextUseReload on release");

    // Case C: Hold West (X) for >= 300 ms -> fires AmmoCheck once at threshold, and does NOT fire ContextUseReload on release
    evs = m.EvaluateContextGestures(ContextId::World_Gameplay, Bit(ButtonId::West), 150);
    CHECK(evs.empty(), "Hold(X) at 150ms not fired yet");
    evs = m.EvaluateContextGestures(ContextId::World_Gameplay, Bit(ButtonId::West), 160); // total 310ms >= 300ms
    CHECK(evs.size() == 1 && evs[0].action == ActionId::AmmoCheck && evs[0].trigger_type == TriggerType::Hold,
          "Hold(X) at 310ms fires AmmoCheck");
    evs = m.EvaluateContextGestures(ContextId::World_Gameplay, Bit(ButtonId::West), 200); // still held at 510ms
    CHECK(evs.empty(), "Hold(X) does not repeat-fire while held");
    evs = m.EvaluateContextGestures(ContextId::World_Gameplay, 0, 16);
    CHECK(evs.empty(), "Release after Hold(X) does NOT fire tap ContextUseReload");

    // Case D: Chord(LT + X) -> hold LT, press X -> fires ForceReload immediately and suppresses tap/hold on X
    evs = m.EvaluateContextGestures(ContextId::World_Gameplay, Bit(ButtonId::LT), 16); // Aim pressed
    evs = m.EvaluateContextGestures(ContextId::World_Gameplay, Bit(ButtonId::LT) | Bit(ButtonId::West), 16);
    bool sawForceReload = false;
    for (const auto& e : evs)
    {
        if (e.action == ActionId::ForceReload && e.trigger_type == TriggerType::Chord)
            sawForceReload = true;
    }
    CHECK(sawForceReload, "Chord(LT+X) fires ForceReload on X press while LT held");
    evs = m.EvaluateContextGestures(ContextId::World_Gameplay, Bit(ButtonId::LT) | Bit(ButtonId::West), 350);
    CHECK(evs.empty(), "Holding X after Chord(LT+X) does NOT fire AmmoCheck");
    evs = m.EvaluateContextGestures(ContextId::World_Gameplay, 0, 16);
    CHECK(evs.empty(), "Releasing LT+X after Chord does NOT fire ContextUseReload");
}

// 3. Conflict detection within a context vs across contexts (D4.1 item 2)
static void TestConflictDetector()
{
    BindingProfileModel m;

    // 3a. Same context conflict (Button): Jump is Button(A) in World_Gameplay.
    // Assigning Crouch to Button(A) in World_Gameplay without resolution must fail with ConflictDetected.
    EditResult r1 = m.SetBinding(ContextId::World_Gameplay, ActionId::Crouch, BindingTrigger::MakeButton(ButtonId::South), false);
    CHECK(r1.status == EditStatus::ConflictDetected, "Button(A) conflict in World_Gameplay must be detected");
    CHECK(r1.conflicts.size() == 1 && r1.conflicts[0].existing_action == ActionId::Jump &&
              r1.conflicts[0].kind == ConflictKind::ExactDuplicate && r1.conflicts[0].is_blocking,
          "Conflict points to existing Jump action");
    // Verify Crouch remained unchanged (Button(B))
    const BindingTrigger* crouch = m.FindBinding(ContextId::World_Gameplay, ActionId::Crouch);
    CHECK(crouch && crouch->button == ButtonId::East, "Crouch unchanged when conflict rejected");

    // 3b. Same context conflict (HoldOverlap): LowCrouch is Hold(B, 300) in World_Gameplay.
    // Assigning AmmoCheck to Hold(B, 500) in World_Gameplay must conflict (HoldOverlap on button B).
    EditResult r2 = m.SetBinding(ContextId::World_Gameplay, ActionId::AmmoCheck, BindingTrigger::MakeHold(ButtonId::East, 500), false);
    CHECK(r2.status == EditStatus::ConflictDetected && !r2.conflicts.empty() &&
              r2.conflicts[0].kind == ConflictKind::HoldOverlap && r2.conflicts[0].existing_action == ActionId::LowCrouch,
          "Two Holds on button B with different ms must report HoldOverlap conflict");

    // 3c. Same context conflict (Chord): ForceReload is Chord(LT + X) in World_Gameplay.
    // Assigning LeanLeft to Chord(LT + X) must report ExactDuplicate conflict.
    EditResult r3 = m.SetBinding(ContextId::World_Gameplay, ActionId::LeanLeft,
                                 BindingTrigger::MakeChord(ButtonId::LT, ButtonId::West), false);
    CHECK(r3.status == EditStatus::ConflictDetected && !r3.conflicts.empty() &&
              r3.conflicts[0].existing_action == ActionId::ForceReload,
          "Duplicate Chord(LT+X) in World_Gameplay must conflict");

    // 3d. Cross-context non-conflict: Button(A) is Confirm in MenuUI, DialogSelect in Dialog_NPC, WheelConfirm in RadialWheel, Jump in World_Gameplay.
    // Assigning ContextMenu in MenuUI to Button(LeftStick) (which is Sprint in World_Gameplay) must have 0 conflicts!
    auto crossConflicts = m.DetectConflictsForCandidate(ContextId::MenuUI, ActionId::ContextMenu,
                                                        BindingTrigger::MakeButton(ButtonId::LeftStick), true);
    CHECK(crossConflicts.empty(), "Button used in World_Gameplay must NOT conflict in MenuUI");
    EditResult r4 = m.SetBinding(ContextId::MenuUI, ActionId::ContextMenu,
                                 BindingTrigger::MakeButton(ButtonId::LeftStick), false);
    CHECK(r4.status == EditStatus::Ok, "Cross-context assignment succeeds with 0 conflicts");

    // 3e. Resolving conflict in World_Gameplay with allowConflictResolution=true swaps Jump and Crouch
    EditResult r5 = m.SetBinding(ContextId::World_Gameplay, ActionId::Crouch, BindingTrigger::MakeButton(ButtonId::South), true);
    CHECK(r5.Succeeded() && r5.swapped_with == ActionId::Jump, "Conflict resolution swaps Crouch and Jump");
    CHECK(m.FindBinding(ContextId::World_Gameplay, ActionId::Crouch)->button == ButtonId::South, "Crouch is now A");
    CHECK(m.FindBinding(ContextId::World_Gameplay, ActionId::Jump)->button == ButtonId::East, "Jump is now B");
}

// 4. Protected Menu / Confirm / Back in MenuUI and MainMenu (D4.1 item 3, T05)
static void TestProtectedMenuNavigation()
{
    BindingProfileModel m;

    // 4a. Cannot unbind Menu, Confirm, or Back in MenuUI or MainMenu
    CHECK(m.UnbindAction(ContextId::MenuUI, ActionId::Menu).status == EditStatus::ProtectedActionCannotUnbind,
          "Cannot unbind Menu in MenuUI");
    CHECK(m.UnbindAction(ContextId::MenuUI, ActionId::Confirm).status == EditStatus::ProtectedActionCannotUnbind,
          "Cannot unbind Confirm in MenuUI");
    CHECK(m.UnbindAction(ContextId::MenuUI, ActionId::Back).status == EditStatus::ProtectedActionCannotUnbind,
          "Cannot unbind Back in MenuUI");
    CHECK(m.UnbindAction(ContextId::MainMenu, ActionId::Confirm).status == EditStatus::ProtectedActionCannotUnbind,
          "Cannot unbind Confirm in MainMenu");

    // Non-protected action in MenuUI CAN be unbound
    CHECK(m.UnbindAction(ContextId::MenuUI, ActionId::QuickAction).status == EditStatus::Ok,
          "Non-protected QuickAction in MenuUI can be unbound");
    CHECK(m.VerifyMenuNavigationInvariant(), "MenuUI navigation invariant still holds after unbinding QuickAction");

    // 4b. Cannot assign Chord or Guide or None to protected Confirm/Back/Menu
    EditResult badChord = m.SetBinding(ContextId::MenuUI, ActionId::Confirm,
                                       BindingTrigger::MakeChord(ButtonId::LT, ButtonId::South), true);
    CHECK(badChord.status == EditStatus::ProtectedActionInvalidTrigger,
          "Protected Confirm cannot be assigned a Chord");

    EditResult badGuide = m.SetBinding(ContextId::MenuUI, ActionId::Menu,
                                       BindingTrigger::MakeButton(ButtonId::Guide), true);
    CHECK(badGuide.status == EditStatus::ProtectedActionInvalidTrigger,
          "Protected Menu cannot be assigned OS Guide button");

    // 4c. Cannot overwrite Confirm/Back from an unbound action (which would leave Confirm/Back without a swap button)
    // QuickAction is currently unbound; trying to bind QuickAction to Button(A) (Confirm's button) even with allowConflictResolution=true must fail!
    EditResult stealConfirm = m.SetBinding(ContextId::MenuUI, ActionId::QuickAction,
                                           BindingTrigger::MakeButton(ButtonId::South), true);
    CHECK(stealConfirm.status == EditStatus::ProtectedActionCannotUnbind,
          "Unbound action cannot steal protected Confirm's button without a valid swap button");
    CHECK(m.FindBinding(ContextId::MenuUI, ActionId::Confirm)->button == ButtonId::South,
          "Confirm remains on A");

    // 4d. Swapping Confirm (A) and Back (B) (Nintendo / Japanese BAYX layout) works and preserves working pair!
    EditResult swapAB = m.SetBinding(ContextId::MenuUI, ActionId::Confirm,
                                     BindingTrigger::MakeButton(ButtonId::East), true);
    CHECK(swapAB.status == EditStatus::OkWithSwappedProtected && swapAB.swapped_with == ActionId::Back,
          "Rebinding Confirm to B swaps with Back -> Confirm=B, Back=A");
    CHECK(m.FindBinding(ContextId::MenuUI, ActionId::Confirm)->button == ButtonId::East, "Confirm is now B");
    CHECK(m.FindBinding(ContextId::MenuUI, ActionId::Back)->button == ButtonId::South, "Back is now A");
    CHECK(m.VerifyMenuNavigationInvariant(), "MenuUI navigation invariant holds after Confirm<->Back swap");

    // 4e. Moving Confirm to X (ContextMenu's button) swaps Confirm and ContextMenu safely
    EditResult moveConfirmToX = m.SetBinding(ContextId::MenuUI, ActionId::Confirm,
                                             BindingTrigger::MakeButton(ButtonId::West), true);
    CHECK(moveConfirmToX.status == EditStatus::OkWithSwappedProtected && moveConfirmToX.swapped_with == ActionId::ContextMenu,
          "Moving Confirm to X swaps with ContextMenu");
    CHECK(m.FindBinding(ContextId::MenuUI, ActionId::Confirm)->button == ButtonId::West, "Confirm is now X");
    CHECK(m.FindBinding(ContextId::MenuUI, ActionId::ContextMenu)->button == ButtonId::East, "ContextMenu is now B");
    CHECK(m.VerifyMenuNavigationInvariant(), "MenuUI navigation invariant holds after moving Confirm to X");
}

// 5. Versioned Profile File, Schema Migration v1 -> v2, Corrupt File Recovery, Export/Import, Path Guard (D4.1 item 4)
static void TestVersionedStorageMigrationAndCorruptRecovery(const std::string& tempDir)
{
    // 5a. Forbidden path guard (D4.1 stop condition: never write to user.ltx, axr_options.ltx, gamecontrollerdb.txt, or D:\Stalker)
    BindingProfileModel m;
    std::string err;
    CHECK(BindingProfileModel::IsPathForbiddenForWrite("D:\\Stalker\\Anomaly\\appdata\\user.ltx", &err),
          "D:\\Stalker path must be forbidden");
    CHECK(BindingProfileModel::IsPathForbiddenForWrite("D:\\GAMMA-Gamepad-Lab\\appdata\\user.ltx", &err),
          "user.ltx must be forbidden");
    CHECK(BindingProfileModel::IsPathForbiddenForWrite("D:\\GAMMA-Gamepad-Lab\\game\\gamedata\\configs\\axr_options.ltx", &err),
          "axr_options.ltx must be forbidden");
    CHECK(!m.SaveToFile("D:\\GAMMA-Gamepad-Lab\\appdata\\user.ltx", &err),
          "SaveToFile must refuse user.ltx");
    CHECK(BindingProfileModel::GetDefaultProfileRelativePath() == "gamepad\\profile.ltx",
          "Default relative path is gamepad\\profile.ltx under appdata (D37)");

    // 5b. Schema migration v1 -> v2 test
    const std::string v1ProfileText =
        "; Legacy v1 gamepad profile\n"
        "[profile_header]\n"
        "version = 1\n"
        "\n"
        "[bindings_menu]\n"
        "ui_accept = East\n"
        "ui_cancel = South\n"
        "ui_menu = Start\n"
        "\n"
        "[bindings_world]\n"
        "Jump = North\n"
        "interact_reload = West\n"
        "check_ammo = hold:West\n"
        "tactical_reload = LT+West\n";

    BindingProfileModel migratedModel;
    LoadReport migRep = migratedModel.DeserializeFromText(v1ProfileText);
    CHECK(migRep.status == LoadStatus::MigratedV1ToV2, "v1 profile status must be MigratedV1ToV2, got %d (%s)",
          static_cast<int>(migRep.status), migRep.detail.c_str());
    CHECK(migRep.source_version == 1 && migRep.target_version == 2, "source_version=1 -> target_version=2");
    CHECK(migRep.migrated_entries >= 7, "migrated_entries >= 7, got %u", migRep.migrated_entries);
    CHECK(migratedModel.GetSchemaVersion() == 2, "model upgraded to schema v2");
    CHECK(migratedModel.FindBinding(ContextId::MenuUI, ActionId::Confirm)->button == ButtonId::East,
          "v1 ui_accept migrated to MenuUI.Confirm = B");
    CHECK(migratedModel.FindBinding(ContextId::MenuUI, ActionId::Back)->button == ButtonId::South,
          "v1 ui_cancel migrated to MenuUI.Back = A");
    CHECK(migratedModel.FindBinding(ContextId::World_Gameplay, ActionId::Jump)->button == ButtonId::North,
          "v1 bindings_world.Jump migrated to World_Gameplay.Jump = Y");
    const BindingTrigger* migHold = migratedModel.FindBinding(ContextId::World_Gameplay, ActionId::AmmoCheck);
    CHECK(migHold && migHold->type == TriggerType::Hold && migHold->button == ButtonId::West && migHold->hold_ms == 300,
          "v1 'hold:West' migrated to Hold(X, 300)");
    const BindingTrigger* migChord = migratedModel.FindBinding(ContextId::World_Gameplay, ActionId::FastReload);
    CHECK(migChord && migChord->type == TriggerType::Chord && migChord->modifier == ButtonId::LT &&
              migChord->button == ButtonId::West,
          "v1 'LT+West' migrated to Chord(LT+X)");

    // 5c. Corrupt / hand-broken file recovery test (garbage lines, negative/huge hold_ms, Confirm==Back collision, Guide on Menu)
    const std::string corruptProfileText =
        "THIS IS GARBAGE WITHOUT SECTION\n"
        "[unclosed_section\n"
        "[profile_header]\n"
        "schema_version = not_a_number\n"
        "[context_MenuUI]\n"
        "Confirm = button:East\n"
        "Back = button:East\n"        // collision with Confirm!
        "Menu = button:Guide\n"       // invalid button for protected Menu!
        "ContextMenu = chord:West+West\n" // invalid self-chord!
        "[context_World_Gameplay]\n"
        "LowCrouch = hold:East:-500\n"    // negative hold_ms -> clamped to 100
        "NightVision = hold:DPadUp:99999\n"// huge hold_ms -> clamped to 2000
        "AmmoCheck = hold:West:nan_ms\n"  // non-numeric hold_ms -> default 300
        "UnknownAction = button:South\n"
        "Jump = button:NonExistentButton\n"
        "[context_NonExistent]\n"
        "Jump = button:South\n";

    BindingProfileModel corruptModel;
    LoadReport corRep = corruptModel.DeserializeFromText(corruptProfileText);
    CHECK(corRep.status == LoadStatus::RecoveredFromCorrupt, "corrupt profile status == RecoveredFromCorrupt");
    CHECK(corRep.corrupted_lines_skipped >= 5, "corrupted lines skipped (%u)", corRep.corrupted_lines_skipped);
    CHECK(corRep.sanitized_fields >= 3, "out-of-range hold_ms sanitized (%u)", corRep.sanitized_fields);
    CHECK(corruptModel.VerifyMenuNavigationInvariant(),
          "MenuUI navigation invariant must be intact after loading corrupt file");
    CHECK(corruptModel.FindBinding(ContextId::World_Gameplay, ActionId::LowCrouch)->hold_ms == limits::kMinHoldMs,
          "negative hold_ms clamped to 100");
    CHECK(corruptModel.FindBinding(ContextId::World_Gameplay, ActionId::NightVision)->hold_ms == limits::kMaxHoldMs,
          "huge hold_ms clamped to 2000");
    CHECK(corruptModel.FindBinding(ContextId::World_Gameplay, ActionId::AmmoCheck)->hold_ms == limits::kDefaultHoldMs,
          "nan hold_ms sanitized to 300");

    // 5d. Totally empty / binary garbage file recovery
    BindingProfileModel binaryGarbageModel;
    LoadReport binRep = binaryGarbageModel.DeserializeFromText("\x01\x02\xFF===@@@\n[][][]\n");
    CHECK(binRep.status == LoadStatus::RecoveredFromCorrupt, "binary garbage recovers to defaults");
    CHECK(binaryGarbageModel.VerifyMenuNavigationInvariant(), "navigation invariant intact after binary garbage");

    // 5e. Export -> Reset -> Import roundtrip via separate files
    const std::string activeProfilePath = tempDir + "\\appdata\\gamepad\\profile.ltx";
    const std::string exportFilePath = tempDir + "\\appdata\\gamepad\\exports\\custom_layout_export.ltx";

    BindingProfileModel customModel;
    // Customize: swap Confirm and Back in MenuUI, set Jump to North (Y) and NextWeapon to South (A) in World_Gameplay
    CHECK(customModel.SetBinding(ContextId::MenuUI, ActionId::Confirm, BindingTrigger::MakeButton(ButtonId::East), true).Succeeded(),
          "customize MenuUI Confirm=B");
    CHECK(customModel.SetBinding(ContextId::World_Gameplay, ActionId::Jump, BindingTrigger::MakeButton(ButtonId::North), true).Succeeded(),
          "customize World Jump=Y");

    std::string ioErr;
    CHECK(customModel.ExportToFile(exportFilePath, &ioErr), "ExportToFile succeeded: %s", ioErr.c_str());

    // Reset model to defaults and verify customization is gone
    customModel.ResetToDefaults();
    CHECK(customModel.FindBinding(ContextId::MenuUI, ActionId::Confirm)->button == ButtonId::South, "After reset Confirm=A");
    CHECK(customModel.FindBinding(ContextId::World_Gameplay, ActionId::Jump)->button == ButtonId::South, "After reset Jump=A");

    // Import from exportFilePath and auto-persist to activeProfilePath
    LoadReport impRep = customModel.ImportFromFile(exportFilePath, activeProfilePath);
    CHECK(impRep.status == LoadStatus::Ok, "ImportFromFile status == Ok (%s)", impRep.detail.c_str());
    CHECK(customModel.FindBinding(ContextId::MenuUI, ActionId::Confirm)->button == ButtonId::East,
          "After import Confirm=B restored");
    CHECK(customModel.FindBinding(ContextId::MenuUI, ActionId::Back)->button == ButtonId::South,
          "After import Back=A restored");
    CHECK(customModel.FindBinding(ContextId::World_Gameplay, ActionId::Jump)->button == ButtonId::North,
          "After import Jump=Y restored");

    // Reload from persisted activeProfilePath into a fresh instance to verify disk persistence
    BindingProfileModel reloadedModel;
    LoadReport reloadRep = reloadedModel.LoadFromFile(activeProfilePath);
    CHECK(reloadRep.status == LoadStatus::Ok, "Reload from persisted profile.ltx Ok");
    CHECK(reloadedModel.FindBinding(ContextId::MenuUI, ActionId::Confirm)->button == ButtonId::East,
          "Reloaded Confirm=B");
    CHECK(reloadedModel.FindBinding(ContextId::World_Gameplay, ActionId::Jump)->button == ButtonId::North,
          "Reloaded Jump=Y");
}

// 6. Emergency Reset: Hold Start + Back 5s in any context OR console gp_bind_reset (D4.1 item 5)
static void TestEmergencyReset(const std::string& tempDir)
{
    const std::string activeProfilePath = tempDir + "\\appdata\\gamepad\\profile_emergency.ltx";
    BindingProfileModel m;

    // Customize bindings away from default
    m.SetBinding(ContextId::MenuUI, ActionId::Confirm, BindingTrigger::MakeButton(ButtonId::East), true);
    m.SetBinding(ContextId::World_Gameplay, ActionId::Jump, BindingTrigger::MakeButton(ButtonId::North), true);
    m.SaveToFile(activeProfilePath);

    const std::uint32_t comboMask = Bit(ButtonId::Start) | Bit(ButtonId::Back);

    // Hold Start + Back for 4900 ms (< 5000 ms) -> does NOT trigger reset yet
    for (int i = 0; i < 49; ++i)
    {
        const bool fired = m.UpdateEmergencyResetHold(comboMask, 100, activeProfilePath);
        CHECK(!fired, "Start+Back before 5000ms must not reset (step %d)", i);
    }
    CHECK(m.GetEmergencyResetHoldElapsedMs() == 4900, "elapsed == 4900ms");
    CHECK(m.FindBinding(ContextId::World_Gameplay, ActionId::Jump)->button == ButtonId::North, "Jump still Y at 4900ms");

    // Release Back before 5000 ms -> timer resets to 0
    CHECK(!m.UpdateEmergencyResetHold(Bit(ButtonId::Start), 100, activeProfilePath), "Release Back cancels timer");
    CHECK(m.GetEmergencyResetHoldElapsedMs() == 0, "Timer reset to 0 on release");

    // Hold Start + Back for full 5000 ms -> triggers emergency reset!
    bool triggeredAt5000 = false;
    for (int i = 0; i < 50; ++i)
    {
        if (m.UpdateEmergencyResetHold(comboMask, 100, activeProfilePath))
            triggeredAt5000 = true;
    }
    CHECK(triggeredAt5000, "Holding Start+Back for 5000ms triggers emergency reset");
    CHECK(m.GetEmergencyResetCount() == 1 && m.GetLastEmergencyResetReason() == "start_plus_back_5s",
          "Emergency reset count=1 reason=start_plus_back_5s");
    CHECK(m.FindBinding(ContextId::MenuUI, ActionId::Confirm)->button == ButtonId::South,
          "Confirm restored to default A after 5s hold");
    CHECK(m.FindBinding(ContextId::World_Gameplay, ActionId::Jump)->button == ButtonId::South,
          "Jump restored to default A after 5s hold");

    // Continuing to hold Start + Back without releasing must NOT re-trigger in a loop
    CHECK(!m.UpdateEmergencyResetHold(comboMask, 1000, activeProfilePath),
          "Latched until physical release of Start+Back");

    // Test console reset (gp_bind_reset)
    m.SetBinding(ContextId::World_Gameplay, ActionId::Jump, BindingTrigger::MakeButton(ButtonId::North), true);
    CHECK(m.FindBinding(ContextId::World_Gameplay, ActionId::Jump)->button == ButtonId::North, "Jump changed to Y");
    m.ExecuteEmergencyReset("gp_bind_reset", activeProfilePath);
    CHECK(m.GetEmergencyResetCount() == 2 && m.GetLastEmergencyResetReason() == "gp_bind_reset",
          "gp_bind_reset increments reset count");
    CHECK(m.FindBinding(ContextId::World_Gameplay, ActionId::Jump)->button == ButtonId::South,
          "gp_bind_reset restored Jump=A");

    // Verify persisted file on disk also has default Jump=A
    BindingProfileModel diskModel;
    diskModel.LoadFromFile(activeProfilePath);
    CHECK(diskModel.FindBinding(ContextId::World_Gameplay, ActionId::Jump)->button == ButtonId::South,
          "Emergency reset persisted default bindings to profile file");
}

// 7. Fuzz test: 1000 random sequences of SetBinding/UnbindAction/SwapBindings and corrupt LTX deserialization
// must NEVER break VerifyMenuNavigationInvariant() or leave un-sanitized triggers.
static void TestFuzzMenuProtectionAndParser()
{
    std::uint32_t seed = 0xD41BEEFu;
    auto next = [&]() {
        seed = seed * 1664525u + 1013904223u;
        return seed;
    };

    BindingProfileModel m;
    int invariantViolations = 0;
    const int ops = 2000;
    for (int i = 0; i < ops; ++i)
    {
        const ContextId ctx = (next() & 1) ? ContextId::MenuUI : ContextId::MainMenu;
        const ActionId act = static_cast<ActionId>(next() % 10);
        const std::uint32_t op = next() % 3;
        if (op == 0)
        {
            BindingTrigger t;
            t.type = static_cast<TriggerType>(next() % 4);
            t.button = static_cast<ButtonId>(next() % 20);
            t.modifier = static_cast<ButtonId>(next() % 20);
            t.hold_ms = static_cast<std::uint16_t>(next() % 5000);
            m.SetBinding(ctx, act, t, (next() & 1) != 0);
        }
        else if (op == 1)
        {
            m.UnbindAction(ctx, act);
        }
        else
        {
            const ActionId actB = static_cast<ActionId>(next() % 10);
            m.SwapBindings(ctx, act, actB);
        }

        if (!m.VerifyMenuNavigationInvariant())
            ++invariantViolations;
    }
    std::printf("fuzz_menu_invariant ops=%d violations=%d\n", ops, invariantViolations);
    CHECK(invariantViolations == 0, "MenuUI/MainMenu invariant violated %d times during fuzz", invariantViolations);
}

// 8. K2 verification: WeaponWheel=hold:Y:220 + NextWeapon=button:Y in World_Gameplay,
// gp_ctx world_bindings diagnostic output, and ReloadActiveBindingProfileIfModifiedOnDisk().
static void TestK2WorldBindingsDiagnosticAndHotReload(const std::string& tempDir)
{
    namespace fs = std::filesystem;
    fs::create_directories(tempDir);
    const std::string k2ProfilePath = tempDir + "\\k2_profile.ltx";
    SetActiveBindingProfilePath(k2ProfilePath.c_str());

    BindingProfileModel& prof = GetMutableActiveBindingProfile();
    prof.ResetToDefaults();
    prof.SetBinding(ContextId::World_Gameplay, ActionId::WeaponWheel,
                    BindingTrigger::MakeHold(ButtonId::North, 220), true);
    CHECK(SaveActiveBindingProfile(), "K2 profile saved to disk");

    // Verify both NextWeapon=button:Y and WeaponWheel=hold:Y:220 coexist in World_Gameplay
    const BindingTrigger* nextWpn = prof.FindBinding(ContextId::World_Gameplay, ActionId::NextWeapon);
    const BindingTrigger* wpnWheel = prof.FindBinding(ContextId::World_Gameplay, ActionId::WeaponWheel);
    CHECK(nextWpn && nextWpn->type == TriggerType::Button && nextWpn->button == ButtonId::North,
          "K2 NextWeapon remains button:Y");
    CHECK(wpnWheel && wpnWheel->type == TriggerType::Hold && wpnWheel->button == ButtonId::North && wpnWheel->hold_ms == 220,
          "K2 WeaponWheel is hold:Y:220");

    std::string worldBindsLine;
    for (const auto& entry : prof.GetBindingsForContext(ContextId::World_Gameplay))
    {
        if (!worldBindsLine.empty())
            worldBindsLine += " ";
        worldBindsLine += std::string(BindingProfileModel::ActionToString(entry.action)) + "=" +
                          BindingProfileModel::FormatTriggerSpec(entry.trigger);
    }
    std::printf("* [Gamepad] gp_ctx world_bindings (D4.1/K2): %s\n", worldBindsLine.c_str());
    CHECK(worldBindsLine.find("WeaponWheel=hold:Y:220") != std::string::npos,
          "gp_ctx world_bindings contains WeaponWheel=hold:Y:220");
    CHECK(worldBindsLine.find("NextWeapon=button:Y") != std::string::npos,
          "gp_ctx world_bindings contains NextWeapon=button:Y");

    // Verify ReloadActiveBindingProfileIfModifiedOnDisk() reloads modified LTX file without restart
    CHECK(!ReloadActiveBindingProfileIfModifiedOnDisk(), "No reload when file mtime unchanged");
    BindingProfileModel externalWriter;
    externalWriter.ResetToDefaults();
    externalWriter.SetBinding(ContextId::World_Gameplay, ActionId::WeaponWheel,
                              BindingTrigger::MakeHold(ButtonId::RightShoulder, 260), true);
    // Advance file write time by writing again after a tiny sleep or touching file_time_type
    CHECK(externalWriter.SaveToFile(k2ProfilePath), "External writer saved updated profile");
    std::error_code ec;
    fs::last_write_time(k2ProfilePath, fs::last_write_time(k2ProfilePath, ec) + std::chrono::seconds(2), ec);
    CHECK(ReloadActiveBindingProfileIfModifiedOnDisk(), "Hot reload detected modified profile.ltx on disk");
    const BindingTrigger* reloadedWheel = prof.FindBinding(ContextId::World_Gameplay, ActionId::WeaponWheel);
    CHECK(reloadedWheel && reloadedWheel->type == TriggerType::Hold &&
              reloadedWheel->button == ButtonId::RightShoulder && reloadedWheel->hold_ms == 260,
          "Active profile hot-reloaded WeaponWheel=hold:RB:260 from disk");
}

// 9. W4-PORTG-HARDEN: GamepadAtomicFile atomic replacement + foreign sections ([gp_icons], [wheel_qaw], [source])
static void TestW4AtomicSaveAndForeignSections(const std::string& tempDir)
{
    namespace fs = std::filesystem;
    fs::create_directories(tempDir);

    // Direct smoke check of GpTempPathFor + GpCommitTempFile
    const std::string targetFile = tempDir + "\\atomic_smoke.ltx";
    const std::string tmpFile = GpTempPathFor(targetFile.c_str());
    CHECK(tmpFile == targetFile + ".tmp", "GpTempPathFor appends .tmp");
    {
        std::ofstream ofs(tmpFile, std::ios::binary | std::ios::trunc);
        ofs << "[test]\nkey = 1\n";
    }
    CHECK(GpCommitTempFile(tmpFile.c_str(), targetFile.c_str()), "GpCommitTempFile replaces target");
    CHECK(fs::exists(targetFile) && !fs::exists(tmpFile), "Target exists and .tmp removed after commit");

    // Seed profile.ltx with [gp_icons], [wheel_qaw], and [source] sections, then save & reload bindings
    const std::string profPath = tempDir + "\\w4_foreign_sections_profile.ltx";
    {
        std::ofstream ofs(profPath, std::ios::binary | std::ios::trunc);
        ofs << "[gp_icons]\nset = dualsense\n\n[wheel_qaw]\nslot_1 = medkit\n\n[source]\nmode = gamepad_only\n";
    }

    BindingProfileModel writer;
    writer.ResetToDefaults();
    std::string saveErr;
    CHECK(writer.SaveToFile(profPath, &saveErr), "SaveToFile succeeded with foreign sections: %s", saveErr.c_str());
    CHECK(!fs::exists(profPath + ".tmp"), "No leftover .tmp after SaveToFile");

    BindingProfileModel reader;
    const LoadReport rep = reader.LoadFromFile(profPath);
    CHECK(rep.status == LoadStatus::Ok, "Foreign sections load cleanly without RecoveredFromCorrupt (got %d: %s)",
          static_cast<int>(rep.status), rep.detail.c_str());
    CHECK(rep.corrupted_lines_skipped == 0, "Zero corrupted_lines_skipped on [gp_icons]/[wheel_qaw]/[source] (got %d)",
          rep.corrupted_lines_skipped);

    std::ifstream ifs(profPath, std::ios::binary);
    const std::string finalBody((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
    CHECK(finalBody.find("[gp_icons]") != std::string::npos && finalBody.find("set = dualsense") != std::string::npos,
          "[gp_icons] preserved across atomic SaveToFile");
    CHECK(finalBody.find("[wheel_qaw]") != std::string::npos && finalBody.find("slot_1 = medkit") != std::string::npos,
          "[wheel_qaw] preserved across atomic SaveToFile");
    CHECK(finalBody.find("[source]") != std::string::npos && finalBody.find("mode = gamepad_only") != std::string::npos,
          "[source] preserved across atomic SaveToFile");
}

// 10. CURSOR1: ActionId::MouseCursor default MenuUI R3 binding, string roundtrip, and [cursor] foreign section preservation
static void TestCursorActionAndSection(const std::string& tempDir)
{
    namespace fs = std::filesystem;
    fs::create_directories(tempDir);

    CHECK(static_cast<std::uint16_t>(ActionId::MouseCursor) == 57 &&
              static_cast<std::uint16_t>(ActionId::WheelLaser) == 59 &&
              static_cast<std::uint16_t>(ActionId::Count) == 60, // FIX-LIVE2 p.15: WheelMaskClean=58, WheelLaser=59
          "ActionId::MouseCursor == 57, WheelLaser == 59, Count == 60");

    CHECK(std::string(BindingProfileModel::ActionToString(ActionId::MouseCursor)) == "MouseCursor",
          "ActionToString(MouseCursor) == MouseCursor");
    CHECK(BindingProfileModel::StringToAction("MouseCursor") == ActionId::MouseCursor,
          "StringToAction(\"MouseCursor\") == MouseCursor");
    CHECK(BindingProfileModel::StringToAction("mousecursor") == ActionId::MouseCursor,
          "StringToAction(\"mousecursor\") == MouseCursor");
    CHECK(BindingProfileModel::StringToAction("mouse_cursor") == ActionId::MouseCursor,
          "StringToAction(\"mouse_cursor\") == MouseCursor");
    CHECK(BindingProfileModel::StringToAction("MOUSE_CURSOR") == ActionId::MouseCursor,
          "StringToAction(\"MOUSE_CURSOR\") == MouseCursor");

    BindingProfileModel m;
    const BindingTrigger* mc = m.FindBinding(ContextId::MenuUI, ActionId::MouseCursor);
    CHECK(mc != nullptr && mc->type == TriggerType::Button && mc->button == ButtonId::RightStick,
          "default MenuUI MouseCursor == button:R3");

    const auto menuCanon = BindingProfileModel::GetCanonicalActionsForContext(ContextId::MenuUI);
    bool foundInCanon = false;
    for (ActionId a : menuCanon)
    {
        if (a == ActionId::MouseCursor)
            foundInCanon = true;
    }
    CHECK(foundInCanon, "MouseCursor is in GetCanonicalActionsForContext(MenuUI)");

    // Rebinding MouseCursor to Hold(L3, 300) and Chord(LB + R3) in MenuUI works cleanly and roundtrips
    CHECK(m.SetBinding(ContextId::MenuUI, ActionId::MouseCursor,
                       BindingTrigger::MakeHold(ButtonId::LeftStick, 300), true)
              .Succeeded(),
          "Rebind MenuUI MouseCursor to hold:L3:300");

    const std::string cursorProfPath = tempDir + "\\cursor1_profile.ltx";
    {
        std::ofstream ofs(cursorProfPath, std::ios::binary | std::ios::trunc);
        ofs << "[cursor]\nsize = 1.50\nspeed = 1.25\n\n[gp_icons]\nset = xbox\n";
    }
    std::string saveErr;
    CHECK(m.SaveToFile(cursorProfPath, &saveErr), "SaveToFile with [cursor] section succeeded: %s", saveErr.c_str());

    BindingProfileModel reader;
    const LoadReport rep = reader.LoadFromFile(cursorProfPath);
    CHECK(rep.status == LoadStatus::Ok && rep.corrupted_lines_skipped == 0,
          "[cursor] foreign section loaded with status=Ok and 0 corrupted lines (status=%d, skipped=%u)",
          static_cast<int>(rep.status), rep.corrupted_lines_skipped);

    const BindingTrigger* loadedMc = reader.FindBinding(ContextId::MenuUI, ActionId::MouseCursor);
    CHECK(loadedMc != nullptr && loadedMc->type == TriggerType::Hold &&
              loadedMc->button == ButtonId::LeftStick && loadedMc->hold_ms == 300,
          "Reloaded MenuUI MouseCursor == hold:L3:300");

    std::ifstream ifs(cursorProfPath, std::ios::binary);
    const std::string body((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
    CHECK(body.find("[cursor]") != std::string::npos &&
              body.find("size = 1.50") != std::string::npos &&
              body.find("speed = 1.25") != std::string::npos,
          "[cursor] section and keys preserved across atomic SaveToFile");
}

int main(int argc, char** argv)
{
    std::string tempDir = "_build\\tests\\gamepad_bindings\\tmp";
    if (argc > 1 && argv[1] && argv[1][0])
        tempDir = argv[1];

    TestDefaultsAndTriggerTypes();
    TestRuntimeGestureEvaluation();
    TestConflictDetector();
    TestProtectedMenuNavigation();
    TestVersionedStorageMigrationAndCorruptRecovery(tempDir);
    TestEmergencyReset(tempDir);
    TestFuzzMenuProtectionAndParser();
    TestK2WorldBindingsDiagnosticAndHotReload(tempDir);
    TestW4AtomicSaveAndForeignSections(tempDir);
    TestCursorActionAndSection(tempDir);

    std::printf("RESULT pass=%d fail=%d\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
