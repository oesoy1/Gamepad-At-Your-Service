// D2.1: console unit test for src/xrEngine/GamepadMath. No game, no engine.
// Build: tools/tests/gamepad_math/build.ps1 -> _build/tests/gamepad_math/GamepadMath_test.exe
#include "../../../src/xrEngine/GamepadMath.h"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>

using namespace gpmath;

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

static bool Near(float a, float b, float eps) { return std::fabs(a - b) <= eps; }
static float Len(Vec2 v) { return std::sqrt(v.x * v.x + v.y * v.y); }
static bool Finite(Vec2 v) { return std::isfinite(v.x) && std::isfinite(v.y); }

// Exact copy of the C2.1/C3.1 formula (Actor_Movement.cpp:71-80, ActorInput.cpp:588-600) for regression.
static Vec2 ReferenceC21(float rawX, float rawY)
{
    const float DZ = 0.15f, SAT = 0.95f;
    rawX = rawX < -1.f ? -1.f : (rawX > 1.f ? 1.f : rawX);
    rawY = rawY < -1.f ? -1.f : (rawY > 1.f ? 1.f : rawY);
    const float rawMag = std::sqrt(rawX * rawX + rawY * rawY);
    if (rawMag <= DZ)
        return {0.f, 0.f};
    float normMag = (rawMag - DZ) / (SAT - DZ);
    normMag = normMag < 0.f ? 0.f : (normMag > 1.f ? 1.f : normMag);
    const float inv = 1.f / rawMag;
    return {rawX * inv * normMag, rawY * inv * normMag};
}

static StickConfig Sanitized(StickConfig c)
{
    SanitizeStick(c);
    return c;
}

struct CurveCase
{
    const char* name;
    CurveConfig c;
};

static CurveConfig MakeCurve(CurveType t, float g = 2.f, float s = 2.f, float ki = 0.5f, float ko = 0.25f)
{
    CurveConfig c;
    c.type = t;
    c.gamma = g;
    c.s_exponent = s;
    c.knee_in = ki;
    c.knee_out = ko;
    return c;
}

static const CurveCase kCurves[] = {
    {"linear", MakeCurve(CurveType::Linear)},
    {"power_g0.5", MakeCurve(CurveType::Power, 0.5f)},
    {"power_g1", MakeCurve(CurveType::Power, 1.0f)},
    {"power_g2", MakeCurve(CurveType::Power, 2.0f)},
    {"power_g4", MakeCurve(CurveType::Power, 4.0f)},
    {"scurve_a0.5", MakeCurve(CurveType::SCurve, 2.f, 0.5f)},
    {"scurve_a1", MakeCurve(CurveType::SCurve, 2.f, 1.0f)},
    {"scurve_a2", MakeCurve(CurveType::SCurve, 2.f, 2.0f)},
    {"scurve_a4", MakeCurve(CurveType::SCurve, 2.f, 4.0f)},
    {"twozone_0.5_0.25", MakeCurve(CurveType::TwoZone, 2.f, 2.f, 0.5f, 0.25f)},
    {"twozone_0.05_0.95", MakeCurve(CurveType::TwoZone, 2.f, 2.f, 0.05f, 0.95f)},
    {"twozone_0.95_0.05", MakeCurve(CurveType::TwoZone, 2.f, 2.f, 0.95f, 0.05f)},
};

static void TestDefaults()
{
    StickConfig d;
    CHECK(d.deadzone == 0.15f && d.saturation == 0.95f, "defaults must equal C2.1/C3.1 0.15/0.95");
    CHECK(d.shape == DeadzoneShape::Radial && d.curve.type == CurveType::Linear, "default radial+linear");
    StickConfig copy = d;
    CHECK(SanitizeStick(copy) == 0u, "default stick config must be valid");
    TriggerConfig t;
    CHECK(SanitizeTrigger(t) == 0u, "default trigger config must be valid");
}

