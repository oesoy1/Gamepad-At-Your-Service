// S3: Autonomous C++ unit test for GamepadErrorGuard ("Core Armor" & gamepad_last_error.log)
#include "../../../src/xrEngine/GamepadErrorGuard.h"

#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

namespace
{

int g_passed = 0;
int g_failed = 0;

void Check(bool cond, const char* name)
{
    if (cond)
    {
        ++g_passed;
        std::printf("[PASS] %s\n", name);
    }
    else
    {
        ++g_failed;
        std::printf("[FAIL] %s\n", name);
    }
}

std::string ReadFileBytes(const std::string& path)
{
    std::ifstream ifs(path, std::ios::binary);
    if (!ifs)
        return {};
    std::ostringstream oss;
    oss << ifs.rdbuf();
    return oss.str();
}

struct SimulatedEngineInputState
{
    std::int16_t axes[6] = { 0, 0, 0, 0, 0, 0 };
    std::uint32_t buttons_mask = 0;
    std::uint32_t instance_id = 1;
    bool need_release_all = false;
    bool rumble_active = false;
    std::string active_source = "gamepad";
    std::uint32_t frame_id = 100;
    std::uint32_t time_ms = 5000;
    bool device_paused = false;
    int completed_frames = 0;
    int inject_mode = 0; // 0 = normal, 1 = SEH access violation, 2 = C++ exception
};

bool MockRecoveryCallback(const char* stageTag,
                          const char* errorDetail,
                          std::uint32_t sehCode,
                          std::uint64_t sehAddr,
                          const char* contextOverride,
                          const char* recoveryOverride,
                          bool isLuaError,
                          void* userData)
{
    SimulatedEngineInputState* st = static_cast<SimulatedEngineInputState*>(userData);
    if (!st)
        return false;

    gperr::ErrorContextInfo info = {};
    info.stage_tag = stageTag ? stageTag : "CInput::GamepadUpdate";
    info.error_detail = errorDetail ? errorDetail : "unknown";
    info.context_name = (contextOverride && contextOverride[0]) ? contextOverride : "World_Gameplay";
    info.recovery_action = recoveryOverride;
    info.seh_code = sehCode;
    info.seh_addr = sehAddr;
    info.frame_id = st->frame_id;
    info.time_continual_ms = st->time_ms;
    info.gamepad_instance_id = st->instance_id;
    info.buttons_mask = st->buttons_mask;
    for (int i = 0; i < 6; ++i)
        info.axes[i] = st->axes[i];
    info.was_gamepad_active_source = (st->active_source == "gamepad");
    info.was_device_paused = st->device_paused;
    info.pause_tokens_count = st->device_paused ? 1u : 0u;
    info.is_lua_error = isLuaError;
    info.repeat_count = 1;

    // Reset gamepad state to neutral, stop rumble, raise release barrier, switch to KBM
    for (int i = 0; i < 6; ++i)
        st->axes[i] = 0;
    st->buttons_mask = 0;
    st->need_release_all = true;
    st->rumble_active = false;
    st->active_source = "kbm";

    return gperr::RecordEngineGamepadError(info);
}

void SimulatedGamepadPollStep(void* rawCtx)
{
    SimulatedEngineInputState* st = static_cast<SimulatedEngineInputState*>(rawCtx);
    if (!st)
        return;

    if (st->inject_mode == 1)
    {
#ifdef _WIN32
        RaiseException(EXCEPTION_ACCESS_VIOLATION, 0, 0, nullptr);
#endif
    }
    else if (st->inject_mode == 2)
    {
        throw std::runtime_error("artificial_cpp_exception_in_gamepad_poll");
    }

    // Normal frame processing
    st->completed_frames++;
}

} // namespace

