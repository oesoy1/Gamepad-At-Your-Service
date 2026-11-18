// Standalone C++ verification test for FG.4:
// Native G.A.M.M.A. PDA (CUIPdaWnd 2D & 3D, CUIMapWnd, 8 tabs, PAW pins/modals, looted NPC PDAs ui_pda_npc_tab)
// Stylized cursor magnet & D-Pad snap, right stick map zoom / list scroll, LB/RB tabs, A/X/Y/B/View quick buttons (D59).

#include <cstdio>
#include <cmath>
#include <cstring>
#include <vector>
#include <string>
#include <algorithm>

struct Fvector2 {
    float x, y;
    Fvector2() : x(0.f), y(0.f) {}
    Fvector2(float _x, float _y) : x(_x), y(_y) {}
    Fvector2& set(float _x, float _y) { x = _x; y = _y; return *this; }
};

struct Frect {
    float x1, y1, x2, y2;
    Frect() : x1(0), y1(0), x2(0), y2(0) {}
    Frect(float _x1, float _y1, float _x2, float _y2) : x1(_x1), y1(_y1), x2(_x2), y2(_y2) {}
    float width() const { return x2 - x1; }
    float height() const { return y2 - y1; }
    bool in(const Fvector2& p) const { return p.x >= x1 && p.x <= x2 && p.y >= y1 && p.y <= y2; }
};

static float clampr(float v, float lo, float hi) {
    return (v < lo) ? lo : ((v > hi) ? hi : v);
}

// 1. 8-tab cyclic switching (UIPdaWnd::CycleActiveTab)
struct MockPdaTabs {
    std::vector<std::string> tabs = {
        "eptTasks", "eptTaskboard", "eptRanking", "eptRelations",
        "eptContacts", "eptEncyclopedia", "eptRadio", "eptLogs"
    };
    bool tabControlShown = true;
    std::string activeSection = "eptTasks";

    bool CycleActiveTab(int delta) {
        if (delta == 0 || !tabControlShown || tabs.empty())
            return false;
        const int count = static_cast<int>(tabs.size());
        int curIdx = 0;
        for (int i = 0; i < count; ++i) {
            if (tabs[i] == activeSection) {
                curIdx = i;
                break;
            }
        }
        const int nextIdx = ((curIdx + delta) % count + count) % count;
        activeSection = tabs[nextIdx];
        return true;
    }
};

// 2. Map panning (edge pan & LT modifier pan) + Right stick zoom/scroll + X/Y/View/B
struct MockMapAndTaskWnd {
    Frect activeMapRect = Frect(155.f, 115.f, 890.f, 710.f);
    Frect cursorBox3D   = Frect(117.f, 39.f, 903.f, 731.f);
    std::vector<Frect> mapSpots;
    std::vector<int> spotObjIds;

    bool propertiesBoxShown = false;
    std::vector<Frect> propertiesBoxItems;
    bool secondTaskWndShown = false;
    Frect secondTaskWndRect = Frect(160.f, 130.f, 440.f, 680.f);
    std::vector<Frect> secondTaskRows;

    bool pawModalShown = false;
    bool npcPdaSubtabBackShown = false;
    bool pdaShown = true;
    int consumedBarrierCount = 0;

    Fvector2 mapOffset = Fvector2(0.f, 0.f);
    float mapZoom = 1.0f;
    int taskListScrollCalls = 0;
    int viewActorCalls = 0;

    int FindSpotUnderCursor(const Fvector2& cur) const {
        if (!activeMapRect.in(cur)) return -1;
        int bestIdx = -1;
        float bestDistSq = 18.f * 18.f;
        for (size_t i = 0; i < mapSpots.size(); ++i) {
            const Frect& r = mapSpots[i];
            float cx = (r.x1 + r.x2) * 0.5f;
            float cy = (r.y1 + r.y2) * 0.5f;
            if (!activeMapRect.in(Fvector2(cx, cy))) continue;
            float dx = cur.x - cx;
            float dy = cur.y - cy;
            float d2 = dx * dx + dy * dy;
            if (r.in(cur)) d2 *= 0.25f;
            if (d2 <= bestDistSq) {
                bestDistSq = d2;
                bestIdx = static_cast<int>(i);
            }
        }
        return bestIdx;
    }

