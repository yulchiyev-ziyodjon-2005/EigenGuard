#include "approximation_processor.h"
#include <cmath>
#include <cstring>
#include <algorithm>

namespace eigenguard {

ApproximationProcessor::ApproximationProcessor() {}

bool ApproximationProcessor::solveSystem(double A[3][4], double result[3]) {
    // Gauss eliminatsiyasi — 3x3 kengaytirilgan matritsa
    for (int col = 0; col < 3; ++col) {
        // Pivotni topish
        int maxRow = col;
        for (int row = col + 1; row < 3; ++row) {
            if (std::fabs(A[row][col]) > std::fabs(A[maxRow][col])) {
                maxRow = row;
            }
        }
        // Swap
        if (maxRow != col) {
            for (int j = 0; j < 4; ++j) {
                double tmp = A[col][j];
                A[col][j] = A[maxRow][j];
                A[maxRow][j] = tmp;
            }
        }
        // Pivot nolga teng bo'lsa, yechim yo'q
        if (std::fabs(A[col][col]) < 1e-12) return false;

        // Eliminatsiya
        for (int row = col + 1; row < 3; ++row) {
            double factor = A[row][col] / A[col][col];
            for (int j = col; j < 4; ++j) {
                A[row][j] -= factor * A[col][j];
            }
        }
    }

    // Orqaga yechish (Back substitution)
    for (int i = 2; i >= 0; --i) {
        result[i] = A[i][3];
        for (int j = i + 1; j < 3; ++j) {
            result[i] -= A[i][j] * result[j];
        }
        result[i] /= A[i][i];
    }
    return true;
}

PredictionResult ApproximationProcessor::predict(
    const double* t, const double* y, int count, double y_limit) {

    PredictionResult result;
    result.a = 0.0;
    result.b = 0.0;
    result.c = 0.0;
    result.hours_to_critical = -1.0;
    result.direction = TrendDirection::STABLE;

    if (count < 3 || !t || !y) {
        return result;
    }

    // §6.4 Normal tenglamalar tizimi: y = a + b*t + c*t^2
    // Eng kichik kvadratlar uchun 3x3 normal tenglamalar
    double S[5] = {0};  // S0=sum(t^0), S1=sum(t^1), ..., S4=sum(t^4)
    double T[3] = {0};  // T0=sum(y), T1=sum(t*y), T2=sum(t^2*y)

    for (int i = 0; i < count; ++i) {
        double ti = t[i];
        double ti2 = ti * ti;
        double yi = y[i];

        S[0] += 1.0;
        S[1] += ti;
        S[2] += ti2;
        S[3] += ti2 * ti;
        S[4] += ti2 * ti2;

        T[0] += yi;
        T[1] += ti * yi;
        T[2] += ti2 * yi;
    }

    // Normal tenglamalar matritsasi:
    // [S0 S1 S2 | T0]
    // [S1 S2 S3 | T1]
    // [S2 S3 S4 | T2]
    double A[3][4] = {
        {S[0], S[1], S[2], T[0]},
        {S[1], S[2], S[3], T[1]},
        {S[2], S[3], S[4], T[2]}
    };

    double coeffs[3];
    if (!solveSystem(A, coeffs)) {
        return result; // Degeneratsiya; bashorat imkonsiz
    }

    result.a = coeffs[0];
    result.b = coeffs[1];
    result.c = coeffs[2];

    // Trend yo'nalishini aniqlash (ohirgi nuqtadagi hosila)
    double t_last = t[count - 1];
    double derivative = result.b + 2.0 * result.c * t_last;

    if (derivative > 0.05) {
        result.direction = TrendDirection::RISING;
    } else if (derivative < -0.05) {
        result.direction = TrendDirection::FALLING;
    } else {
        result.direction = TrendDirection::STABLE;
    }

    // Kritik nuqtaga yetish vaqtini hisoblash
    // y_limit = a + b*t + c*t^2 tenglamasini t uchun yechamiz
    if (std::fabs(result.c) > 1e-12) {
        // Kvadrat tenglama: c*t^2 + b*t + (a - y_limit) = 0
        double disc = result.b * result.b - 4.0 * result.c * (result.a - y_limit);
        if (disc >= 0) {
            double t1 = (-result.b + std::sqrt(disc)) / (2.0 * result.c);
            double t2 = (-result.b - std::sqrt(disc)) / (2.0 * result.c);
            // Kelajakdagi ijobiy vaqtni tanlaymiz
            double future1 = t1 - t_last;
            double future2 = t2 - t_last;
            if (future1 > 0 && future2 > 0) {
                result.hours_to_critical = std::min(future1, future2);
            } else if (future1 > 0) {
                result.hours_to_critical = future1;
            } else if (future2 > 0) {
                result.hours_to_critical = future2;
            }
        }
    } else if (std::fabs(result.b) > 1e-12) {
        // Chiziqli: b*t + (a - y_limit) = 0
        double t_crit = (y_limit - result.a) / result.b;
        double future = t_crit - t_last;
        if (future > 0) {
            result.hours_to_critical = future;
        }
    }

    return result;
}

} // namespace eigenguard
