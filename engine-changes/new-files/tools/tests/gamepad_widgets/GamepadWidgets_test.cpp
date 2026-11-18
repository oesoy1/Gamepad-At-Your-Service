#include <cassert>
#include <cstdio>
#include <iostream>

#include "GamepadWidgets.h"

int main()
{
    std::printf("================================================================================\n");
    std::printf("F2.1 Base Widgets & Showcase Unit Test Suite (GamepadWidgets_test)\n");
    std::printf("================================================================================\n");

    const gpfocus::SelfTestSummary summary = gpwidgets::RunWidgetsSelfTest();
    std::printf("%s\n\n", summary.report.c_str());

    gpwidgets::WidgetShowcaseController ctrl;
    ctrl.InitializeDefaultShowcase(1000u);
    std::printf("%s\n", ctrl.FormatShowcaseDump().c_str());

    if (summary.failed_cases > 0 || summary.passed_cases != summary.total_cases)
    {
        std::fprintf(stderr, "ERROR: %u test case(s) failed!\n", summary.failed_cases);
        return 1;
    }

    std::printf("[PASS] All %u F2.1 widget test cases succeeded (inventory_mutations=0).\n", summary.passed_cases);
    return 0;
}