    bool HandleButtonX(const Fvector2& cur, bool bModifierHeld, Fvector2* outSnapPos) {
        int spotIdx = FindSpotUnderCursor(cur);
        if (spotIdx >= 0 || (bModifierHeld && activeMapRect.in(cur))) {
            propertiesBoxShown = true;
            propertiesBoxItems = {
                Frect(cur.x, cur.y, cur.x + 140.f, cur.y + 20.f),      // header
                Frect(cur.x, cur.y + 20.f, cur.x + 140.f, cur.y + 40.f) // first action
            };
            if (outSnapPos) {
                const Frect& ir = propertiesBoxItems[1];
                outSnapPos->set((ir.x1 + ir.x2) * 0.5f, (ir.y1 + ir.y2) * 0.5f);
            }
            return true;
        }
        viewActorCalls++;
        return true;
    }

    bool ToggleTaskListWnd(Fvector2* outSnapPos) {
        secondTaskWndShown = !secondTaskWndShown;
        if (secondTaskWndShown && outSnapPos && !secondTaskRows.empty()) {
            const Frect& r = secondTaskRows[0];
            outSnapPos->set((r.x1 + r.x2) * 0.5f, (r.y1 + r.y2) * 0.5f);
        }
        return true;
    }

    bool HandleRightStick(float curX, float curY, int wheelDir) {
        if (wheelDir == 0) return false;
        if (secondTaskWndShown && secondTaskWndRect.in(Fvector2(curX, curY))) {
            taskListScrollCalls += (wheelDir > 0 ? 1 : -1);
            return true;
        }
        mapZoom = clampr(mapZoom + (wheelDir > 0 ? 0.25f : -0.25f), 0.5f, 4.0f);
        return true;
    }

    void StepMapPan(float stickX, float stickY, bool bModifierHeld, float curX, float curY, unsigned int dtMs) {
        if (propertiesBoxShown) return;
        float dtSec = clampr(float(dtMs) * 0.001f, 0.001f, 0.1f);
        float panSpeed = 520.f;
        if (bModifierHeld) {
            if (std::fabs(stickX) > 0.05f || std::fabs(stickY) > 0.05f) {
                mapOffset.x += -stickX * panSpeed * dtSec;
                mapOffset.y += stickY * panSpeed * dtSec;
            }
            return;
        }
        if (!activeMapRect.in(Fvector2(curX, curY))) return;
        const float edgeMargin = 28.f;
        if (curX <= activeMapRect.x1 + edgeMargin && stickX < -0.15f)
            mapOffset.x += -stickX * panSpeed * dtSec;
        else if (curX >= activeMapRect.x2 - edgeMargin && stickX > 0.15f)
            mapOffset.x += -stickX * panSpeed * dtSec;
        if (curY <= activeMapRect.y1 + edgeMargin && stickY > 0.15f)
            mapOffset.y += stickY * panSpeed * dtSec;
        else if (curY >= activeMapRect.y2 - edgeMargin && stickY < -0.15f)
            mapOffset.y += stickY * panSpeed * dtSec;
    }

    void HandleButtonB() {
        if (pawModalShown) {
            pawModalShown = false;
            return;
        }
        if (propertiesBoxShown) {
            propertiesBoxShown = false;
            return;
        }
        if (secondTaskWndShown) {
            secondTaskWndShown = false;
            return;
        }
        if (npcPdaSubtabBackShown) {
            npcPdaSubtabBackShown = false;
            return;
        }
        pdaShown = false;
        consumedBarrierCount++;
    }
};