static void TestRegressionC21()
{
    StickConfig d;
    float maxDiff = 0.f;
    for (int i = -100; i <= 100; ++i)
        for (int j = -100; j <= 100; ++j)
        {
            const float x = i / 100.f, y = j / 100.f;
            const Vec2 a = ProcessStick(d, x, y);
            const Vec2 b = ReferenceC21(x, y);
            maxDiff = std::fmax(maxDiff, std::fmax(std::fabs(a.x - b.x), std::fabs(a.y - b.y)));
        }
    std::printf("regression_c21_max_abs_diff=%.9g (grid 201x201)\n", maxDiff);
    CHECK(maxDiff <= 1e-6f, "defaults differ from C2.1 formula: %g", maxDiff);
}

static void TestBoundaries()
{
    const float eps = 1e-4f;
    for (const CurveCase& cc : kCurves)
    {
        StickConfig c;
        c.curve = cc.c;
        c = Sanitized(c);
        CHECK(Len(ProcessStick(c, 0.f, 0.f)) == 0.f, "%s: zero", cc.name);
        CHECK(Len(ProcessStick(c, c.deadzone, 0.f)) == 0.f, "%s: at deadzone", cc.name);
        CHECK(Len(ProcessStick(c, c.deadzone - eps, 0.f)) == 0.f, "%s: dz-eps", cc.name);
        const float justAbove = Len(ProcessStick(c, c.deadzone + eps, 0.f));
        CHECK(justAbove > 0.f && justAbove <= 0.02f, "%s: dz+eps continuity, got %g", cc.name, justAbove);
        CHECK(Near(Len(ProcessStick(c, 1.f, 0.f)), 1.f, 1e-6f), "%s: full", cc.name);
        CHECK(Near(Len(ProcessStick(c, c.saturation, 0.f)), 1.f, 1e-6f), "%s: at saturation", cc.name);
        const Vec2 diag = ProcessStick(c, 1.f, 1.f);
        CHECK(Near(Len(diag), 1.f, 1e-6f) && Near(diag.x, diag.y, 1e-6f), "%s: diagonal (1,1) len=%g", cc.name,
              Len(diag));
        const Vec2 neg = ProcessStick(c, -1.f, -1.f);
        CHECK(Near(Len(neg), 1.f, 1e-6f) && neg.x < 0.f && neg.y < 0.f, "%s: diagonal (-1,-1)", cc.name);
    }
}

static void TestCurveShape()
{
    const int N = 10000;
    for (const CurveCase& cc : kCurves)
    {
        CurveConfig c = cc.c;
        StickConfig s;
        s.curve = c;
        SanitizeStick(s);
        c = s.curve;
        CHECK(ApplyCurve(c, 0.f) == 0.f, "%s: f(0)=0", cc.name);
        CHECK(Near(ApplyCurve(c, 1.f), 1.f, 1e-6f), "%s: f(1)=1", cc.name);
        float prev = 0.f, maxStep = 0.f;
        int nonMono = 0;
        for (int i = 1; i <= N; ++i)
        {
            const float f = ApplyCurve(c, static_cast<float>(i) / N);
            if (f < prev)
                ++nonMono;
            maxStep = std::fmax(maxStep, f - prev);
            prev = f;
        }
        std::printf("curve %-18s monotonic_violations=%d max_step(dt=1e-4)=%.6f\n", cc.name, nonMono, maxStep);
        CHECK(nonMono == 0, "%s: non-monotonic (%d)", cc.name, nonMono);
        CHECK(maxStep <= 0.02f, "%s: discontinuity, max step %g", cc.name, maxStep);
    }
    // stick magnitude monotonic through the whole pipeline, including beyond 1 (diagonal)
    for (const CurveCase& cc : kCurves)
    {
        StickConfig s;
        s.curve = cc.c;
        SanitizeStick(s);
        float prev = 0.f;
        int bad = 0;
        for (int i = 0; i <= 1500; ++i)
        {
            const float m = i / 1000.f;
            const float l = Len(ProcessStick(s, m * 0.70710678f, m * 0.70710678f));
            if (l + 1e-7f < prev)
                ++bad;
            prev = l;
        }
        CHECK(bad == 0, "%s: pipeline magnitude non-monotonic (%d)", cc.name, bad);
    }
}

