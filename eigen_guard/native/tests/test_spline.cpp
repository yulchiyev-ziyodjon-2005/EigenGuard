/// SplineProcessor Unit Testlari
/// sin(x), chiziqli funksiya, va boshqa test holatlarida
/// kubik splayn algoritmining to'g'riligini tekshiradi.
///
/// Ishga tushirish:
///   cd native
///   cmake -S . -B build -DBUILD_TESTS=ON
///   cmake --build build --config Release
///   .\build\Release\eigenguard_test.exe

#include "spline_processor.h"
#include <iostream>
#include <cmath>
#include <vector>
#include <string>
#include <iomanip>

// Oddiy test framework (Google Test o'rniga — dastlabki bosqich uchun)
static int test_count = 0;
static int pass_count = 0;
static int fail_count = 0;

#define ASSERT_TRUE(expr, msg) do { \
    test_count++; \
    if (expr) { \
        pass_count++; \
        std::cout << "  [PASS] " << msg << std::endl; \
    } else { \
        fail_count++; \
        std::cerr << "  [FAIL] " << msg << " (line " << __LINE__ << ")" << std::endl; \
    } \
} while(0)

#define ASSERT_NEAR(actual, expected, tolerance, msg) do { \
    test_count++; \
    double _diff = std::abs((actual) - (expected)); \
    if (_diff <= (tolerance)) { \
        pass_count++; \
        std::cout << "  [PASS] " << msg << " (diff=" << _diff << ")" << std::endl; \
    } else { \
        fail_count++; \
        std::cerr << "  [FAIL] " << msg << " | expected=" << (expected) \
                  << " actual=" << (actual) << " diff=" << _diff \
                  << " (line " << __LINE__ << ")" << std::endl; \
    } \
} while(0)

// ============================================================
// Test 1: Chiziqli funksiya f(x) = 2x + 3
// Splayn chiziqli funksiyani ANIQ takrorlashi kerak (xatolik ≈ 0)
// ============================================================
void test_linear_function() {
    std::cout << "\n=== Test 1: Chiziqli funksiya f(x) = 2x + 3 ===" << std::endl;

    eigenguard::SplineProcessor spline;

    double t[] = {0.0, 1.0, 2.0, 3.0, 4.0, 5.0};
    double y[] = {3.0, 5.0, 7.0, 9.0, 11.0, 13.0};  // y = 2x + 3
    size_t n = 6;

    ASSERT_TRUE(spline.setDataPoints(t, y, n), "setDataPoints muvaffaqiyatli");
    ASSERT_TRUE(spline.computeCoefficients(), "computeCoefficients muvaffaqiyatli");
    ASSERT_TRUE(spline.isComputed(), "isComputed = true");

    // Oraliq nuqtalarda tekshirish
    ASSERT_NEAR(spline.evaluate(0.5), 4.0, 1e-10, "f(0.5) = 4.0");
    ASSERT_NEAR(spline.evaluate(1.5), 6.0, 1e-10, "f(1.5) = 6.0");
    ASSERT_NEAR(spline.evaluate(2.7), 8.4, 1e-10, "f(2.7) = 8.4");
    ASSERT_NEAR(spline.evaluate(4.3), 11.6, 1e-10, "f(4.3) = 11.6");

    // Hosila tekshirish: f'(x) = 2.0
    ASSERT_NEAR(spline.evaluateDerivative(1.0), 2.0, 1e-10, "f'(1.0) = 2.0");
    ASSERT_NEAR(spline.evaluateDerivative(3.5), 2.0, 1e-10, "f'(3.5) = 2.0");
}

// ============================================================
// Test 2: sin(x) funksiyasi
// Splayn sin(x) ni yaxshi approksimatsiya qilishi kerak (xatolik < 0.01)
// ============================================================
void test_sine_function() {
    std::cout << "\n=== Test 2: sin(x) funksiyasi ===" << std::endl;

    eigenguard::SplineProcessor spline;

    // 0 dan 2*pi gacha 11 nuqta
    const int N = 11;
    double t[N], y[N];
    double step = 2.0 * M_PI / (N - 1);

    for (int i = 0; i < N; ++i) {
        t[i] = i * step;
        y[i] = std::sin(t[i]);
    }

    ASSERT_TRUE(spline.setDataPoints(t, y, N), "setDataPoints (sin) muvaffaqiyatli");
    ASSERT_TRUE(spline.computeCoefficients(), "computeCoefficients (sin) muvaffaqiyatli");

    // Oraliq nuqtalarda tekshirish
    double test_points[] = {0.3, 0.7, 1.0, 1.5, 2.0, 2.5, 3.14, 4.0, 5.0, 5.5};
    for (double x : test_points) {
        double expected = std::sin(x);
        double actual = spline.evaluate(x);
        ASSERT_NEAR(actual, expected, 0.01,
            "sin(" + std::to_string(x).substr(0, 4) + ") approksimatsiya");
    }
}