int main() {
    int passed = 0;
    int failed = 0;
    auto check = [&](bool cond, const char* name) {
        if (cond) {
            passed++;
            std::printf("[PASS] %s\n", name);
        } else {
            failed++;
            std::printf("[FAIL] %s\n", name);
        }
    };

    // Test 1: 8-tab cyclic switching with LB/RB and disabled in eptNPC
    {
        MockPdaTabs pda;
        check(pda.activeSection == "eptTasks", "Initial tab is eptTasks");
        check(pda.CycleActiveTab(+1) && pda.activeSection == "eptTaskboard", "RB -> eptTaskboard");
        check(pda.CycleActiveTab(-1) && pda.activeSection == "eptTasks", "LB -> back to eptTasks");
        check(pda.CycleActiveTab(-1) && pda.activeSection == "eptLogs", "LB wraps from eptTasks to eptLogs (8th tab)");
        check(pda.CycleActiveTab(+1) && pda.activeSection == "eptTasks", "RB wraps from eptLogs to eptTasks");

        pda.tabControlShown = false; // eptNPC (looted NPC PDA hides UITabControl)
        check(!pda.CycleActiveTab(+1), "LB/RB disabled when UITabControl is hidden (eptNPC)");
    }

    // Test 2: Map spot detection, X button (PropertiesBox on spot / LT+X on map / ViewActor on empty map)
    {
        MockMapAndTaskWnd m;
        m.mapSpots.push_back(Frect(390.f, 290.f, 410.f, 310.f)); // center (400, 300)
        m.spotObjIds.push_back(1234);

        Fvector2 snap(0.f, 0.f);
        m.HandleButtonX(Fvector2(500.f, 500.f), false, &snap);
        check(m.viewActorCalls == 1 && !m.propertiesBoxShown, "X on empty map calls ViewActor()");

        m.HandleButtonX(Fvector2(402.f, 298.f), false, &snap);
        check(m.propertiesBoxShown && std::fabs(snap.x - 472.f) < 1.f && std::fabs(snap.y - 328.f) < 1.f,
              "X on CMapSpot opens CUIPropertiesBox and snaps cursor to first item");

        m.propertiesBoxShown = false;
        m.HandleButtonX(Fvector2(500.f, 500.f), true, &snap);
        check(m.propertiesBoxShown, "LT + X on empty map opens PAW CUIPropertiesBox");
    }

    // Test 3: View button toggles UISecondTaskWnd and Right Stick zooms map or scrolls task list
    {
        MockMapAndTaskWnd m;
        m.secondTaskRows.push_back(Frect(170.f, 160.f, 420.f, 184.f));
        Fvector2 snap(0.f, 0.f);

        check(m.ToggleTaskListWnd(&snap) && m.secondTaskWndShown, "View button opens UISecondTaskWnd");
        check(std::fabs(snap.x - 295.f) < 1.f && std::fabs(snap.y - 172.f) < 1.f, "Cursor snaps to first task row");

        m.HandleRightStick(295.f, 172.f, -1);
        check(m.taskListScrollCalls == -1 && std::fabs(m.mapZoom - 1.0f) < 1e-4f, "Right stick over UISecondTaskWnd scrolls task list");

        m.HandleRightStick(600.f, 400.f, +1);
        check(std::fabs(m.mapZoom - 1.25f) < 1e-4f, "Right stick over map zooms map in");
    }

    // Test 4: Left stick edge panning and LT modifier panning
    {
        MockMapAndTaskWnd m;
        m.StepMapPan(0.8f, 0.0f, false, 500.f, 400.f, 16);
        check(std::fabs(m.mapOffset.x) < 1e-4f, "Left stick in center of map moves cursor without panning map");

        m.StepMapPan(0.8f, 0.0f, false, 880.f, 400.f, 16);
        check(m.mapOffset.x < -1.0f, "Left stick at map edge smoothly pans map");

        float prevX = m.mapOffset.x;
        m.StepMapPan(-0.8f, 0.5f, true, 500.f, 400.f, 16);
        check(m.mapOffset.x > prevX && m.mapOffset.y > 1.0f, "LT + Left stick pans map directly");
    }

    // Test 5: Layered B close priority & anti-shot barrier on PDA close
    {
        MockMapAndTaskWnd m;
        m.pawModalShown = true;
        m.propertiesBoxShown = true;
        m.secondTaskWndShown = true;
        m.npcPdaSubtabBackShown = true;

        m.HandleButtonB();
        check(!m.pawModalShown && m.propertiesBoxShown && m.pdaShown, "B #1 closes PAW modal window first");
        m.HandleButtonB();
        check(!m.propertiesBoxShown && m.secondTaskWndShown && m.pdaShown, "B #2 closes CUIPropertiesBox second");
        m.HandleButtonB();
        check(!m.secondTaskWndShown && m.npcPdaSubtabBackShown && m.pdaShown, "B #3 closes UISecondTaskWnd third");
        m.HandleButtonB();
        check(!m.npcPdaSubtabBackShown && m.pdaShown, "B #4 returns from NPC PDA subtab to NPC PDA main tab");
        m.HandleButtonB();
        check(!m.pdaShown && m.consumedBarrierCount == 1, "B #5 closes PDA and engages ConsumeAllCurrentlyHeldButtons barrier");
    }

    std::printf("\nFG.4 C++ Standalone Verification: %d passed, %d failed\n", passed, failed);
    return (failed == 0) ? 0 : 1;
}