static void PrintTable()
{
    std::printf("TABLE t:");
    for (int i = 0; i <= 10; ++i)
        std::printf(" %.2f", i / 10.f);
    std::printf("\n");
    for (const CurveCase& cc : kCurves)
    {
        StickConfig s;
        s.curve = cc.c;
        SanitizeStick(s);
        std::printf("TABLE %-18s", cc.name);
        for (int i = 0; i <= 10; ++i)
            std::printf(" %.4f", ApplyCurve(s.curve, i / 10.f));
        std::printf("\n");
    }
}

static void TestDirection()
{
    StickConfig d;
    float maxErrDeg = 0.f;
    for (int k = 0; k < 24; ++k)
    {
        const float a = k * 15.f * 3.14159265f / 180.f;
        const float mags[] = {0.25f, 0.5f, 0.75f, 1.0f};
        for (float m : mags)
        {
            const float x = m * std::cos(a), y = m * std::sin(a);
            const Vec2 o = ProcessStick(d, x, y);
            // atan2(cross, dot): acos near 1 loses precision in float (acos(1-6e-8) = 0.02 deg)
            const double cr = (double)o.x * y - (double)o.y * x;
            const double dt = (double)o.x * x + (double)o.y * y;
            const float err = static_cast<float>(std::fabs(std::atan2(cr, dt)) * 180.0 / 3.14159265358979);
            maxErrDeg = std::fmax(maxErrDeg, err);
        }
    }
    std::printf("radial_direction_max_err_deg=%.6f (24 dirs x 4 mags)\n", maxErrDeg);
    CHECK(maxErrDeg <= 0.01f, "radial changes direction by %g deg", maxErrDeg);
}

static void TestAxialAndInvert()
{
    StickConfig a;
    a.shape = DeadzoneShape::Axial;
    const Vec2 o = ProcessStick(a, 0.5f, 0.1f);
    CHECK(o.y == 0.f && Near(o.x, (0.5f - 0.15f) / 0.8f, 1e-6f), "axial snap: %g %g", o.x, o.y);
    const Vec2 c = ProcessStick(a, 1.f, 1.f);
    CHECK(Near(Len(c), 1.f, 1e-6f), "axial corner clipped to 1: %g", Len(c));

    StickConfig inv;
    inv.invert_x = true;
    inv.invert_y = true;
    const Vec2 p = ProcessStick(StickConfig{}, 0.6f, -0.4f);
    const Vec2 q = ProcessStick(inv, 0.6f, -0.4f);
    CHECK(q.x == -p.x && q.y == -p.y, "inversion");
}

static void TestNormalize()
{
    CHECK(NormalizeStickAxis(32767) == 1.f, "stick +max");
    CHECK(NormalizeStickAxis(-32768) == -1.f, "stick -32768 clamps to -1");
    CHECK(NormalizeStickAxis(0) == 0.f, "stick zero");
    CHECK(NormalizeTriggerAxis(32767) == 1.f, "trigger max");
    CHECK(NormalizeTriggerAxis(-5) == 0.f, "trigger negative clamps to 0");
}

static void TestBadInputs()
{
    const float nan = std::numeric_limits<float>::quiet_NaN();
    const float inf = std::numeric_limits<float>::infinity();
    StickConfig d;
    CHECK(Len(ProcessStick(d, nan, 0.5f)) <= 1.f && Finite(ProcessStick(d, nan, 0.5f)), "nan x");
    CHECK(Len(ProcessStick(d, nan, nan)) == 0.f, "nan both -> 0");
    CHECK(Finite(ProcessStick(d, inf, -inf)) && Len(ProcessStick(d, inf, -inf)) == 0.f, "inf -> 0");
    CHECK(Near(Len(ProcessStick(d, 5.f, 0.f)), 1.f, 1e-6f), "out of range input clamps");
    TriggerConfig t;
    CHECK(ProcessTrigger(t, nan) == 0.f && ProcessTrigger(t, inf) == 1.f && ProcessTrigger(t, -inf) == 0.f,
          "trigger nan/inf");
}

