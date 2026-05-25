#ifndef EIGENGUARD_SPLINE_PROCESSOR_H
#define EIGENGUARD_SPLINE_PROCESSOR_H

#include <vector>
#include <cstddef>

namespace eigenguard {

/// Kubik splayn koeffitsiyentlari: S_i(x) = a + b*(x-x_i) + c*(x-x_i)^2 + d*(x-x_i)^3
struct SplineCoefficients {
    std::vector<double> a;  // Splayn qiymatlari (y_i)
    std::vector<double> b;  // Birinchi tartibli koeffitsientlar
    std::vector<double> c;  // Ikkinchi tartibli koeffitsientlar
    std::vector<double> d;  // Uchinchi tartibli koeffitsientlar
    std::vector<double> x;  // Tugun nuqtalari x koordinatalari
    size_t n;               // Oraliqlar soni (nuqtalar - 1)
};

/// Kubik Splayn-interpolyatsiya protsessori.
/// "Sonli usullar" kitobining 6.3-paragrafiga asoslangan.
/// Haydash usuli (Progonka / Thomas algoritmi) bilan tridagonal sistemani yechadi.
class SplineProcessor {
public:
    SplineProcessor();
    ~SplineProcessor();

    /// Kirish ma'lumotlarini o'rnatish.
    /// @param t Vaqt (yoki x) massivi, o'sish tartibida bo'lishi kerak.
    /// @param y Amplituda (yoki y) massivi.
    /// @param count Nuqtalar soni (kamida 3 bo'lishi kerak).
    /// @return true agar ma'lumotlar to'g'ri qabul qilinsa.
    bool setDataPoints(const double* t, const double* y, size_t count);

    /// Splayn koeffitsiyentlarini hisoblash.
    /// Ichki tridagonal sistema quriladi va Haydash usuli bilan yechiladi.
    /// Natural splayn sharti: S''(x_0) = 0 va S''(x_n) = 0.
    /// @return true agar hisoblash muvaffaqiyatli bo'lsa.
    bool computeCoefficients();

    /// Berilgan x nuqtada splayn qiymatini hisoblash.
    /// @param x Hisoblash nuqtasi (t[0] <= x <= t[n] oralig'ida bo'lishi kerak).
    /// @return S(x) qiymati.
    double evaluate(double x) const;

    /// Berilgan x nuqtada splaynning birinchi hosilasini hisoblash.
    /// @param x Hisoblash nuqtasi.
    /// @return S'(x) qiymati.
    double evaluateDerivative(double x) const;

    /// Hisoblangan koeffitsiyentlarni olish.
    /// @return SplineCoefficients strukturasi.
    const SplineCoefficients& getCoefficients() const;

    /// Koeffitsiyentlar hisoblanganmi?
    bool isComputed() const;

    /// Ma'lumotlar nuqtalari soni.
    size_t getPointCount() const;

private:
    /// Tridagonal sistema qurish: h_i, alpha_i hisoblash.
    void buildTridiagonalSystem();

    /// To'g'ri haydash (Forward sweep / Progonka).
    /// l_i, mu_i, z_i koeffitsiyentlarini hisoblaydi.
    void forwardSweep();

    /// Teskari haydash (Back substitution).
    /// c_i, b_i, d_i koeffitsiyentlarini topadi.
    void backSubstitution();

    /// x nuqtaga mos oraliq indeksini topish (binary search).
    size_t findInterval(double x) const;

    SplineCoefficients coeffs_;     // Natija koeffitsiyentlari
    std::vector<double> h_;         // Qadam uzunliklari: h_i = x_{i+1} - x_i
    std::vector<double> alpha_;     // O'ng tomon vektori
    std::vector<double> l_;         // Haydash: pastki diagonal
    std::vector<double> mu_;        // Haydash: koeffitsiyent
    std::vector<double> z_;         // Haydash: yordamchi vektor
    bool computed_;                 // Hisoblash holati
};

} // namespace eigenguard

#endif // EIGENGUARD_SPLINE_PROCESSOR_H
