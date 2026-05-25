/// SplineProcessor implementatsiyasi.
/// "Sonli usullar" kitobi, 6.3-paragraf, 113-bet asosida.
/// Haydash usuli (Progonka / Thomas algoritmi) bilan tridagonal sistema yechiladi.
///
/// Kubik splayn formulasi:
///   S_i(x) = a_i + b_i*(x - x_i) + c_i*(x - x_i)^2 + d_i*(x - x_i)^3
///
/// Natural splayn sharti:
///   S''(x_0) = 0,  S''(x_n) = 0  =>  c_0 = 0, c_n = 0

#include "spline_processor.h"
#include <cmath>
#include <algorithm>
#include <stdexcept>

namespace eigenguard {

// ============================================================
// Konstruktor va destruktor
// ============================================================

SplineProcessor::SplineProcessor()
    : computed_(false) {
}

SplineProcessor::~SplineProcessor() = default;

// ============================================================
// Ma'lumot nuqtalarini o'rnatish
// ============================================================

bool SplineProcessor::setDataPoints(const double* t, const double* y, size_t count) {
    // Minimal tekshiruv: kamida 3 nuqta kerak
    if (count < 3 || t == nullptr || y == nullptr) {
        return false;
    }

    // x massivi o'sish tartibida bo'lishi kerak
    for (size_t i = 1; i < count; ++i) {
        if (t[i] <= t[i - 1]) {
            return false;  // Noto'g'ri tartib
        }
    }

    // Ma'lumotlarni saqlash
    size_t n = count - 1;  // Oraliqlar soni

    coeffs_.x.assign(t, t + count);
    coeffs_.a.assign(y, y + count);
    coeffs_.n = n;

    // Koeffitsiyent massivlarini tayyorlash
    coeffs_.b.resize(n);
    coeffs_.c.resize(count);  // c_0 dan c_n gacha
    coeffs_.d.resize(n);

    // Yordamchi massivlar
    h_.resize(n);
    alpha_.resize(n);
    l_.resize(count);
    mu_.resize(count);
    z_.resize(count);

    computed_ = false;
    return true;
}

// ============================================================
// Asosiy hisoblash
// ============================================================

bool SplineProcessor::computeCoefficients() {
    if (coeffs_.x.empty() || coeffs_.a.empty()) {
        return false;
    }

    // 1-qadam: Tridagonal sistema qurish
    buildTridiagonalSystem();

    // 2-qadam: To'g'ri haydash (Forward sweep)
    forwardSweep();

    // 3-qadam: Teskari haydash (Back substitution)
    backSubstitution();

    computed_ = true;
    return true;
}

// ============================================================
// 1-Qadam: Tridagonal sistema qurish
// Kitob 113-bet: h_i va alpha_i hisoblash
// ============================================================

void SplineProcessor::buildTridiagonalSystem() {
    size_t n = coeffs_.n;

    // Qadam uzunliklari: h_i = x_{i+1} - x_i
    for (size_t i = 0; i < n; ++i) {
        h_[i] = coeffs_.x[i + 1] - coeffs_.x[i];
    }

    // O'ng tomon vektori:
    // alpha_i = (3/h_i)*(a_{i+1} - a_i) - (3/h_{i-1})*(a_i - a_{i-1})
    // i = 1, 2, ..., n-1
    for (size_t i = 1; i < n; ++i) {
        alpha_[i] = (3.0 / h_[i]) * (coeffs_.a[i + 1] - coeffs_.a[i])
                  - (3.0 / h_[i - 1]) * (coeffs_.a[i] - coeffs_.a[i - 1]);
    }
}

// ============================================================
// 2-Qadam: To'g'ri haydash (Progonka — Forward Sweep)
// Kitob 113-bet: l_i, mu_i, z_i hisoblash
// Tridagonal sistema:
//   | 2(h_0+h_1)   h_1                         | | c_1   |   | alpha_1   |
//   | h_1     2(h_1+h_2)  h_2                   | | c_2   |   | alpha_2   |
//   |              ...                           | | ...   | = | ...       |
//   |                h_{n-2}  2(h_{n-2}+h_{n-1})| | c_{n-1}|  | alpha_{n-1}|
// ============================================================

void SplineProcessor::forwardSweep() {
    size_t n = coeffs_.n;

    // Natural splayn sharti: c_0 = 0
    l_[0] = 1.0;
    mu_[0] = 0.0;
    z_[0] = 0.0;

    // To'g'ri haydash: i = 1, 2, ..., n-1
    for (size_t i = 1; i < n; ++i) {
        l_[i] = 2.0 * (coeffs_.x[i + 1] - coeffs_.x[i - 1]) - h_[i - 1] * mu_[i - 1];
        mu_[i] = h_[i] / l_[i];
        z_[i] = (alpha_[i] - h_[i - 1] * z_[i - 1]) / l_[i];
    }

    // Natural splayn sharti: c_n = 0
    l_[n] = 1.0;
    z_[n] = 0.0;
}

// ============================================================
// 3-Qadam: Teskari haydash (Back Substitution)
// Kitob 113-bet: c_i, b_i, d_i topish
//   c_n = 0 (natural splayn sharti)
//   j = n-1, n-2, ..., 0:
//     c_j = z_j - mu_j * c_{j+1}
//     b_j = (a_{j+1} - a_j) / h_j - h_j * (c_{j+1} + 2*c_j) / 3
//     d_j = (c_{j+1} - c_j) / (3 * h_j)
// ============================================================

void SplineProcessor::backSubstitution() {
    size_t n = coeffs_.n;

    // c_n = 0 (natural splayn)
    coeffs_.c[n] = 0.0;

    // Teskari haydash: j = n-1, n-2, ..., 0
    for (int j = static_cast<int>(n) - 1; j >= 0; --j) {
        size_t idx = static_cast<size_t>(j);
        coeffs_.c[idx] = z_[idx] - mu_[idx] * coeffs_.c[idx + 1];

        coeffs_.b[idx] = (coeffs_.a[idx + 1] - coeffs_.a[idx]) / h_[idx]
                       - h_[idx] * (coeffs_.c[idx + 1] + 2.0 * coeffs_.c[idx]) / 3.0;

        coeffs_.d[idx] = (coeffs_.c[idx + 1] - coeffs_.c[idx]) / (3.0 * h_[idx]);
    }
}

// ============================================================
// Splayn qiymatini hisoblash: S_i(x) = a_i + b_i*dx + c_i*dx^2 + d_i*dx^3
// bu yerda dx = x - x_i
// ============================================================

double SplineProcessor::evaluate(double x) const {
    if (!computed_) {
        return 0.0;
    }

    size_t i = findInterval(x);
    double dx = x - coeffs_.x[i];

    return coeffs_.a[i]
         + coeffs_.b[i] * dx
         + coeffs_.c[i] * dx * dx
         + coeffs_.d[i] * dx * dx * dx;
}

// ============================================================
// Splayn hosilasini hisoblash: S'_i(x) = b_i + 2*c_i*dx + 3*d_i*dx^2
// ============================================================

double SplineProcessor::evaluateDerivative(double x) const {
    if (!computed_) {
        return 0.0;
    }

    size_t i = findInterval(x);
    double dx = x - coeffs_.x[i];

    return coeffs_.b[i]
         + 2.0 * coeffs_.c[i] * dx
         + 3.0 * coeffs_.d[i] * dx * dx;
}

// ============================================================
// Koeffitsiyentlarni qaytarish
// ============================================================

const SplineCoefficients& SplineProcessor::getCoefficients() const {
    return coeffs_;
}

bool SplineProcessor::isComputed() const {
    return computed_;
}

size_t SplineProcessor::getPointCount() const {
    return coeffs_.x.size();
}

// ============================================================
// Yordamchi funksiya: Binary search bilan oraliq topish
// x ga mos i indeksini topadi: x_i <= x < x_{i+1}
// ============================================================

size_t SplineProcessor::findInterval(double x) const {
    size_t n = coeffs_.n;

    // Chegaraviy holatlar
    if (x <= coeffs_.x[0]) {
        return 0;
    }
    if (x >= coeffs_.x[n]) {
        return n - 1;
    }

    // Binary search
    size_t low = 0;
    size_t high = n;

    while (low < high) {
        size_t mid = (low + high) / 2;
        if (coeffs_.x[mid + 1] <= x) {
            low = mid + 1;
        } else if (coeffs_.x[mid] > x) {
            high = mid;
        } else {
            return mid;
        }
    }

    return low;
}

} // namespace eigenguard