static void TestSanitizer()
{
    const float nan = std::numeric_limits<float>::quiet_NaN();
    const float inf = std::numeric_limits<float>::infinity();
    struct Bad
    {
        const char* name;
        float dz, sat, g, s, ki, ko;
        std::uint8_t shape, type;
    };
    const Bad bads[] = {
        {"nan_all", nan, nan, nan, nan, nan, nan, 0, 3},
        {"inf_all", inf, inf, inf, inf, inf, inf, 0, 2},
        {"neg_inf", -inf, -inf, -inf, -inf, -inf, -inf, 1, 1},
        {"minus5", -5.f, -5.f, -5.f, -5.f, -5.f, -5.f, 0, 1},
        {"huge", 100.f, 100.f, 100.f, 100.f, 100.f, 100.f, 0, 2},
        {"dz_eq_sat", 0.5f, 0.5f, 2.f, 2.f, 0.5f, 0.25f, 0, 0},
        {"dz_gt_sat", 0.8f, 0.2f, 2.f, 2.f, 0.5f, 0.25f, 0, 0},
        {"zero_knees_gamma", 0.1f, 0.9f, 0.f, 0.f, 0.f, 1.f, 0, 3},
        {"bad_enums", 0.15f, 0.95f, 2.f, 2.f, 0.5f, 0.25f, 200, 250},
    };
    for (const Bad& b : bads)
    {
        StickConfig c;
        c.deadzone = b.dz;
        c.saturation = b.sat;
        c.curve.gamma = b.g;
        c.curve.s_exponent = b.s;
        c.curve.knee_in = b.ki;
        c.curve.knee_out = b.ko;
        c.shape = static_cast<DeadzoneShape>(b.shape);
        c.curve.type = static_cast<CurveType>(b.type);
        const std::uint32_t flags = SanitizeStick(c);
        const bool inRange = c.deadzone >= 0.f && c.deadzone <= limits::kDeadzoneMax &&
                             c.saturation - c.deadzone >= limits::kMinSpan - 1e-7f && c.saturation <= 1.f &&
                             c.curve.gamma >= limits::kExpMin && c.curve.gamma <= limits::kExpMax &&
                             c.curve.s_exponent >= limits::kExpMin && c.curve.s_exponent <= limits::kExpMax &&
                             c.curve.knee_in >= limits::kKneeMin && c.curve.knee_in <= limits::kKneeMax &&
                             c.curve.knee_out >= limits::kKneeMin && c.curve.knee_out <= limits::kKneeMax &&
                             static_cast<std::uint8_t>(c.shape) <= 1 && static_cast<std::uint8_t>(c.curve.type) <= 3;
        CHECK(flags != 0u, "%s: sanitizer must report a fix", b.name);
        CHECK(inRange, "%s: sanitized values out of range", b.name);
        std::uint32_t again = SanitizeStick(c);
        CHECK(again == 0u, "%s: sanitizer not idempotent (0x%x)", b.name, again);
        int bad = 0;
        for (int i = -20; i <= 20; ++i)
            for (int j = -20; j <= 20; ++j)
            {
                const Vec2 o = ProcessStick(c, i / 20.f * 1.2f, j / 20.f * 1.2f);
                if (!Finite(o) || Len(o) > 1.f + 1e-6f)
                    ++bad;
            }
        std::printf("sanitize %-18s flags=0x%03x dz=%.3f sat=%.3f g=%.2f s=%.2f ki=%.2f ko=%.2f bad_outputs=%d\n",
                    b.name, flags, c.deadzone, c.saturation, c.curve.gamma, c.curve.s_exponent, c.curve.knee_in,
                    c.curve.knee_out, bad);
        CHECK(bad == 0, "%s: non-finite or >1 outputs: %d", b.name, bad);
    }

    // trigger
    TriggerConfig t;
    t.press = 0.2f;
    t.release = 0.6f; // inverted
    t.deadzone = nan;
    t.saturation = -1.f;
    const std::uint32_t tf = SanitizeTrigger(t);
    CHECK(tf != 0u && t.release <= t.press - limits::kTriggerMinGap + 1e-7f && t.saturation > t.deadzone,
          "trigger sanitize: release=%g press=%g", t.release, t.press);
}

