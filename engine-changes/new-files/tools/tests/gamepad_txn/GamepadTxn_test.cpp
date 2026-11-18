#include "GamepadTxnDispatcher.h"

#include <cstdio>
#include <iostream>
#include <string>

namespace
{
    int g_passed = 0;
    int g_failed = 0;

    void Check(bool cond, const char* expr, const char* file, int line)
    {
        if (cond)
        {
            ++g_passed;
        }
        else
        {
            ++g_failed;
            std::fprintf(stderr, "[FAIL] %s (%s:%d)\n", expr, file, line);
        }
    }
} // namespace

#define EXPECT_TRUE(expr) Check(static_cast<bool>(expr), #expr, __FILE__, __LINE__)

int main()
{
    using namespace gptxn;
    using gpfocus::StableItemID;

    // 1. Встроенный самотест диспетчера транзакций F4.1
    {
        std::string report;
        const bool selfTestOk = RunTxnDispatcherSelfTest(&report);
        EXPECT_TRUE(selfTestOk);
        std::printf("[SelfTest] %s\n", report.c_str());
    }

    // 2. Детальная проверка Category A / B / C / D, защиты от двойного A, слота без CInventory::Update() и таймаута
    {
        TransactionDispatcher disp;

        // Category A: синхронное подтверждение в том же кадре (delta_frames = 0)
        const StableItemID favItem{ 1u, 10u, 100ull };
        TxnBeginResult rA = disp.BeginCategoryA("SP_fav", favItem, 100u, 1000u);
        EXPECT_TRUE(rA.accepted);
        EXPECT_TRUE(!rA.duplicate_blocked);
        EXPECT_TRUE(rA.state == TxnState::Confirmed);
        const TxnRecord* recA = disp.FindRecordById(rA.txn_id);
        EXPECT_TRUE(recA != nullptr);
        EXPECT_TRUE(recA->delta_frames == 0u);
        EXPECT_TRUE(!disp.IsItemLocked(favItem));

        // Category B: слот без CInventory::Update() + защита от двойного A + подтверждение на следующем кадре (+1)
        const StableItemID rifleItem{ 1u, 25u, 250ull };
        TxnBeginResult rB = disp.BeginCategoryB(
            "Action_Equip:to_slot",
            rifleItem,
            ExpectedEventMask::ItemToSlot,
            200u,
            2000u,
            500u,
            true);
        EXPECT_TRUE(rB.accepted);
        EXPECT_TRUE(rB.state == TxnState::Pending);
        EXPECT_TRUE(disp.IsItemLocked(rifleItem));
        EXPECT_TRUE(disp.IsObjectIdLockedInCategoryB(25u));

        // Три повторных нажатия A на том же кадре (200) и до прихода GEG_PLAYER_ITEM2SLOT блокируются
        for (int i = 0; i < 3; ++i)
        {
            TxnBeginResult dup = disp.BeginCategoryB(
                "Action_Equip:to_slot_dup",
                rifleItem,
                ExpectedEventMask::ItemToSlot,
                200u,
                2002u + static_cast<uint32_t>(i),
                500u,
                true);
            EXPECT_TRUE(!dup.accepted);
            EXPECT_TRUE(dup.duplicate_blocked);
        }
        EXPECT_TRUE(disp.GetStats().duplicate_a_blocked == 3u);

        // Попытка поставить тот же предмет в очередь C, пока он в Pending B, также блокируется
        TxnBeginResult blockedC = disp.BeginCategoryC(
            "ActivateSlot",
            rifleItem,
            ExpectedEventMask::None,
            200u,
            2006u);
        EXPECT_TRUE(!blockedC.accepted);
        EXPECT_TRUE(blockedC.duplicate_blocked);

        // На следующем кадре (201) приходит GEG_PLAYER_ITEM2SLOT (38)
        uint32_t confId = disp.OnInventoryEvent(38u, 25u, 201u, 2016u);
        EXPECT_TRUE(confId == rB.txn_id);
        EXPECT_TRUE(!disp.IsItemLocked(rifleItem));
        EXPECT_TRUE(!disp.IsObjectIdLockedInCategoryB(25u));

        const TxnRecord* recB = disp.FindRecordById(rB.txn_id);
        EXPECT_TRUE(recB != nullptr);
        EXPECT_TRUE(recB->state == TxnState::Confirmed);
        EXPECT_TRUE(recB->delta_frames == 1u);
        EXPECT_TRUE(recB->no_inv_update_slot);
        EXPECT_TRUE(disp.GetStats().slot_without_inv_update == 1u);
        EXPECT_TRUE(disp.GetStats().last_b_delta_frames == 1u);

        // Category B: GE_OWNERSHIP_TAKE (1) и GE_OWNERSHIP_REJECT (3)
        const StableItemID lootItem{ 1u, 33u, 330ull };
        TxnBeginResult rLoot = disp.BeginCategoryB(
            "TransferItem:take",
            lootItem,
            ExpectedEventMask::OwnershipTake | ExpectedEventMask::TradeBuy,
            300u,
            3000u);
        EXPECT_TRUE(rLoot.accepted);
        EXPECT_TRUE(disp.IsItemLocked(lootItem));
        // Чужой тип события (например, ItemToBelt = 39) не снимает блокировку
        EXPECT_TRUE(disp.OnInventoryEvent(39u, 33u, 301u, 3016u) == 0u);
        EXPECT_TRUE(disp.IsItemLocked(lootItem));
        // Приход GE_OWNERSHIP_TAKE (1) на кадре 301 подтверждает транзакцию (delta_frames = 1)
        EXPECT_TRUE(disp.OnInventoryEvent(1u, 33u, 301u, 3016u) == rLoot.txn_id);
        EXPECT_TRUE(!disp.IsItemLocked(lootItem));

        // Category B: отмена при net_Destroy объекта
        const StableItemID destroyedItem{ 1u, 44u, 440ull };
        TxnBeginResult rDestroy = disp.BeginCategoryB(
            "Disassemble",
            destroyedItem,
            ExpectedEventMask::OwnershipReject,
            400u,
            4000u);
        EXPECT_TRUE(rDestroy.accepted && disp.IsItemLocked(destroyedItem));
        EXPECT_TRUE(disp.OnObjectNetDestroy(44u, 401u, 4016u) == 1u);
        EXPECT_TRUE(!disp.IsItemLocked(destroyedItem));
        EXPECT_TRUE(disp.FindRecordById(rDestroy.txn_id)->state == TxnState::Cancelled);

        // Category C: успешное выполнение при совпадении StableItemID и отклонение при смене instance_gen
        const StableItemID medkitOrig{ 1u, 55u, 550ull };
        TxnBeginResult rC_ok = disp.BeginCategoryC("EatItem", medkitOrig, ExpectedEventMask::ItemEat, 500u, 5000u);
        EXPECT_TRUE(rC_ok.accepted);
        EXPECT_TRUE(disp.VerifyAndCommitCategoryC(rC_ok.txn_id, medkitOrig, 510u, 5160u));
        EXPECT_TRUE(disp.FindRecordById(rC_ok.txn_id)->state == TxnState::Confirmed);

        const StableItemID medkitStale{ 1u, 55u, 551ull };
        TxnBeginResult rC_stale = disp.BeginCategoryC("EatItem", medkitOrig, ExpectedEventMask::ItemEat, 520u, 5200u);
        EXPECT_TRUE(rC_stale.accepted);
        EXPECT_TRUE(!disp.VerifyAndCommitCategoryC(rC_stale.txn_id, medkitStale, 530u, 5360u));
        EXPECT_TRUE(disp.FindRecordById(rC_stale.txn_id)->state == TxnState::Cancelled);
        EXPECT_TRUE(disp.GetStats().stale_c_rejected == 1u);
    }

    std::printf("[GamepadTxn_test] passed=%d failed=%d\n", g_passed, g_failed);
    return (g_failed == 0) ? 0 : 1;
}
