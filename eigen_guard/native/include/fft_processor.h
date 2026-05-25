#pragma once
#include <vector>
#include <complex>

namespace eigenguard {

class FftProcessor {
public:
    FftProcessor();
    
    // Vaqt zonasidagi ma'lumotlarni qabul qilib, dominant chastota va spektrni hisoblaydi.
    // signal_amplitudes: Spline dan olingan silliqlangan amplitudalar
    // sample_rate: sekundiga necha marta o'qilayotgani (FPS yoki Hz)
    // dominant_freq_out: eng kuchli tebranish chastotasi qaytariladi
    // magnitudes_out: barcha spektral amplitudalar qaytariladi
    void compute(const std::vector<double>& signal_amplitudes, double sample_rate, 
                 double& dominant_freq_out, std::vector<double>& magnitudes_out);

private:
    void performFFT(std::vector<std::complex<double>>& x);
};

} // namespace eigenguard
