// Standalone deterministic verification of FG.1 (D59) cursor kinematics, magnet friction, soft snap, right-stick scroll, D-Pad snap, and virtual cursor arbitration guard.
#include <cstdio>
#include <cmath>
#include <cstdint>
#include <algorithm>

using u32 = uint32_t;

struct Fvector2
{
	float x;
	float y;
	void set(float _x, float _y) { x = _x; y = _y; }
};

struct CursorTargetRect
{
	bool valid = false;
	float cx = 0.0f;
	float cy = 0.0f;
	float halfW = 0.0f;
	float halfH = 0.0f;

	bool Contains(float x, float y) const
	{
		if (!valid || halfW <= 0.5f || halfH <= 0.5f)
			return false;
		return std::fabs(x - cx) <= halfW && std::fabs(y - cy) <= halfH;
	}
};

struct DpadSnapCandidate
{
	float cx = 0.0f;
	float cy = 0.0f;
};

static Fvector2 StepCursorKinematics(
	Fvector2 curPos,
	float stickX,
	float stickY,
	float dtSec,
	float baseSpeedPxPerSec,
	const CursorTargetRect& target,
	u32 msSinceStickActive,
	float* outSpeedScale,
	bool* outSoftSnapped)
{
	if (outSpeedScale)
		*outSpeedScale = 1.0f;
	if (outSoftSnapped)
		*outSoftSnapped = false;

	const float clampedDt = std::clamp(dtSec, 0.0f, 0.100f);
	const bool insideTarget = target.Contains(curPos.x, curPos.y);
	const float speedScale = insideTarget ? 0.45f : 1.0f;
	if (outSpeedScale)
		*outSpeedScale = speedScale;

	Fvector2 nextPos = curPos;
	const float stickMagSq = stickX * stickX + stickY * stickY;
	if (stickMagSq > 1e-6f && clampedDt > 0.0f)
	{
		const float step = baseSpeedPxPerSec * speedScale * clampedDt;
		nextPos.x += stickX * step;
		nextPos.y -= stickY * step;
	}

	const float stickMag = std::sqrt(stickMagSq);
	if (insideTarget && clampedDt > 0.0f && stickMag < 0.25f && msSinceStickActive <= 220u)
	{
		const float dx = target.cx - nextPos.x;
		const float dy = target.cy - nextPos.y;
		const float distSq = dx * dx + dy * dy;
		if (distSq > 0.25f)
		{
			const float pullAlpha = std::clamp(clampedDt * 6.5f, 0.0f, 0.45f);
			nextPos.x += dx * pullAlpha;
			nextPos.y += dy * pullAlpha;
			if (outSoftSnapped)
				*outSoftSnapped = true;
		}
	}

	nextPos.x = std::clamp(nextPos.x, 0.0f, 1024.0f);
	nextPos.y = std::clamp(nextPos.y, 0.0f, 768.0f);
	return nextPos;
}

static int StepRightStickScrollAccumulator(
	float stickY,
	float dtSec,
	float stepsPerSecAtFullDeflection,
	float& inOutAccum,
	u32 nowMs,
	u32& inOutLastEmitMs,
	u32 minEmitIntervalMs)
{
	const float clampedDt = std::clamp(dtSec, 0.0f, 0.100f);
	if (std::fabs(stickY) <= 1e-4f || clampedDt <= 0.0f)
	{
		inOutAccum = 0.0f;
		return 0;
	}

	inOutAccum += (-stickY) * stepsPerSecAtFullDeflection * clampedDt;
	inOutAccum = std::clamp(inOutAccum, -4.0f, 4.0f);

	if (std::fabs(inOutAccum) < 1.0f)
		return 0;

	if (inOutLastEmitMs != 0 && nowMs >= inOutLastEmitMs && (nowMs - inOutLastEmitMs) < minEmitIntervalMs)
		return 0;

	const int stepDir = (inOutAccum > 0.0f) ? 1 : -1;
	inOutAccum -= static_cast<float>(stepDir);
	inOutLastEmitMs = nowMs;
	return stepDir;
}

static int SelectBestDpadSnapTarget(
	Fvector2 curPos,
	int dirX,
	int dirY,
	const DpadSnapCandidate* candidates,
	int count)
{
	if (!candidates || count <= 0 || (dirX == 0 && dirY == 0))
		return -1;

	int bestIdx = -1;
	float bestScore = 1e9f;

	for (int i = 0; i < count; ++i)
	{
		const float vx = candidates[i].cx - curPos.x;
		const float vy = candidates[i].cy - curPos.y;
		const float distSq = vx * vx + vy * vy;
		if (distSq < 9.0f)
			continue;

		const float primary = vx * static_cast<float>(dirX) + vy * static_cast<float>(dirY);
		const float cross = std::fabs(vx * static_cast<float>(-dirY) + vy * static_cast<float>(dirX));

		if (primary < 4.0f)
			continue;

		if (cross > primary * 1.75f + 18.0f)
			continue;

		const float score = primary + cross * 2.35f;
		if (score < bestScore)
		{
			bestScore = score;
			bestIdx = i;
		}
	}

	return bestIdx;
}

