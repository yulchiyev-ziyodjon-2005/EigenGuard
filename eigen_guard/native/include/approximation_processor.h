#pragma once
#include <cstdint>

namespace eigenguard {

/// Trend yo'nalishi
enum class TrendDirection : int32_t {
    FALLING = -1,   // KAMAYMOQDA
    STABLE = 0,     // BARQAROR
    RISING = 1      // OSHMOQDA
};

/// Bashorat natijasi
struct PredictionResult {
    double a;                 // y = a + b*t + c*t^2
    double b;
    double c;
    double hours_to_critical; // Kritik nuqtaga qolgan soat
    TrendDirection direction; // Trend yo'nalishi
};

class ApproximationProcessor {
public:
    ApproximationProcessor();

    /// §6.4 Eng kichik kvadratlar usuli (Parabolik fit)
    /// t[] — vaqt massivi, y[] — amplituda/xavf massivi
    /// count — nuqtalar soni, y_limit — kritik chegara
    PredictionResult predict(const double* t, const double* y,
                             int count, double y_limit);

private:
    // Gauss eliminatsiya yordamida 3x3 tizimni yechish
    bool solveSystem(double A[3][4], double result[3]);
};

} // namespace eigenguard
