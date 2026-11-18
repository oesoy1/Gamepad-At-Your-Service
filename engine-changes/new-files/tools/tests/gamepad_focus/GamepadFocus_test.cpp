#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "GamepadFocusGraph.h"

using namespace gpfocus;

namespace
{
    int g_total_tests      = 0;
    int g_passed_tests     = 0;
    int g_failed_tests     = 0;
    int g_old_regressions  = 0;
    int g_old_evaluated    = 0;

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
            if (evaluate_old)
            {
                ++g_old_evaluated;
                if (!old_passed)
                {
                    ++g_old_regressions;
                    std::printf("[PASS] %-36s | %-52s | OLD_BEHAVIOR: FAIL (REGRESSION CAUGHT)\n",
                        case_id, description);
                }
                else
                {
                    std::printf("[PASS] %-36s | %-52s | OLD_BEHAVIOR: PASS\n",
                        case_id, description);
                }
            }
            else
            {
                std::printf("[PASS] %-36s | %s\n", case_id, description);
            }
        }
        else
        {
            ++g_failed_tests;
            std::printf("[FAIL] %-36s | %s\n", case_id, description);
        }
    }

    FocusNode MakeItem(
        uint32_t           node_id,
        uint16_t           obj_id,
        uint64_t           inst_gen,
        const std::string& section,
        int32_t            list_idx,
        int16_t            gx        = 0,
        int16_t            gy        = 0,
        int16_t            gw        = 1,
        int16_t            gh        = 1,
        uint16_t           cond_perm = 1000,
        uint16_t           uses      = 1,
        int32_t            cell_indx = -1,
        uint32_t           sess_gen  = 1)
    {
        FocusNode n;
        n.node_id                = node_id;
        n.kind                   = FocusNodeKind::Item;
        n.stable_id.session_gen  = sess_gen;
        n.stable_id.object_id    = obj_id;
        n.stable_id.instance_gen = inst_gen;
        n.key.section            = section;
        n.key.cond_permille      = cond_perm;
        n.key.uses_or_ammo       = uses;
        n.key.list_index         = list_idx;
        n.key.grid_x             = gx;
        n.key.grid_y             = gy;
        n.key.grid_w             = gw;
        n.key.grid_h             = gh;
        n.key.cell_indx          = (cell_indx >= 0) ? cell_indx : list_idx;
        n.label                  = section + "#" + std::to_string(obj_id);
        return n;
    }

    // =========================================================================
    // Блок 1: Удаление в 1D-списке (первый, средний, предпоследний, последний,
    //         единственный, все сразу, восстановление из пустого)
    // =========================================================================
    void TestBlock1_Delete1D()
    {
        std::printf("\n--- Block 1: 1D List Deletion & Empty Recovery (8 cases) ---\n");

        auto makeInitial5 = []() -> std::vector<FocusNode>
        {
            return {
                MakeItem(1, 101, 1, "bandage",      0),
                MakeItem(2, 102, 1, "medkit",       1),
                MakeItem(3, 103, 1, "antirad",      2),
                MakeItem(4, 104, 1, "conserva",     3),
                MakeItem(5, 105, 1, "water_bottle", 4)
            };
        };

        // Case 01: Delete first item (index 0 -> new index 0, NeighborBelow)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag1D", FocusLayoutMode::List1D, 1, false);
            auto items = makeInitial5();
            fg.RebuildGroupItems(g, items, 0, 100);
            fg.SetFocusedNode(g, 1);

            std::vector<FocusNode> after = { items[1], items[2], items[3], items[4] };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC01_1D_Del_First",
                "Delete first item (idx 0) -> NeighborBelow (medkit#102)",
                r == FocusRestoreReason::NeighborBelow && cur && cur->stable_id.object_id == 102,
                true, old_node == 2);
        }

        // Case 02: Delete middle item (index 2 -> new index 2, NeighborBelow)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag1D", FocusLayoutMode::List1D, 1, false);
            auto items = makeInitial5();
            fg.RebuildGroupItems(g, items, 0, 100);
            fg.SetFocusedNode(g, 3); // antirad at idx 2

            std::vector<FocusNode> after = { items[0], items[1], items[3], items[4] };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC02_1D_Del_Middle",
                "Delete middle item (idx 2) -> NeighborBelow (conserva#104)",
                r == FocusRestoreReason::NeighborBelow && cur && cur->stable_id.object_id == 104,
                true, old_node == 4);
        }

        // Case 03: Delete second-to-last item (index 3 -> new index 3, NeighborBelow)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag1D", FocusLayoutMode::List1D, 1, false);
            auto items = makeInitial5();
            fg.RebuildGroupItems(g, items, 0, 100);
            fg.SetFocusedNode(g, 4); // conserva at idx 3

            std::vector<FocusNode> after = { items[0], items[1], items[2], items[4] };
            auto r = fg.RebuildGroupItems(g, after, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC03_1D_Del_Penultimate",
                "Delete penultimate item (idx 3) -> NeighborBelow (water#105)",
                r == FocusRestoreReason::NeighborBelow && cur && cur->stable_id.object_id == 105);
        }

        // Case 04: Delete last item (index 4 -> NeighborAbove index 3; OLD loses focus!)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag1D", FocusLayoutMode::List1D, 1, false);
            auto items = makeInitial5();
            fg.RebuildGroupItems(g, items, 0, 100);
            fg.SetFocusedNode(g, 5); // water_bottle at idx 4

            std::vector<FocusNode> after = { items[0], items[1], items[2], items[3] };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC04_1D_Del_Last",
                "Delete last item (idx 4) -> NeighborAbove (conserva#104)",
                r == FocusRestoreReason::NeighborAbove && cur && cur->stable_id.object_id == 104,
                true, old_node == 4);
        }

        // Case 05: Delete single item (1 -> 0 items -> EmptyGroupHeader; OLD returns invalid!)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag1D", FocusLayoutMode::List1D, 1, false);
            std::vector<FocusNode> single = { MakeItem(1, 101, 1, "bandage", 0) };
            fg.RebuildGroupItems(g, single, 0, 100);
            fg.SetFocusedNode(g, 1);

            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior({}, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, {}, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC05_1D_Del_Single",
                "Delete single item (1->0) -> EmptyGroupHeader (valid node)",
                r == FocusRestoreReason::EmptyGroupHeader && cur && cur->kind == FocusNodeKind::EmptyStatePlaceholder,
                true, old_node != kInvalidNodeId);
        }

        // Case 06: Delete all 5 items at once ("Drop All" / "Move All" 5->0 -> EmptyGroupHeader)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag1D", FocusLayoutMode::List1D, 1, false);
            auto items = makeInitial5();
            fg.RebuildGroupItems(g, items, 0, 100);
            fg.SetFocusedNode(g, 3);

            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior({}, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, {}, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC06_1D_Del_All",
                "Delete all items at once (5->0) -> EmptyGroupHeader",
                r == FocusRestoreReason::EmptyGroupHeader && cur && cur->kind == FocusNodeKind::EmptyStatePlaceholder,
                true, old_node != kInvalidNodeId);
        }

        // Case 07: Populate empty group with new unrelated items after settle window -> FirstInGroup or Neighbor
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag1D", FocusLayoutMode::List1D, 1, false);
            std::vector<FocusNode> later_items = {
                MakeItem(10, 501, 1, "bread",   0),
                MakeItem(11, 502, 1, "kolbasa", 1)
            };
            auto r = fg.RebuildGroupItems(g, later_items, 0, 500);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC07_1D_Populate_From_Empty",
                "Populate initially empty group (0->2) -> FirstInGroup (bread#501)",
                r == FocusRestoreReason::FirstInGroup && cur && cur->stable_id.object_id == 501);
        }

        // Case 08: Delete focused item when a duplicate of the same section exists further down -> SimilarNearby
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag1D", FocusLayoutMode::List1D, 1, false);
            std::vector<FocusNode> items = {
                MakeItem(1, 101, 1, "medkit",  0, 0, 0, 1, 1, 1000),
                MakeItem(2, 102, 1, "bandage", 1, 0, 1, 1, 1, 1000),
                MakeItem(3, 103, 1, "medkit",  2, 0, 2, 1, 1, 800)
            };
            fg.RebuildGroupItems(g, items, 0, 100);
            fg.SetFocusedNode(g, 1); // first medkit#101

            // medkit#101 consumed; bandage#102 is at idx 0, second medkit#103 is at idx 1
            std::vector<FocusNode> after = { items[1], items[2] };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC08_1D_Del_With_Duplicate_Section",
                "Delete medkit#101 -> SimilarNearby selects remaining medkit#103",
                r == FocusRestoreReason::SimilarNearby && cur && cur->stable_id.object_id == 103,
                true, old_node == 3);
        }
    }

    // =========================================================================
    // Блок 2: Удаление в 2D-сетке (верхний левый, центр, нижний правый,
    //         конец неполной строки, многоклеточный предмет 5x2)
    // =========================================================================
    void TestBlock2_Delete2DGrid()
    {
        std::printf("\n--- Block 2: 2D Grid Deletion & Fallbacks (6 cases) ---\n");

        // Case 09: Delete top-left cell (0,0) in 2x2 grid -> NeighborBelow picks (1,0) on same row
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Grid", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> grid = {
                MakeItem(1, 201, 1, "bandage",  0, 0, 0, 1, 1),
                MakeItem(2, 202, 1, "antirad",  1, 1, 0, 1, 1),
                MakeItem(3, 203, 1, "conserva", 2, 0, 1, 1, 1),
                MakeItem(4, 204, 1, "vodka",    3, 1, 1, 1, 1)
            };
            fg.RebuildGroupItems(g, grid, 0, 100);
            fg.SetFocusedNode(g, 1); // (0,0)

            std::vector<FocusNode> after = { grid[1], grid[2], grid[3] };
            auto r = fg.RebuildGroupItems(g, after, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC09_2D_Del_TopLeft",
                "2D Grid delete (0,0) -> NeighborBelow picks (1,0) antirad#202",
                r == FocusRestoreReason::NeighborBelow && cur && cur->stable_id.object_id == 202);
        }

        // Case 10: Delete right-end of row 0 (1,0) -> NeighborBelow picks (0,1) on next row below
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Grid", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> grid = {
                MakeItem(1, 201, 1, "bandage",  0, 0, 0, 1, 1),
                MakeItem(2, 202, 1, "antirad",  1, 1, 0, 1, 1),
                MakeItem(3, 203, 1, "conserva", 2, 1, 1, 1, 1)
            };
            fg.RebuildGroupItems(g, grid, 0, 100);
            fg.SetFocusedNode(g, 2); // (1,0)

            std::vector<FocusNode> after = { grid[0], grid[2] };
            auto r = fg.RebuildGroupItems(g, after, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC10_2D_Del_RowEnd_HasBelow",
                "2D Grid delete (1,0) -> NeighborBelow picks (1,1) conserva#203",
                r == FocusRestoreReason::NeighborBelow && cur && cur->stable_id.object_id == 203);
        }

        // Case 11: Delete bottom-right last item (1,1) -> NeighborAbove picks nearest above/left
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Grid", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> grid = {
                MakeItem(1, 201, 1, "bandage",  0, 0, 0, 1, 1),
                MakeItem(2, 202, 1, "antirad",  1, 1, 0, 1, 1),
                MakeItem(3, 203, 1, "conserva", 2, 0, 1, 1, 1),
                MakeItem(4, 204, 1, "vodka",    3, 1, 1, 1, 1)
            };
            fg.RebuildGroupItems(g, grid, 0, 100);
            fg.SetFocusedNode(g, 4); // (1,1)

            std::vector<FocusNode> after = { grid[0], grid[1], grid[2] };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC11_2D_Del_BottomRight",
                "2D Grid delete last (1,1) -> NeighborAbove picks (0,1) conserva#203",
                r == FocusRestoreReason::NeighborAbove && cur && cur->stable_id.object_id == 203,
                true, old_node != kInvalidNodeId);
        }

        // Case 12: Delete sole item on row 1 (0,1) when only row 0 items exist -> NeighborAbove picks (0,0)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Grid", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> grid = {
                MakeItem(1, 201, 1, "bandage",  0, 0, 0, 1, 1),
                MakeItem(2, 202, 1, "antirad",  1, 2, 0, 1, 1),
                MakeItem(3, 203, 1, "conserva", 2, 0, 1, 1, 1)
            };
            fg.RebuildGroupItems(g, grid, 0, 100);
            fg.SetFocusedNode(g, 3); // (0,1)

            std::vector<FocusNode> after = { grid[0], grid[1] };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC12_2D_Del_LastRow_SingleCell",
                "2D Grid delete (0,1) -> NeighborAbove picks (0,0) Directly Above",
                r == FocusRestoreReason::NeighborAbove && cur && cur->stable_id.object_id == 201,
                true, old_node != kInvalidNodeId);
        }

        // Case 13: Delete 5x2 multi-cell rifle at (0,0) -> NeighborBelow picks item at (0,2)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Grid", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> grid = {
                MakeItem(1, 210, 1, "wpn_ak74",  0, 0, 0, 5, 2),
                MakeItem(2, 211, 1, "ammo_5.45", 1, 0, 2, 2, 1),
                MakeItem(3, 212, 1, "medkit",    2, 2, 2, 1, 1)
            };
            fg.RebuildGroupItems(g, grid, 0, 100);
            fg.SetFocusedNode(g, 1);

            std::vector<FocusNode> after = { grid[1], grid[2] };
            auto r = fg.RebuildGroupItems(g, after, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC13_2D_Del_MultiCell_5x2",
                "2D Grid delete 5x2 rifle at (0,0) -> NeighborBelow ammo#211 at (0,2)",
                r == FocusRestoreReason::NeighborBelow && cur && cur->stable_id.object_id == 211);
        }

        // Case 14: Delete all items in 2D grid -> EmptyGroupHeader
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Grid", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> grid = {
                MakeItem(1, 210, 1, "wpn_ak74",  0, 0, 0, 5, 2),
                MakeItem(2, 211, 1, "ammo_5.45", 1, 0, 2, 2, 1)
            };
            fg.RebuildGroupItems(g, grid, 0, 100);
            fg.SetFocusedNode(g, 2);

            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior({}, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, {}, 0, 110);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC14_2D_Del_All_To_Empty",
                "2D Grid delete all -> EmptyGroupHeader",
                r == FocusRestoreReason::EmptyGroupHeader && cur && cur->kind == FocusNodeKind::EmptyStatePlaceholder,
                true, old_node != kInvalidNodeId);
        }
    }

    // =========================================================================
    // Блок 3: Использование стака (UICellItem:ResetToChild и расходование до нуля)
    // =========================================================================
    void TestBlock3_StackConsumption()
    {
        std::printf("\n--- Block 3: Stack Consumption & ResetToChild (6 cases) ---\n");

        // Case 15: Stack of 3 medkits at cell_indx=4: use top item (201), child (202) promoted via ResetToChild
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> before = {
                MakeItem(1, 201, 1, "medkit_army", 0, 0, 0, 1, 1, 1000, 3, 4),
                MakeItem(2, 210, 1, "wpn_pm",      1, 1, 0, 2, 1, 950,  1, 5)
            };
            fg.RebuildGroupItems(g, before, 0, 100);
            fg.SetFocusedNode(g, 1);

            std::vector<FocusNode> after = {
                MakeItem(10, 202, 2, "medkit_army", 0, 0, 0, 1, 1, 1000, 2, 4),
                MakeItem(2,  210, 1, "wpn_pm",      1, 1, 0, 2, 1, 950,  1, 5)
            };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 120);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC15_Stack_ResetToChild_3to2",
                "Use stack 3->2 (ResetToChild changes ID 201->202 in cell 4)",
                r == FocusRestoreReason::StackPromotedChild && cur && cur->stable_id.object_id == 202,
                true, old_node == 10);
        }

        // Case 16: Second use of same stack (2->1): child 203 promoted via ResetToChild
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> before = {
                MakeItem(10, 202, 2, "medkit_army", 0, 0, 0, 1, 1, 1000, 2, 4),
                MakeItem(2,  210, 1, "wpn_pm",      1, 1, 0, 2, 1, 950,  1, 5)
            };
            fg.RebuildGroupItems(g, before, 0, 120);
            fg.SetFocusedNode(g, 10);

            std::vector<FocusNode> after = {
                MakeItem(11, 203, 3, "medkit_army", 0, 0, 0, 1, 1, 1000, 1, 4),
                MakeItem(2,  210, 1, "wpn_pm",      1, 1, 0, 2, 1, 950,  1, 5)
            };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 140);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC16_Stack_ResetToChild_2to1",
                "Use stack 2->1 (ResetToChild changes ID 202->203 in cell 4)",
                r == FocusRestoreReason::StackPromotedChild && cur && cur->stable_id.object_id == 203,
                true, old_node == 11);
        }

        // Case 17: Multi-use item (e.g. cheese/water 3/3 -> 2/3 uses) keeping SAME StableItemID
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> before = {
                MakeItem(1, 250, 1, "mineral_water", 0, 0, 0, 1, 1, 1000, 3, 1),
                MakeItem(2, 251, 1, "bread",         1, 1, 0, 1, 1, 1000, 1, 2)
            };
            fg.RebuildGroupItems(g, before, 0, 100);
            fg.SetFocusedNode(g, 1);

            std::vector<FocusNode> after = {
                MakeItem(1, 250, 1, "mineral_water", 0, 0, 0, 1, 1, 667, 2, 1),
                MakeItem(2, 251, 1, "bread",         1, 1, 0, 1, 1, 1000, 1, 2)
            };
            auto r = fg.RebuildGroupItems(g, after, 0, 120);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC17_MultiUse_Decrement_SameID",
                "Multi-use item decrements uses 3->2 with same StableItemID -> SameItem",
                r == FocusRestoreReason::SameItem && cur && cur->stable_id.object_id == 250 && cur->key.uses_or_ammo == 2);
        }

        // Case 18: Final stack item consumed (1->0) when another stack of same section exists in another cell -> SimilarNearby
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> before = {
                MakeItem(1, 260, 1, "ammo_9x19_fmj", 0, 0, 0, 1, 1, 1000, 5,  1),
                MakeItem(2, 261, 1, "wpn_beretta",   1, 1, 0, 2, 1, 900,  1,  2),
                MakeItem(3, 262, 1, "ammo_9x19_fmj", 2, 3, 0, 1, 1, 1000, 15, 3)
            };
            fg.RebuildGroupItems(g, before, 0, 100);
            fg.SetFocusedNode(g, 1);

            // Stack #260 at (0,0) exhausted; wpn_beretta is at (1,0), second ammo stack #262 is at (3,0)
            std::vector<FocusNode> after = { before[1], before[2] };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 120);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC18_Stack_Exhausted_To_SimilarStack",
                "Exhaust stack #260 -> SimilarNearby jumps to second ammo stack #262",
                r == FocusRestoreReason::SimilarNearby && cur && cur->stable_id.object_id == 262,
                true, old_node == 3);
        }

        // Case 19: Final stack item consumed (1->0) when NO other item of same section exists -> NeighborBelow
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> before = {
                MakeItem(1, 260, 1, "ammo_9x19_fmj", 0, 0, 0, 1, 1, 1000, 5, 1),
                MakeItem(2, 261, 1, "wpn_beretta",   1, 1, 0, 2, 1, 900,  1, 2)
            };
            fg.RebuildGroupItems(g, before, 0, 100);
            fg.SetFocusedNode(g, 1);

            std::vector<FocusNode> after = { before[1] };
            auto r = fg.RebuildGroupItems(g, after, 0, 120);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC19_Stack_Exhausted_To_Neighbor",
                "Exhaust last stack of section -> NeighborBelow (wpn_beretta#261)",
                r == FocusRestoreReason::NeighborBelow && cur && cur->stable_id.object_id == 261);
        }

        // Case 20: Stack consumption in 1D list via ResetToChild (same cell_indx, new object_id)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag1D", FocusLayoutMode::List1D, 1, false);
            std::vector<FocusNode> before = {
                MakeItem(1, 270, 1, "bandage", 0, 0, 0, 1, 1, 1000, 4, 10),
                MakeItem(2, 271, 1, "vodka",   1, 0, 1, 1, 1, 1000, 1, 11)
            };
            fg.RebuildGroupItems(g, before, 0, 100);
            fg.SetFocusedNode(g, 1);

            std::vector<FocusNode> after = {
                MakeItem(5, 275, 2, "bandage", 0, 0, 0, 1, 1, 1000, 3, 10),
                MakeItem(2, 271, 1, "vodka",   1, 0, 1, 1, 1, 1000, 1, 11)
            };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 120);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC20_1D_Stack_ResetToChild",
                "1D list stack ResetToChild -> StackPromotedChild (bandage#275)",
                r == FocusRestoreReason::StackPromotedChild && cur && cur->stable_id.object_id == 275,
                true, old_node == 5);
        }
    }

    // =========================================================================
    // Блок 4: Перенос предметов между колонками (ActorBag <-> LootBag) и View (D24)
    // =========================================================================
    void TestBlock4_TransferAndColumnSwitch()
    {
        std::printf("\n--- Block 4: Item Transfer & View Column Switching D24 (7 cases) ---\n");

        FocusGraph fg;
        uint32_t g_actor = fg.AddGroup("ActorBag", FocusLayoutMode::Grid2D, 1, false);
        uint32_t g_loot  = fg.AddGroup("LootBag",  FocusLayoutMode::Grid2D, 2, false);

        std::vector<FocusNode> actor_items = {
            MakeItem(1, 301, 1, "wpn_ak74",  0, 0, 0, 5, 2, 850),
            MakeItem(2, 302, 1, "medkit",    1, 0, 2, 1, 1, 1000),
            MakeItem(3, 303, 1, "conserva",  2, 1, 2, 1, 1, 1000)
        };
        std::vector<FocusNode> loot_items = {
            MakeItem(10, 401, 1, "af_medusa",   0, 0, 0, 1, 1, 1000),
            MakeItem(11, 402, 1, "af_cristall", 1, 1, 0, 1, 1, 1000),
            MakeItem(12, 403, 1, "ammo_5.45",   2, 0, 1, 2, 1, 1000)
        };

        fg.RebuildGroupItems(g_actor, actor_items, 0, 100);
        fg.RebuildGroupItems(g_loot,  loot_items,  0, 100);

        // Case 21: Focus item #2 (medkit#302) in ActorBag, switch to LootBag via View, focus item #11 (af_cristall#402)
        fg.SetFocusedNode(g_actor, 2);
        fg.SwitchGroupNext(110);
        fg.SetFocusedNode(g_loot, 11);
        CheckCase("TC21_View_Switch_LeftToRight",
            "Switch ActorBag -> LootBag via View and select af_cristall#402",
            fg.GetActiveGroupId() == g_loot && fg.GetFocusedNode()->stable_id.object_id == 402);

        // Case 22: Switch back to ActorBag via View -> remembers medkit#302!
        fg.SwitchGroupNext(120);
        CheckCase("TC22_View_Switch_RemembersLeft",
            "Switch LootBag -> ActorBag via View restores remembered medkit#302",
            fg.GetActiveGroupId() == g_actor && fg.GetFocusedNode()->stable_id.object_id == 302);

        // Case 23: Switch to LootBag via View -> remembers af_cristall#402!
        fg.SwitchGroupNext(130);
        CheckCase("TC23_View_Switch_RemembersRight",
            "Switch ActorBag -> LootBag via View restores remembered af_cristall#402",
            fg.GetActiveGroupId() == g_loot && fg.GetFocusedNode()->stable_id.object_id == 402);

        // Case 24: Transfer af_cristall#402 from LootBag to ActorBag:
        //   LootBag loses af_cristall#402 -> focus moves to NeighborBelow (ammo_5.45#403)
        //   ActorBag gains af_cristall#402 -> keeps its remembered focus on medkit#302 (SameItem)
        std::vector<FocusNode> loot_after_t1 = { loot_items[0], loot_items[2] };
        std::vector<FocusNode> actor_after_t1 = {
            actor_items[0], actor_items[1], actor_items[2],
            MakeItem(4, 402, 1, "af_cristall", 3, 2, 2, 1, 1, 1000)
        };
        auto r_loot1  = fg.RebuildGroupItems(g_loot,  loot_after_t1,  0, 140);
        auto r_actor1 = fg.RebuildGroupItems(g_actor, actor_after_t1, 0, 140);
        CheckCase("TC24_Transfer_Middle_LootToActor",
            "Transfer af_cristall#402: Loot->ammo#403 (NeighborBelow), Actor keeps medkit#302",
            r_loot1 == FocusRestoreReason::NeighborBelow &&
            fg.GetGroupFocusedNode(g_loot)->stable_id.object_id == 403 &&
            r_actor1 == FocusRestoreReason::SameItem &&
            fg.GetGroupFocusedNode(g_actor)->stable_id.object_id == 302);

        // Case 25: Transfer last item in LootBag (ammo_5.45#403) -> LootBag moves to NeighborAbove (af_medusa#401)
        std::vector<FocusNode> loot_after_t2 = { loot_items[0] };
        auto prev_id  = fg.GetGroup(g_loot)->anchor_stable_id;
        auto prev_key = fg.GetGroup(g_loot)->anchor_key;
        uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(loot_after_t2, prev_id, prev_key, 0, 0);

        auto r_loot2 = fg.RebuildGroupItems(g_loot, loot_after_t2, 0, 150);
        CheckCase("TC25_Transfer_Last_LootToActor",
            "Transfer last item ammo#403: Loot->af_medusa#401 (NeighborAbove)",
            r_loot2 == FocusRestoreReason::NeighborAbove &&
            fg.GetGroupFocusedNode(g_loot)->stable_id.object_id == 401,
            true, old_node != kInvalidNodeId);

        // Case 26: Transfer final remaining item in LootBag (af_medusa#401) -> LootBag becomes EmptyGroupHeader
        uint32_t old_empty = FocusGraph::RestoreFocusNaiveOldBehavior({}, loot_items[0].stable_id, fg.GetGroup(g_loot)->anchor_key, 0, 0);
        auto r_loot3 = fg.RebuildGroupItems(g_loot, {}, 0, 160);
        CheckCase("TC26_Transfer_Sole_LootToEmpty",
            "Transfer sole item af_medusa#401: Loot->EmptyGroupHeader",
            r_loot3 == FocusRestoreReason::EmptyGroupHeader &&
            fg.GetGroupFocusedNode(g_loot)->kind == FocusNodeKind::EmptyStatePlaceholder,
            true, old_empty != kInvalidNodeId);

        // Case 27: While in LootBag, medkit#302 in ActorBag is consumed by script/hotkey ->
        //   when switching back to ActorBag via View, focus deterministically lands on NeighborBelow (conserva#303)
        std::vector<FocusNode> actor_after_consume = {
            actor_after_t1[0], actor_after_t1[2], actor_after_t1[3]
        };
        auto r_actor2 = fg.RebuildGroupItems(g_actor, actor_after_consume, 0, 170);
        fg.SwitchGroupNext(180);
        CheckCase("TC27_View_Switch_AfterInactiveGroupMutated",
            "Inactive ActorBag loses remembered item -> View switch lands on conserva#303",
            r_actor2 == FocusRestoreReason::NeighborBelow &&
            fg.GetActiveGroupId() == g_actor &&
            fg.GetFocusedNode()->stable_id.object_id == 303);
    }

    // =========================================================================
    // Блок 5: Пересортировка (SortingPlus) и эвристика SimilarNearby
    // =========================================================================
    void TestBlock5_ResortingAndSimilarNearby()
    {
        std::printf("\n--- Block 5: Re-sorting (SortingPlus) & SimilarNearby Heuristic (6 cases) ---\n");

        // Case 28: Re-sorting moves focused item from index 3 (3,1) to index 0 (0,0) -> SameItem follows it!
        //   (Old behavior stays on index 3, selecting the wrong item!)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> before = {
                MakeItem(1, 501, 1, "wpn_ak74",  0, 0, 0, 5, 2, 700),
                MakeItem(2, 502, 1, "conserva",  1, 0, 2, 1, 1, 1000),
                MakeItem(3, 503, 1, "bandage",   2, 1, 2, 1, 1, 1000),
                MakeItem(4, 504, 1, "af_medusa", 3, 2, 2, 1, 1, 1000)
            };
            fg.RebuildGroupItems(g, before, 0, 100);
            fg.SetFocusedNode(g, 4); // af_medusa#504 at idx 3

            // Sorted alphabetically/by-kind: af_medusa moves to idx 0 (0,0)
            std::vector<FocusNode> sorted = {
                MakeItem(10, 504, 1, "af_medusa", 0, 0, 0, 1, 1, 1000),
                MakeItem(11, 503, 1, "bandage",   1, 1, 0, 1, 1, 1000),
                MakeItem(12, 502, 1, "conserva",  2, 2, 0, 1, 1, 1000),
                MakeItem(13, 501, 1, "wpn_ak74",  3, 0, 1, 5, 2, 700)
            };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(sorted, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, sorted, 0, 120);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC28_Resort_Follows_SameItem",
                "Re-sort moves af_medusa#504 from idx 3 to idx 0 -> SameItem follows it",
                r == FocusRestoreReason::SameItem && cur && cur->stable_id.object_id == 504 && cur->node_id == 10,
                true, old_node == 10);
        }

        // Case 29: SimilarNearby picks closest by Manhattan distance |dx| + |dy|
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> before = {
                MakeItem(1, 510, 1, "wpn_pm", 0, 2, 2, 2, 1, 800), // focused at (2,2)
                MakeItem(2, 511, 1, "wpn_pm", 1, 0, 0, 2, 1, 800), // dist |0-2|+|0-2| = 4
                MakeItem(3, 512, 1, "wpn_pm", 2, 3, 2, 2, 1, 800)  // dist |3-2|+|2-2| = 1
            };
            fg.RebuildGroupItems(g, before, 0, 100);
            fg.SetFocusedNode(g, 1);

            std::vector<FocusNode> after = { before[1], before[2] };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 120);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC29_SimilarNearby_MinManhattan",
                "SimilarNearby picks wpn_pm#512 at Manhattan dist 1 over #511 at dist 4",
                r == FocusRestoreReason::SimilarNearby && cur && cur->stable_id.object_id == 512,
                true, old_node == 3);
        }

        // Case 30: SimilarNearby tie-breaks equal Manhattan distance by closest condition (cond_permille)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> before = {
                MakeItem(1, 520, 1, "wpn_ak74", 0, 2, 2, 5, 2, 750), // focused at (2,2), cond 750
                MakeItem(2, 521, 1, "wpn_ak74", 1, 2, 0, 5, 2, 300), // dist 2, |300-750| = 450
                MakeItem(3, 522, 1, "wpn_ak74", 2, 2, 4, 5, 2, 740)  // dist 2, |740-750| = 10
            };
            fg.RebuildGroupItems(g, before, 0, 100);
            fg.SetFocusedNode(g, 1);

            std::vector<FocusNode> after = { before[1], before[2] };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 120);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC30_SimilarNearby_ConditionTieBreak",
                "Equal Manhattan dist -> picks wpn_ak74#522 with closest condition (740 vs 750)",
                r == FocusRestoreReason::SimilarNearby && cur && cur->stable_id.object_id == 522,
                true, old_node == 3);
        }

        // Case 31: SimilarNearby tie-breaks equal Manhattan distance and equal condition by smaller list_index
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> before = {
                MakeItem(1, 530, 1, "grenade_f1", 0, 2, 2, 1, 1, 1000),
                MakeItem(2, 531, 1, "grenade_f1", 1, 1, 2, 1, 1, 1000), // dist 1, lower list_index
                MakeItem(3, 532, 1, "grenade_f1", 2, 3, 2, 1, 1, 1000)  // dist 1, higher list_index
            };
            fg.RebuildGroupItems(g, before, 0, 100);
            fg.SetFocusedNode(g, 1);

            std::vector<FocusNode> after = { before[1], before[2] };
            auto r = fg.RebuildGroupItems(g, after, 0, 120);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC31_SimilarNearby_DeterministicIndexTieBreak",
                "Equal Manhattan & condition -> deterministic lower list_index (#531)",
                r == FocusRestoreReason::SimilarNearby && cur && cur->stable_id.object_id == 531);
        }

        // Case 32: QuantizeCondition boundary check (0.0 -> 0, 1.0 -> 1000, 0.7564 -> 756)
        {
            const uint16_t q0   = FocusItemKey::QuantizeCondition(-0.1f);
            const uint16_t q1   = FocusItemKey::QuantizeCondition(1.2f);
            const uint16_t qmid = FocusItemKey::QuantizeCondition(0.7564f);
            CheckCase("TC32_FocusKey_ConditionQuantization",
                "FocusItemKey::QuantizeCondition clamps [0..1000] and rounds permille",
                q0 == 0 && q1 == 1000 && qmid == 756);
        }

        // Case 33: Re-sorting when focused item was simultaneously replaced by new ID (e.g. repack ammo)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> before = {
                MakeItem(1, 540, 1, "bandage",   0, 0, 0, 1, 1, 1000),
                MakeItem(2, 541, 1, "ammo_5.45", 1, 1, 0, 2, 1, 1000, 12, 1),
                MakeItem(3, 542, 1, "vodka",     2, 3, 0, 1, 1, 1000)
            };
            fg.RebuildGroupItems(g, before, 0, 100);
            fg.SetFocusedNode(g, 2); // ammo_5.45#541

            // Ammo repacked into new object #599 and sorted to index 2 (cell 5)
            std::vector<FocusNode> after = {
                MakeItem(10, 540, 1, "bandage",   0, 0, 0, 1, 1, 1000, 1,  0),
                MakeItem(11, 542, 1, "vodka",     1, 1, 0, 1, 1, 1000, 1,  1),
                MakeItem(12, 599, 2, "ammo_5.45", 2, 2, 0, 2, 1, 1000, 30, 5)
            };
            auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
            auto prev_key = fg.GetGroup(g)->anchor_key;
            uint32_t old_node = FocusGraph::RestoreFocusNaiveOldBehavior(after, prev_id, prev_key, 0, 0);

            auto r = fg.RebuildGroupItems(g, after, 0, 120);
            const FocusNode* cur = fg.GetFocusedNode();
            CheckCase("TC33_RepackAndResort_SimilarNearby",
                "Ammo repacked (#541->#599) and re-sorted -> SimilarNearby finds #599",
                r == FocusRestoreReason::SimilarNearby && cur && cur->stable_id.object_id == 599,
                true, old_node == 12);
        }
    }

    // =========================================================================
    // Блок 6: Смена вкладки фильтра (LT/RT — SortingPlus tabs)
    // =========================================================================
    void TestBlock6_TabChange()
    {
        std::printf("\n--- Block 6: Filter Tab Change LT/RT (4 cases) ---\n");

        FocusGraph fg;
        uint32_t g = fg.AddGroup("ActorBag", FocusLayoutMode::Grid2D, 1, false);

        std::vector<FocusNode> tab0_all = {
            MakeItem(1, 601, 1, "wpn_ak74",  0, 0, 0, 5, 2, 800),
            MakeItem(2, 602, 1, "medkit",    1, 0, 2, 1, 1, 1000),
            MakeItem(3, 603, 1, "antirad",   2, 1, 2, 1, 1, 1000),
            MakeItem(4, 604, 1, "conserva",  3, 2, 2, 1, 1, 1000)
        };
        fg.RebuildGroupItems(g, tab0_all, 0, 100);
        fg.SetFocusedNode(g, 3); // antirad#603 at index 2

        // Case 34: Switch from Tab 0 (All) to Tab 1 (Weapons) where antirad#603 is filtered out -> FirstInGroup
        std::vector<FocusNode> tab1_weapons = {
            MakeItem(10, 601, 1, "wpn_ak74", 0, 0, 0, 5, 2, 800),
            MakeItem(11, 605, 1, "wpn_pm",   1, 0, 2, 2, 1, 900)
        };
        auto prev_id  = fg.GetGroup(g)->anchor_stable_id;
        auto prev_key = fg.GetGroup(g)->anchor_key;
        uint32_t old_tab1 = FocusGraph::RestoreFocusNaiveOldBehavior(tab1_weapons, prev_id, prev_key, 0, 1);

        auto r1 = fg.RebuildGroupItems(g, tab1_weapons, 1, 120);
        CheckCase("TC34_TabChange_ItemFilteredOut",
            "Tab 0->1 (focused item filtered out) -> FirstInGroup (wpn_ak74#601)",
            r1 == FocusRestoreReason::FirstInGroup && fg.GetFocusedNode()->stable_id.object_id == 601,
            true, old_tab1 == 10);

        // Case 35: Switch from Tab 1 (Weapons, focused on wpn_pm#605) back to Tab 0 (All, contains wpn_pm#605) -> SameItem
        fg.SetFocusedNode(g, 11); // wpn_pm#605
        std::vector<FocusNode> tab0_with_pm = {
            MakeItem(1, 601, 1, "wpn_ak74", 0, 0, 0, 5, 2, 800),
            MakeItem(2, 602, 1, "medkit",   1, 0, 2, 1, 1, 1000),
            MakeItem(5, 605, 1, "wpn_pm",   2, 1, 2, 2, 1, 900)
        };
        auto r2 = fg.RebuildGroupItems(g, tab0_with_pm, 0, 140);
        CheckCase("TC35_TabChange_ItemStillPresent",
            "Tab 1->0 (focused wpn_pm#605 present in new tab) -> SameItem",
            r2 == FocusRestoreReason::SameItem && fg.GetFocusedNode()->stable_id.object_id == 605);

        // Case 36: Switch to Tab 3 (Artifacts — empty category!) -> EmptyGroupHeader (wireframes.md §2 line 63)
        uint32_t old_tab3 = FocusGraph::RestoreFocusNaiveOldBehavior({}, fg.GetGroup(g)->anchor_stable_id, fg.GetGroup(g)->anchor_key, 0, 3);
        auto r3 = fg.RebuildGroupItems(g, {}, 3, 160);
        CheckCase("TC36_TabChange_EmptyCategory",
            "Tab 0->3 (empty category) -> EmptyGroupHeader (cursor does not vanish)",
            r3 == FocusRestoreReason::EmptyGroupHeader &&
            fg.GetFocusedNode() != nullptr &&
            fg.GetFocusedNode()->kind == FocusNodeKind::EmptyStatePlaceholder,
            true, old_tab3 != kInvalidNodeId);

        // Case 37: Switch from empty Tab 3 back to populated Tab 2 (Meds) -> lands on valid item
        std::vector<FocusNode> tab2_meds = {
            MakeItem(20, 602, 1, "medkit",  0, 0, 0, 1, 1, 1000),
            MakeItem(21, 603, 1, "antirad", 1, 1, 0, 1, 1, 1000)
        };
        auto r4 = fg.RebuildGroupItems(g, tab2_meds, 2, 180);
        CheckCase("TC37_TabChange_EmptyToPopulated",
            "Tab 3 (empty) -> Tab 2 (Meds) -> FirstInGroup (medkit#602)",
            r4 == FocusRestoreReason::FirstInGroup && fg.GetFocusedNode()->stable_id.object_id == 602);
    }

    // =========================================================================
    // Блок 7: StableItemID и SPAWN_ANTIFREEZE (settle_until_ms)
    // =========================================================================
    void TestBlock7_StableItemIdAndAntifreeze()
    {
        std::printf("\n--- Block 7: StableItemID Validation & SPAWN_ANTIFREEZE Window (6 cases) ---\n");

        // Case 38: StableItemID validity checks (0xFFFF invalid, session_gen=0 invalid, instance_gen=0 invalid)
        {
            StableItemID valid_id{ 1, 42, 7 };
            StableItemID bad_sess{ 0, 42, 7 };
            StableItemID bad_obj{ 1, kInvalidObjId, 7 };
            StableItemID bad_inst{ 1, 42, 0 };
            CheckCase("TC38_StableItemID_ValidityInvariants",
                "StableItemID rejects session_gen=0, object_id=0xFFFF, instance_gen=0",
                valid_id.IsValid() && !bad_sess.IsValid() && !bad_obj.IsValid() && !bad_inst.IsValid());
        }

        // Case 39: CID_Generator LIFO reuse of same object_id in same frame (different instance_gen -> NOT SameItem!)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::List1D, 1, false);
            std::vector<FocusNode> before = {
                MakeItem(1, 700, 10, "medkit",  0), // object_id=700, instance_gen=10
                MakeItem(2, 701, 1,  "bandage", 1)
            };
            fg.RebuildGroupItems(g, before, 0, 100);
            fg.SetFocusedNode(g, 1);

            // Object 700 destroyed and immediately reused by CID_Generator for a completely different item (grenade_f1, instance_gen=11)
            std::vector<FocusNode> after = {
                MakeItem(2, 701, 1,  "bandage",    0),
                MakeItem(3, 700, 11, "grenade_f1", 1)
            };
            auto r = fg.RebuildGroupItems(g, after, 0, 110);
            CheckCase("TC39_CID_Generator_LIFO_Reuse_Rejected",
                "Same object_id=700 with new instance_gen=11 is NOT treated as SameItem",
                r != FocusRestoreReason::SameItem && fg.GetFocusedNode()->stable_id.object_id == 701);
        }

        // Case 40: Session generation increment (level reload) invalidates old session's StableItemID
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::List1D, 1, false);
            std::vector<FocusNode> sess1 = {
                MakeItem(1, 700, 10, "medkit",  0, 0, 0, 1, 1, 1000, 1, 0, /*sess_gen=*/1),
                MakeItem(2, 701, 1,  "bandage", 1, 0, 1, 1, 1, 1000, 1, 1, /*sess_gen=*/1)
            };
            fg.RebuildGroupItems(g, sess1, 0, 100);
            fg.SetFocusedNode(g, 2);

            // In session 2, object 701 happens to have instance_gen=1, but session_gen=2 != 1
            std::vector<FocusNode> sess2 = {
                MakeItem(10, 701, 1, "wpn_pm",  0, 0, 0, 1, 1, 1000, 1, 0, /*sess_gen=*/2),
                MakeItem(11, 702, 1, "conserva", 1, 0, 1, 1, 1, 1000, 1, 1, /*sess_gen=*/2)
            };
            auto r = fg.RebuildGroupItems(g, sess2, 0, 500);
            CheckCase("TC40_SessionGen_Increment_RejectsOldSession",
                "session_gen mismatch (1 vs 2) prevents false SameItem match across reloads",
                r != FocusRestoreReason::SameItem);
        }

        // Case 41: SPAWN_ANTIFREEZE 2-frame gap: item disappears at t=1000ms, replacement spawns at t=1050ms (<= 1180ms)
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> frame0 = {
                MakeItem(1, 801, 1, "medkit_army", 0, 0, 0, 1, 1, 1000, 3, 2),
                MakeItem(2, 802, 1, "wpn_ak74",    1, 1, 0, 5, 2, 850,  1, 3)
            };
            fg.RebuildGroupItems(g, frame0, 0, 1000);
            fg.SetFocusedNode(g, 1);

            // Frame 1 (t=1016ms): alife_release removed #801, alife_create is delayed in spawn_queue -> only #802 present
            std::vector<FocusNode> frame1 = { frame0[1] };
            auto r_gap = fg.RebuildGroupItems(g, frame1, 0, 1016, 180);

            // Frame 2 (t=1050ms): alife_create spawned replacement #809 at same cell_indx=2 / (0,0)
            std::vector<FocusNode> frame2 = {
                MakeItem(9, 809, 2, "medkit_army", 0, 0, 0, 1, 1, 1000, 2, 2),
                frame0[1]
            };
            auto r_settled = fg.RebuildGroupItems(g, frame2, 0, 1050, 180);
            CheckCase("TC41_SpawnAntifreeze_ReclaimsWithinWindow",
                "SPAWN_ANTIFREEZE replacement at +50ms (<=180ms) reclaims focus (SpawnAntifreezeSettled)",
                r_gap == FocusRestoreReason::NeighborBelow &&
                r_settled == FocusRestoreReason::SpawnAntifreezeSettled &&
                fg.GetFocusedNode()->stable_id.object_id == 809);
        }

        // Case 42: SPAWN_ANTIFREEZE expired (> 180ms): late spawn at t=1300ms does NOT hijack current focus
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> frame0 = {
                MakeItem(1, 801, 1, "medkit_army", 0, 0, 0, 1, 1, 1000, 3, 2),
                MakeItem(2, 802, 1, "wpn_ak74",    1, 1, 0, 5, 2, 850,  1, 3)
            };
            fg.RebuildGroupItems(g, frame0, 0, 1000);
            fg.SetFocusedNode(g, 1);

            // Disappears at t=1016ms -> focus moves to wpn_ak74#802
            std::vector<FocusNode> frame1 = { frame0[1] };
            fg.RebuildGroupItems(g, frame1, 0, 1016, 180);

            // Late item arrives at t=1300ms (> 1016 + 180 = 1196ms) -> focus stays on wpn_ak74#802 (SameItem)
            std::vector<FocusNode> frame_late = {
                MakeItem(9, 809, 2, "medkit_army", 0, 0, 0, 1, 1, 1000, 2, 2),
                frame0[1]
            };
            auto r_late = fg.RebuildGroupItems(g, frame_late, 0, 1300, 180);
            CheckCase("TC42_SpawnAntifreeze_ExpiresAfterWindow",
                "Late spawn at +284ms (>180ms) does not steal focus from wpn_ak74#802",
                r_late == FocusRestoreReason::SameItem &&
                fg.GetFocusedNode()->stable_id.object_id == 802);
        }

        // Case 43: Manual D-Pad move during SPAWN_ANTIFREEZE window cancels pending_anchor
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> frame0 = {
                MakeItem(1, 801, 1, "medkit_army", 0, 0, 0, 1, 1, 1000, 3, 2),
                MakeItem(2, 802, 1, "wpn_ak74",    1, 1, 0, 5, 2, 850,  1, 3),
                MakeItem(3, 803, 1, "conserva",    2, 1, 2, 1, 1, 1000, 1, 4)
            };
            fg.RebuildGroupItems(g, frame0, 0, 1000);
            fg.SetFocusedNode(g, 1);

            // #801 disappears at t=1010ms -> focus falls back to #802
            std::vector<FocusNode> frame1 = { frame0[1], frame0[2] };
            fg.RebuildGroupItems(g, frame1, 0, 1010, 180);

            // User presses Down at t=1030ms to select conserva#803 -> cancels pending_anchor!
            fg.MoveFocus(NavDir::Down, 1030);

            // At t=1050ms #809 arrives, but user already moved to #803 -> stays on #803!
            std::vector<FocusNode> frame2 = {
                MakeItem(9, 809, 2, "medkit_army", 0, 0, 0, 1, 1, 1000, 2, 2),
                frame0[1],
                frame0[2]
            };
            auto r_after_move = fg.RebuildGroupItems(g, frame2, 0, 1050, 180);
            CheckCase("TC43_SpawnAntifreeze_CancelledByManualMove",
                "Manual D-Pad Down during settle window cancels pending_anchor (stays on #803)",
                r_after_move == FocusRestoreReason::SameItem &&
                fg.GetFocusedNode()->stable_id.object_id == 803);
        }

        // Case 43b (TC49): When SimilarNearby matches a second stack of the same section, pending_anchor is NOT left active
        // to hijack focus away from the second stack!
        {
            FocusGraph fg;
            uint32_t g = fg.AddGroup("Bag", FocusLayoutMode::Grid2D, 1, false);
            std::vector<FocusNode> frame0 = {
                MakeItem(1, 811, 1, "ammo_9x19", 0, 0, 0, 1, 1, 1000, 10, 1),
                MakeItem(2, 812, 1, "ammo_9x19", 1, 2, 0, 1, 1, 1000, 15, 2)
            };
            fg.RebuildGroupItems(g, frame0, 0, 1000);
            fg.SetFocusedNode(g, 1);

            // Stack #811 exhausted -> SimilarNearby selects #812 at cell 2
            std::vector<FocusNode> frame1 = { frame0[1] };
            auto r_sim = fg.RebuildGroupItems(g, frame1, 0, 1020, 180);

            // Within 180ms (t=1060ms), a new item #819 is placed in cell 1 -> focus stays on #812 (SameItem), not hijacked!
            std::vector<FocusNode> frame2 = {
                MakeItem(9, 819, 2, "ammo_9x19", 0, 0, 0, 1, 1, 1000, 5, 1),
                frame0[1]
            };
            auto r_stay = fg.RebuildGroupItems(g, frame2, 0, 1060, 180);
            CheckCase("TC49_SimilarNearby_ClearsPendingAnchor",
                "SimilarNearby match (#812) clears pending_anchor so cell 1 does not hijack focus",
                r_sim == FocusRestoreReason::SimilarNearby &&
                r_stay == FocusRestoreReason::SameItem &&
                fg.GetFocusedNode()->stable_id.object_id == 812);
        }
    }

    // =========================================================================
    // Блок 8: 2D-навигация по многоклеточной сетке, память колонки preferred_col и дамп
    // =========================================================================
    void TestBlock8_GridNavigationAndDump()
    {
        std::printf("\n--- Block 8: 2D Multi-Cell Grid Navigation & Dump (5 cases) ---\n");

        // Layout:
        // Row 0: [Node 1: medkit (0,0) 1x1] [Node 2: bandage (1,0) 1x1] [Node 3: vod (3,0) 1x1]
        // Row 1..2: [Node 4: wpn_ak74 (0,1) 5x2]
        // Row 3: [Node 5: ammo1 (0,3) 1x1]  [Node 6: ammo2 (3,3) 1x1]
        FocusGraph fg;
        uint32_t g = fg.AddGroup("GridNav", FocusLayoutMode::Grid2D, 1, false);
        std::vector<FocusNode> grid = {
            MakeItem(1, 901, 1, "medkit",   0, 0, 0, 1, 1),
            MakeItem(2, 902, 1, "bandage",  1, 1, 0, 1, 1),
            MakeItem(3, 903, 1, "vodka",    2, 3, 0, 1, 1),
            MakeItem(4, 904, 1, "wpn_ak74", 3, 0, 1, 5, 2),
            MakeItem(5, 905, 1, "ammo1",    4, 0, 3, 1, 1),
            MakeItem(6, 906, 1, "ammo2",    5, 3, 3, 1, 1)
        };
        fg.RebuildGroupItems(g, grid, 0, 100);

        // Case 44: Horizontal navigation across row 0: (0,0) -> Right -> (1,0) -> Right -> (3,0)
        fg.SetFocusedNode(g, 1);
        bool r_step1 = fg.MoveFocus(NavDir::Right, 110);
        uint16_t id1 = fg.GetFocusedNode()->stable_id.object_id;
        bool r_step2 = fg.MoveFocus(NavDir::Right, 120);
        uint16_t id2 = fg.GetFocusedNode()->stable_id.object_id;
        CheckCase("TC44_Grid2D_Horizontal_Row0",
            "Grid Right: (0,0) medkit#901 -> (1,0) bandage#902 -> (3,0) vodka#903",
            r_step1 && id1 == 902 && r_step2 && id2 == 903);

        // Case 45: Vertical navigation preserving preferred_col=3 through a 5x2 wide rifle:
        //   Start at vodka#903 (col 3, row 0) -> Down -> wpn_ak74#904 (cols 0..4, rows 1..2) -> Down -> ammo2#906 (col 3, row 3)!
        bool d_step1 = fg.MoveFocus(NavDir::Down, 130);
        uint16_t mid_id = fg.GetFocusedNode()->stable_id.object_id;
        bool d_step2 = fg.MoveFocus(NavDir::Down, 140);
        uint16_t bot_id = fg.GetFocusedNode()->stable_id.object_id;
        CheckCase("TC45_Grid2D_PreferredCol_AcrossWideRifle",
            "Down from col 3 through 5x2 rifle lands on col 3 ammo2#906 (not col 0)",
            d_step1 && mid_id == 904 && d_step2 && bot_id == 906);

        // Case 46: Upward navigation preserving preferred_col=3 back to vodka#903
        bool u_step1 = fg.MoveFocus(NavDir::Up, 150);
        bool u_step2 = fg.MoveFocus(NavDir::Up, 160);
        CheckCase("TC46_Grid2D_PreferredCol_Upward",
            "Up from col 3 through 5x2 rifle returns to col 3 vodka#903",
            u_step1 && u_step2 && fg.GetFocusedNode()->stable_id.object_id == 903);

        // Case 47: FormatDump produces non-empty structured diagnostic output
        std::string dump = fg.FormatDump();
        CheckCase("TC47_FormatDump_ContainsKeyFields",
            "FocusGraph::FormatDump outputs groups, active node, anchor, and neighbors",
            dump.find("[gp_focus_dump]") != std::string::npos &&
            dump.find("GridNav") != std::string::npos &&
            dump.find("Anchor:") != std::string::npos &&
            dump.find("nbr=[U:") != std::string::npos);

        // Case 48: Built-in RunFocusGraphSelfTest passes 100%
        SelfTestSummary st = RunFocusGraphSelfTest();
        CheckCase("TC48_BuiltIn_RunFocusGraphSelfTest",
            "Built-in RunFocusGraphSelfTest() has 0 failures and catches old regressions",
            st.total_cases >= 6 && st.failed_cases == 0 && st.old_behavior_regressions >= 4);
    }

} // anonymous namespace

int main()
{
    std::printf("====================================================================================================\n");
    std::printf(" GAMMA Gamepad Focus Graph & Deterministic Restoration Unit Test Suite (Step F1.1)\n");
    std::printf("====================================================================================================\n");

    TestBlock1_Delete1D();
    TestBlock2_Delete2DGrid();
    TestBlock3_StackConsumption();
    TestBlock4_TransferAndColumnSwitch();
    TestBlock5_ResortingAndSimilarNearby();
    TestBlock6_TabChange();
    TestBlock7_StableItemIdAndAntifreeze();
    TestBlock8_GridNavigationAndDump();

    std::printf("\n====================================================================================================\n");
    std::printf(" SUMMARY:\n");
    std::printf("   New FocusGraph Restoration : %d / %d PASSED (%d FAILED)\n",
        g_passed_tests, g_total_tests, g_failed_tests);
    std::printf("   Old Behavior Comparison    : %d / %d evaluated cases FAILED on old behavior (regressions caught!)\n",
        g_old_regressions, g_old_evaluated);
    std::printf("====================================================================================================\n");

    return (g_failed_tests == 0 && g_total_tests >= 40 && g_old_regressions > 0) ? 0 : 1;
}