// Random bit patterns as config fields: nothing may produce NaN/Inf or |out|>1.
static void TestFuzz()
{
    std::uint32_t seed = 0xC0FFEEu;
    auto next = [&]() {
        seed = seed * 1664525u + 1013904223u;
        return seed;
    };
    auto rndFloatBits = [&]() {
        std::uint32_t u = next();
        float f;
        std::memcpy(&f, &u, sizeof f);
        return f;
    };
    int bad = 0;
    const int cases = 20000;
    for (int i = 0; i < cases; ++i)
    {
        StickConfig c;
        c.deadzone = rndFloatBits();
        c.saturation = (i & 1) ? rndFloatBits() : static_cast<float>(next() % 2000) / 1000.f - 0.5f;
        c.curve.gamma = rndFloatBits();
        c.curve.s_exponent = rndFloatBits();
        c.curve.knee_in = rndFloatBits();
        c.curve.knee_out = rndFloatBits();
        c.shape = static_cast<DeadzoneShape>(next() & 0xFF);
        c.curve.type = static_cast<CurveType>(next() & 0xFF);
        SanitizeStick(c);
        for (int k = 0; k < 8; ++k)
        {
            const float x = static_cast<float>(static_cast<int>(next() % 3001) - 1500) / 1000.f;
            const float y = static_cast<float>(static_cast<int>(next() % 3001) - 1500) / 1000.f;
            const Vec2 o = ProcessStick(c, x, y);
            if (!Finite(o) || Len(o) > 1.f + 1e-5f)
            {
                if (bad < 5)
                    std::printf("fuzz_bad stick shape=%u type=%u dz=%g sat=%g g=%g s=%g ki=%g ko=%g in=(%g,%g) out=(%g,%g)\n",
                                (unsigned)c.shape, (unsigned)c.curve.type, c.deadzone, c.saturation, c.curve.gamma,
                                c.curve.s_exponent, c.curve.knee_in, c.curve.knee_out, x, y, o.x, o.y);
                ++bad;
            }
        }
        TriggerConfig t;
        t.deadzone = rndFloatBits();
        t.saturation = rndFloatBits();
        t.press = rndFloatBits();
        t.release = rndFloatBits();
        SanitizeTrigger(t);
        const float v = ProcessTrigger(t, static_cast<float>(next() % 1001) / 1000.f);
        if (!std::isfinite(v) || v < 0.f || v > 1.f || !(t.release < t.press))
        {
            if (bad < 5)
                std::printf("fuzz_bad trigger dz=%g sat=%g press=%g rel=%g v=%g\n", t.deadzone, t.saturation, t.press,
                            t.release, v);
            ++bad;
        }
    }
    std::printf("fuzz cases=%d bad=%d\n", cases, bad);
    CHECK(bad == 0, "fuzz: %d bad outputs", bad);
}