// ============================================================
// Test 3: Kvadrat funksiya f(x) = x^2
// Kubik splayn kvadratik funksiyani ANIQ mos kelishi kerak
// ============================================================
void test_quadratic_function() {
    std::cout << "\n=== Test 3: Kvadrat funksiya f(x) = x^2 ===" << std::endl;

    eigenguard::SplineProcessor spline;

    double t[] = {0.0, 1.0, 2.0, 3.0, 4.0};
    double y[] = {0.0, 1.0, 4.0, 9.0, 16.0};  // y = x^2
    size_t n = 5;

    ASSERT_TRUE(spline.setDataPoints(t, y, n), "setDataPoints (x^2) muvaffaqiyatli");
    ASSERT_TRUE(spline.computeCoefficients(), "computeCoefficients (x^2) muvaffaqiyatli");

    ASSERT_NEAR(spline.evaluate(0.5), 0.25, 0.05, "f(0.5) = 0.25");
    ASSERT_NEAR(spline.evaluate(1.5), 2.25, 0.05, "f(1.5) = 2.25");
    ASSERT_NEAR(spline.evaluate(2.5), 6.25, 0.05, "f(2.5) = 6.25");
    ASSERT_NEAR(spline.evaluate(3.5), 12.25, 0.05, "f(3.5) = 12.25");
}

// ============================================================
// Test 4: Chegaraviy holatlar
// ============================================================
void test_edge_cases() {
    std::cout << "\n=== Test 4: Chegaraviy holatlar ===" << std::endl;

    eigenguard::SplineProcessor spline;

    // Kam nuqtalar (< 3) rad qilinishi kerak
    double t2[] = {0.0, 1.0};
    double y2[] = {0.0, 1.0};
    ASSERT_TRUE(!spline.setDataPoints(t2, y2, 2), "2 nuqta rad qilinadi");

    // NULL pointer rad qilinishi kerak
    ASSERT_TRUE(!spline.setDataPoints(nullptr, y2, 3), "NULL t rad qilinadi");
    ASSERT_TRUE(!spline.setDataPoints(t2, nullptr, 3), "NULL y rad qilinadi");

    // Noto'g'ri tartib rad qilinishi kerak
    double t_bad[] = {0.0, 2.0, 1.0};
    double y_bad[] = {0.0, 1.0, 2.0};
    ASSERT_TRUE(!spline.setDataPoints(t_bad, y_bad, 3), "Noto'g'ri tartib rad qilinadi");

    // 3 nuqta (minimal) qabul qilinishi kerak
    double t3[] = {0.0, 1.0, 2.0};
    double y3[] = {0.0, 1.0, 0.0};
    ASSERT_TRUE(spline.setDataPoints(t3, y3, 3), "3 nuqta qabul qilinadi");
    ASSERT_TRUE(spline.computeCoefficients(), "3 nuqta uchun hisoblash muvaffaqiyatli");
}