int main(int argc, char** argv)
{
    std::string baseDir = (argc > 1 && argv[1] && argv[1][0]) ? argv[1] : "_test_tmp_s3";
    std::error_code ec;
    std::filesystem::remove_all(baseDir, ec);
    std::filesystem::create_directories(baseDir + "/appdata", ec);

    const std::string appDataLog = baseDir + "/appdata/gamepad_last_error.log";
    const std::string rootLog = baseDir + "/gamepad_last_error.log";

    // 1. Built-in self-test
    Check(gperr::RunSelfTest(appDataLog.c_str()), "gperr::RunSelfTest passes on artificial SEH fault and verifies log format");

    // 2. Full simulated per-frame loop with SEH access violation -> frame skipped, neutral reset, KBM switch, next frame continues
    gperr::ResetProtectedErrorStatsForTest();
    gperr::SetDefaultErrorLogPaths(appDataLog.c_str(), rootLog.c_str());

    SimulatedEngineInputState sim = {};
    sim.axes[0] = 18500;
    sim.axes[1] = -14200;
    sim.axes[2] = 9100;
    sim.axes[3] = -6000;
    sim.axes[4] = 12000;
    sim.axes[5] = 28000;
    sim.buttons_mask = 0x00000015u;
    sim.rumble_active = true;
    sim.active_source = "gamepad";
    sim.frame_id = 501;
    sim.time_ms = 24000;

    gperr::SetEngineErrorRecoveryCallback(&MockRecoveryCallback, &sim);

    // Frame 501: normal frame
    sim.inject_mode = 0;
    std::uint32_t sehCode = 0;
    std::uint64_t sehAddr = 0;
    bool okFrame1 = gperr::ExecuteProtectedGamepadStepSEH(&SimulatedGamepadPollStep, &sim, sehCode, sehAddr);
    Check(okFrame1 && sim.completed_frames == 1 && sim.active_source == "gamepad", "Frame 501 (healthy) completes normally on gamepad");

    // Frame 502: artificial SEH Access Violation (0xC0000005) inside gamepad frame poll
    sim.frame_id = 502;
    sim.time_ms = 24016;
    sim.inject_mode = 1;
    bool okFrame2 = gperr::ExecuteProtectedGamepadStepSEH(&SimulatedGamepadPollStep, &sim, sehCode, sehAddr);
    if (!okFrame2)
    {
        gperr::HandleProtectedFrameFailure("CInput::GamepadUpdate", nullptr, sehCode, sehAddr);
    }

    Check(!okFrame2 && sehCode == 0xC0000005u, "Frame 502 SEH Access Violation (0xC0000005) caught without terminating process");
    Check(sim.completed_frames == 1, "Frame 502 faulty body skipped");
    Check(sim.axes[0] == 0 && sim.axes[1] == 0 && sim.axes[2] == 0 && sim.axes[3] == 0 && sim.axes[4] == 0 && sim.axes[5] == 0,
          "Frame 502 all 6 gamepad axes reset to neutral (0)");
    Check(sim.buttons_mask == 0 && sim.need_release_all, "Frame 502 buttons_mask reset to 0 and release barrier raised");
    Check(!sim.rumble_active, "Frame 502 gamepad vibration stopped immediately");
    Check(sim.active_source == "kbm", "Frame 502 active input source switched from gamepad to kbm");

    // Frame 503: game continues running normally on next frame
    sim.frame_id = 503;
    sim.time_ms = 24032;
    sim.inject_mode = 0;
    bool okFrame3 = gperr::ExecuteProtectedGamepadStepSEH(&SimulatedGamepadPollStep, &sim, sehCode, sehAddr);
    Check(okFrame3 && sim.completed_frames == 2, "Frame 503 continues execution normally after error without closing window");

    // Verify both appdata/gamepad_last_error.log and root gamepad_last_error.log exist and have human-readable Russian + technical details
    const std::string appLogContent = ReadFileBytes(appDataLog);
    const std::string rootLogContent = ReadFileBytes(rootLog);
    Check(!appLogContent.empty() && appLogContent == rootLogContent,
          "gamepad_last_error.log written identically to both appdata and bench root");
    Check(appLogContent.find("1. ЧТО ПРОИЗОШЛО:") != std::string::npos &&
              appLogContent.find("2. В КАКОЙ МОМЕНТ ИГРЫ:") != std::string::npos &&
              appLogContent.find("3. ЧТО СДЕЛАЛА ЗАЩИТА:") != std::string::npos,
          "gamepad_last_error.log begins with plain Russian sections (Что произошло / В какой момент игры / Что сделала защита)");
    Check(appLogContent.find("ТЕХНИЧЕСКИЕ ДЕТАЛИ ДЛЯ БЫСТРОЙ ПОЧИНКИ:") != std::string::npos &&
              appLogContent.find("0xC0000005") != std::string::npos &&
              appLogContent.find("LX:18500, LY:-14200") != std::string::npos &&
              appLogContent.find("RESET_TO_NEUTRAL") != std::string::npos,
          "gamepad_last_error.log contains technical details (SEH code, pre-reset axes, RESET_TO_NEUTRAL) below Russian summary");

    // 3. Artificial C++ exception in poll
    sim.axes[0] = 10000;
    sim.buttons_mask = 0x02u;
    sim.active_source = "gamepad";
    sim.frame_id = 504;
    sim.time_ms = 25000;
    sim.inject_mode = 2;
    bool okFrame4 = gperr::ExecuteProtectedGamepadStepSEH(&SimulatedGamepadPollStep, &sim, sehCode, sehAddr);
    if (!okFrame4)
    {
        gperr::HandleProtectedFrameFailure("CInput::GamepadUpdate", nullptr, sehCode, sehAddr);
    }
    Check(!okFrame4 && sehCode == 0xE06D7363u, "Frame 504 C++ std::runtime_error caught by protective guard");
    Check(gperr::GetLastCaughtCppExceptionWhat() == "artificial_cpp_exception_in_gamepad_poll",
          "Frame 504 C++ exception what() message preserved");
    Check(sim.axes[0] == 0 && sim.buttons_mask == 0 && sim.active_source == "kbm",
          "Frame 504 C++ exception resets gamepad to neutral and switches to KBM");

    // 4. Lua error report via RecordSimpleGamepadError (binding used by game.gp_write_last_error_log)
    sim.axes[2] = 22000;
    sim.buttons_mask = 0x10u;
    sim.active_source = "gamepad";
    sim.device_paused = true;
    sim.frame_id = 600;
    sim.time_ms = 30000;
    const bool luaRecOk = gperr::RecordSimpleGamepadError(
        "gp_wheel.on_actor_update",
        "gamedata\\scripts\\gp_wheel.script:142: attempt to index local 'slot' (a nil value)",
        "RadialWheel",
        nullptr,
        true);
    const std::string luaLogContent = ReadFileBytes(appDataLog);
    Check(luaRecOk, "RecordSimpleGamepadError (Lua bridge entrypoint) succeeds");
    Check(luaLogContent.find("колесе быстрого доступа") != std::string::npos &&
              luaLogContent.find("Lua (gp_safe_guard / gp_failover)") != std::string::npos &&
              luaLogContent.find("gp_wheel.on_actor_update") != std::string::npos,
          "Lua error report describes quick wheel moment in plain Russian and records Lua stage_tag");

    gperr::SetEngineErrorRecoveryCallback(nullptr, nullptr);

    std::printf("\n=== S3 GamepadErrorGuard_test SUMMARY: %d passed, %d failed ===\n", g_passed, g_failed);
    return (g_failed == 0) ? 0 : 1;
}