static void TestTrigger()
{
    TriggerConfig t;
    CHECK(ProcessTrigger(t, 0.10f) == 0.f, "trigger below dz");
    CHECK(ProcessTrigger(t, 0.12f) == 0.f, "trigger at dz");
    CHECK(ProcessTrigger(t, 0.96f) == 1.f, "trigger saturation");
    CHECK(Near(ProcessTrigger(t, 0.535f), 0.5f, 1e-5f), "trigger mid");
    // hysteresis: press 0.35, release 0.25
    const float seq[] = {0.0f, 0.34f, 0.36f, 0.30f, 0.26f, 0.25f, 0.30f, 0.34f, 0.35f, 1.0f, 0.0f};
    const bool expect[] = {false, false, true, true, true, false, false, false, true, true, false};
    bool st = false;
    int mism = 0;
    for (int i = 0; i < 11; ++i)
    {
        st = UpdateTriggerButton(t, st, seq[i]);
        if (st != expect[i])
            ++mism;
    }
    CHECK(mism == 0, "trigger hysteresis sequence mismatches: %d", mism);
    // jitter around the press threshold must not chatter
    st = false;
    int toggles = 0;
    for (int i = 0; i < 1000; ++i)
    {
        const float v = 0.35f + ((i & 1) ? 0.04f : -0.04f); // 0.31 .. 0.39
        const bool n = UpdateTriggerButton(t, st, v);
        if (n != st)
            ++toggles;
        st = n;
    }
    CHECK(toggles == 1, "trigger chatter: %d toggles under +-0.04 jitter", toggles);
}

static const char* g_calibProfilePath = "_build\\tests\\gamepad_math\\tmp\\profile.ltx";

void TestCalibrationProfileD22()
{
    SetCalibrationProfilePath(g_calibProfilePath);
    SetCalibrationLogCallback([](const char* msg) { std::printf("%s\n", msg); });
    CHECK(RunCalibrationSelfTest(), "D2.2 RunCalibrationSelfTest");
    CHECK(LoadCalibrationProfile(), "D2.2 LoadCalibrationProfile initial");
    CHECK(SaveCalibrationProfile(), "D2.2 SaveCalibrationProfile");
    CalibrationLoadReport rep{};
    CHECK(LoadCalibrationProfile(&rep) && rep.file_existed && rep.loaded_ok && rep.profile_flags == 0 && rep.parse_warnings == 0,
          "D2.2 LoadCalibrationProfile clean reload");

    // K6b: test defaults and edge turn acceleration / ADS sensitivity scale
    CalibrationProfile defP{};
    CHECK(Near(defP.ads_sens_mult, 0.70f, 1e-5f) && Near(defP.turn_accel, 0.30f, 1e-5f) && defP.disable_aa_on_scope == true,
          "K6b default CalibrationProfile ads_sens_mult=0.70 turn_accel=0.30 disable_aa_on_scope=true");
    float ramp = 0.0f;
    CHECK(Near(StepTurnAcceleration(ramp, 0.85f, 0.40f, 0.1f), 1.0f, 1e-5f) && ramp == 0.0f, "K6b below 0.90 no accel");
    for (int i = 0; i < 20; ++i)
        StepTurnAcceleration(ramp, 1.0f, 0.40f, 0.05f);
    CHECK(Near(ramp, 1.0f, 1e-5f), "K6b ramp reaches 1.0 at full deflection");
    CHECK(Near(ComputeLookSpeedScale(0.75f, true, 0.40f, ramp), 0.75f * 1.40f, 1e-5f), "K6b combined ADS + turn accel scale");
    StepTurnAcceleration(ramp, 0.20f, 0.40f, 0.20f);
    CHECK(Near(ramp, 0.0f, 1e-5f), "K6b ramp decays to 0 when leaving edge");
}

int main(int argc, char** argv)
{
    if (argc > 1 && argv[1] && argv[1][0])
        g_calibProfilePath = argv[1];
    TestDefaults();
    TestRegressionC21();
    TestBoundaries();
    TestCurveShape();
    PrintTable();
    TestDirection();
    TestAxialAndInvert();
    TestNormalize();
    TestBadInputs();
    TestSanitizer();
    TestFuzz();
    TestTrigger();
    TestCalibrationProfileD22();
    std::printf("RESULT pass=%d fail=%d\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