// ============================================================
// Test 5: Koeffitsiyentlar tekshirish
// ============================================================
void test_coefficients() {
    std::cout << "\n=== Test 5: Koeffitsiyentlar tekshirish ===" << std::endl;

    eigenguard::SplineProcessor spline;

    double t[] = {0.0, 1.0, 2.0, 3.0};
    double y[] = {0.0, 1.0, 0.0, 1.0};
    size_t n = 4;

    ASSERT_TRUE(spline.setDataPoints(t, y, n), "setDataPoints muvaffaqiyatli");
    ASSERT_TRUE(spline.computeCoefficients(), "computeCoefficients muvaffaqiyatli");

    const auto& coeffs = spline.getCoefficients();
    ASSERT_TRUE(coeffs.n == 3, "3 ta oraliq (n=3)");
    ASSERT_TRUE(coeffs.a.size() == 4, "4 ta a koeffitsiyent");
    ASSERT_TRUE(coeffs.b.size() == 3, "3 ta b koeffitsiyent");
    ASSERT_TRUE(coeffs.c.size() == 4, "4 ta c koeffitsiyent (c_0..c_n)");
    ASSERT_TRUE(coeffs.d.size() == 3, "3 ta d koeffitsiyent");

    // Natural splayn sharti: c_0 = 0 va c_n = 0
    ASSERT_NEAR(coeffs.c[0], 0.0, 1e-10, "c_0 = 0 (natural splayn)");
    ASSERT_NEAR(coeffs.c[3], 0.0, 1e-10, "c_n = 0 (natural splayn)");

    // a_i = y_i (splayn tugun nuqtalaridan o'tishi kerak)
    ASSERT_NEAR(coeffs.a[0], 0.0, 1e-10, "a_0 = y_0 = 0");
    ASSERT_NEAR(coeffs.a[1], 1.0, 1e-10, "a_1 = y_1 = 1");
    ASSERT_NEAR(coeffs.a[2], 0.0, 1e-10, "a_2 = y_2 = 0");
    ASSERT_NEAR(coeffs.a[3], 1.0, 1e-10, "a_3 = y_3 = 1");

    // Splayn tugun nuqtalaridan o'tishi
    ASSERT_NEAR(spline.evaluate(0.0), 0.0, 1e-10, "S(0) = 0");
    ASSERT_NEAR(spline.evaluate(1.0), 1.0, 1e-10, "S(1) = 1");
    ASSERT_NEAR(spline.evaluate(2.0), 0.0, 1e-10, "S(2) = 0");
    ASSERT_NEAR(spline.evaluate(3.0), 1.0, 1e-10, "S(3) = 1");
}

// ============================================================
// Test 6: Tebranish signali simulyatsiyasi (Real-world use case)
// ============================================================
void test_vibration_signal() {
    std::cout << "\n=== Test 6: Tebranish signali (Real-world) ===" << std::endl;

    eigenguard::SplineProcessor spline;

    // 0-1 soniya, 5 Hz tebranish, 20 nuqta (20 FPS simulyatsiya)
    const int N = 21;
    double t[N], y[N];
    double freq = 5.0;  // Hz

    for (int i = 0; i < N; ++i) {
        t[i] = i * 0.05;  // 20 FPS = 0.05s qadam
        y[i] = 2.0 * std::sin(2.0 * M_PI * freq * t[i]);
    }

    ASSERT_TRUE(spline.setDataPoints(t, y, N), "Tebranish ma'lumotlari qabul qilindi");
    ASSERT_TRUE(spline.computeCoefficients(), "Tebranish splayni hisoblandi");

    // Oraliq nuqtalarda tekshirish (kadrlar orasida)
    double test_t = 0.025;  // Kadrlar orasidagi nuqta
    double expected = 2.0 * std::sin(2.0 * M_PI * freq * test_t);
    double actual = spline.evaluate(test_t);
    ASSERT_NEAR(actual, expected, 0.2, "Tebranish oraliq nuqtada approksimatsiya");

    std::cout << "  [INFO] Signal: 5 Hz, Amplitude: 2.0" << std::endl;
    std::cout << "  [INFO] t=" << test_t << " expected=" << expected
              << " actual=" << actual << std::endl;
}

// ============================================================
// Main
// ============================================================
int main() {
    std::cout << "============================================" << std::endl;
    std::cout << "  EigenGuard SplineProcessor Unit Tests     " << std::endl;
    std::cout << "  Kubik Splayn - Haydash usuli (6.3-§)     " << std::endl;
    std::cout << "============================================" << std::endl;

    test_linear_function();
    test_sine_function();
    test_quadratic_function();
    test_edge_cases();
    test_coefficients();
    test_vibration_signal();

    std::cout << "\n============================================" << std::endl;
    std::cout << "  NATIJALAR: " << pass_count << "/" << test_count << " PASS, "
              << fail_count << " FAIL" << std::endl;
    std::cout << "============================================\n" << std::endl;

    return fail_count > 0 ? 1 : 0;
}