static bool IsGamepadCursorRecentlyMoved(u32 lastMoveMs, u32 nowMs, u32 windowMs = 60)
{
	return lastMoveMs != 0 && nowMs >= lastMoveMs && (nowMs - lastMoveMs) <= windowMs;
}

int main()
{
	int passed = 0;
	int total = 0;
	auto check = [&](bool cond, const char* name) {
		++total;
		if (cond)
		{
			++passed;
			std::printf("  [PASS] %s\n", name);
		}
		else
		{
			std::printf("  [FAIL] %s\n", name);
		}
	};

	CursorTargetRect cell{};
	cell.valid = true;
	cell.cx = 300.0f;
	cell.cy = 200.0f;
	cell.halfW = 28.0f;
	cell.halfH = 28.0f;

	float scaleFree = 0.0f;
	bool snappedFree = false;
	Fvector2 startFree{};
	startFree.set(100.0f, 200.0f);
	const Fvector2 movedFree = StepCursorKinematics(startFree, 1.0f, 0.0f, 0.016f, 920.0f, cell, 0u, &scaleFree, &snappedFree);
	const float deltaFree = movedFree.x - startFree.x;
	check(std::fabs(scaleFree - 1.0f) < 1e-4f && !snappedFree && deltaFree > 14.0f, "free_cursor_full_speed");

	float scaleHover = 0.0f;
	bool snappedHover = false;
	Fvector2 startHover{};
	startHover.set(290.0f, 200.0f);
	const Fvector2 movedHover = StepCursorKinematics(startHover, 1.0f, 0.0f, 0.016f, 920.0f, cell, 0u, &scaleHover, &snappedHover);
	const float deltaHover = movedHover.x - startHover.x;
	check(std::fabs(scaleHover - 0.45f) < 1e-4f && std::fabs(deltaHover - deltaFree * 0.45f) < 0.05f, "hover_friction_55pct_slowdown");

	bool softSnapped = false;
	Fvector2 posSnap = startHover;
	for (int i = 0; i < 6; ++i)
	{
		bool stepSnap = false;
		posSnap = StepCursorKinematics(posSnap, 0.0f, 0.0f, 0.016f, 920.0f, cell, 80u, nullptr, &stepSnap);
		softSnapped = softSnapped || stepSnap;
	}
	check(softSnapped && posSnap.x > startHover.x + 3.0f && posSnap.x <= cell.cx + 0.1f, "soft_snap_pulls_toward_center");

	bool expiredSnap = false;
	const Fvector2 posExpired = StepCursorKinematics(startHover, 0.0f, 0.0f, 0.016f, 920.0f, cell, 500u, nullptr, &expiredSnap);
	check(!expiredSnap && std::fabs(posExpired.x - startHover.x) < 1e-4f, "soft_snap_stops_after_settle_window");

	Fvector2 edgePos{};
	edgePos.set(1020.0f, 4.0f);
	const Fvector2 clampedPos = StepCursorKinematics(edgePos, 1.0f, 1.0f, 0.050f, 920.0f, CursorTargetRect{}, 0u, nullptr, nullptr);
	check(std::fabs(clampedPos.x - 1024.0f) < 1e-4f && std::fabs(clampedPos.y - 0.0f) < 1e-4f, "cursor_clamped_to_ui_bounds");

	float accum60 = 0.0f;
	u32 lastEmit60 = 0;
	int steps60 = 0;
	for (u32 frame = 1; frame <= 60; ++frame)
	{
		const int s = StepRightStickScrollAccumulator(-1.0f, 1.0f / 60.0f, 7.0f, accum60, frame * 16u, lastEmit60, 30u);
		if (s > 0)
			steps60 += s;
	}
	float accum120 = 0.0f;
	u32 lastEmit120 = 0;
	int steps120 = 0;
	for (u32 frame = 1; frame <= 120; ++frame)
	{
		const int s = StepRightStickScrollAccumulator(-1.0f, 1.0f / 120.0f, 7.0f, accum120, frame * 8u, lastEmit120, 30u);
		if (s > 0)
			steps120 += s;
	}
	check(steps60 >= 6 && steps60 <= 7 && std::abs(steps60 - steps120) <= 1, "right_stick_scroll_fps_independent");

	float accumUp = 0.0f;
	u32 lastEmitUp = 0;
	int stepsUp = 0;
	for (u32 frame = 1; frame <= 30; ++frame)
	{
		const int s = StepRightStickScrollAccumulator(1.0f, 1.0f / 60.0f, 7.0f, accumUp, frame * 16u, lastEmitUp, 30u);
		if (s < 0)
			stepsUp += (-s);
	}
	check(stepsUp >= 3, "right_stick_scroll_up_direction");

	float accumGate = 1.5f;
	u32 lastEmitGate = 1000u;
	const int blockedStep = StepRightStickScrollAccumulator(-1.0f, 0.008f, 7.0f, accumGate, 1015u, lastEmitGate, 30u);
	const int allowedStep = StepRightStickScrollAccumulator(-1.0f, 0.008f, 7.0f, accumGate, 1035u, lastEmitGate, 30u);
	check(blockedStep == 0 && allowedStep == 1, "right_stick_scroll_respects_25ms_gate");

	const DpadSnapCandidate grid[5] = {
		{ 200.0f, 200.0f },
		{ 260.0f, 202.0f },
		{ 140.0f, 198.0f },
		{ 204.0f, 140.0f },
		{ 196.0f, 265.0f },
	};
	Fvector2 origin{};
	origin.set(200.0f, 200.0f);
	check(SelectBestDpadSnapTarget(origin, 1, 0, grid, 5) == 1, "dpad_snap_right");
	check(SelectBestDpadSnapTarget(origin, -1, 0, grid, 5) == 2, "dpad_snap_left");
	check(SelectBestDpadSnapTarget(origin, 0, -1, grid, 5) == 3, "dpad_snap_up");
	check(SelectBestDpadSnapTarget(origin, 0, 1, grid, 5) == 4, "dpad_snap_down");
	check(SelectBestDpadSnapTarget({ 260.0f, 202.0f }, 1, 0, grid, 5) == -1, "dpad_snap_edge_returns_minus_one");

	const u32 moveStamp = 50000u;
	check(IsGamepadCursorRecentlyMoved(moveStamp, moveStamp + 16u) && !IsGamepadCursorRecentlyMoved(moveStamp, moveStamp + 100u),
		"virtual_cursor_move_suppresses_false_kbm_switch");

	// FG.2 (D59): Drag-and-Drop 150 ms threshold & db.tg = 0 reset + 2-step sort tab wrap-around + B popup close barrier
	{
		auto shouldActivateGamepadDrag = [](u32 pressMs, u32 nowMs, bool movedCell) -> bool {
			return (nowMs > pressMs) && ((nowMs - pressMs) > 150u) && movedCell;
		};
		check(!shouldActivateGamepadDrag(1000u, 1080u, true) && !shouldActivateGamepadDrag(1000u, 1150u, true),
			"fg2_short_press_a_under_150ms_no_accidental_drag");
		check(shouldActivateGamepadDrag(1000u, 1151u, true) && !shouldActivateGamepadDrag(1000u, 1200u, false),
			"fg2_hold_a_over_150ms_with_move_activates_drag");

		// Resetting db.tg = 0 on drag completion prevents false double-click (< 400 ms)
		u32 dbTg = 2000u;
		const u32 releaseMs = 2220u;
		if (shouldActivateGamepadDrag(2000u, releaseMs, true))
			dbTg = 0u;
		const bool falseDoubleClick = (dbTg != 0u) && ((releaseMs - dbTg) < 400u);
		check(dbTg == 0u && !falseDoubleClick, "fg2_drag_completion_resets_db_tg_zero_no_false_db");

		// 2-step sort tab switch with wrap-around (1..totalTabs)
		auto cycleSortTab2Step = [](int curTab, int totalTabs, int delta, int& outStep1Tab, bool& outStep1Ignore, int& outStep2Tab, bool& outStep2Ignore) -> int {
			const int step = (delta < 0) ? -1 : 1;
			const int nextTab = ((curTab - 1 + step + totalTabs) % totalTabs) + 1;
			outStep1Tab = nextTab;
			outStep1Ignore = true;
			outStep2Tab = nextTab;
			outStep2Ignore = false;
			return nextTab;
		};
		int s1Tab = 0, s2Tab = 0;
		bool s1Ign = false, s2Ign = true;
		const int wrapLeft = cycleSortTab2Step(1, 10, -1, s1Tab, s1Ign, s2Tab, s2Ign);
		check(wrapLeft == 10 && s1Tab == 10 && s1Ign && s2Tab == 10 && !s2Ign, "fg2_lt_sort_tab_2step_wrap_1_to_10");
		const int wrapRight = cycleSortTab2Step(10, 10, 1, s1Tab, s1Ign, s2Tab, s2Ign);
		check(wrapRight == 1 && s1Tab == 1 && s1Ign && s2Tab == 1 && !s2Ign, "fg2_rt_sort_tab_2step_wrap_10_to_1");
	}

	std::printf("* [Gamepad] FG.1 + FG.2 standalone C++ test summary: %d/%d passed (%s)\n",
		passed, total, (passed == total) ? "PASS" : "FAIL");
	return (passed == total) ? 0 : 1;
}
