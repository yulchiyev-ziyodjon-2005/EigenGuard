#include "fft_processor.h"
#include <cmath>
#include <algorithm>

namespace eigenguard {

const double PI = 3.141592653589793238460;

FftProcessor::FftProcessor() {}

void FftProcessor::performFFT(std::vector<std::complex<double>>& x) {
    size_t n = x.size();
    if (n <= 1) return;

    // Uzunlik 2 ning darajasi ekanligini tekshiramiz
    if ((n & (n - 1)) != 0) {
        // Agar 2 ning darajasi bo'lmasa, eng yaqin darajaga kattalashtiramiz (zero-padding)
        size_t next_power_of_2 = 1;
        while (next_power_of_2 < n) next_power_of_2 <<= 1;
        x.resize(next_power_of_2, 0.0);
        n = next_power_of_2;
    }

    // Bit-reversal permutation
    size_t shift = 1;
    while ((1 << shift) < n) shift++;
    shift = sizeof(size_t) * 8 - shift;

    for (size_t i = 1; i < n; i++) {
        size_t j = 0;
        size_t temp = i;
        for (size_t k = 0; k < (sizeof(size_t) * 8 - shift); k++) {
            j = (j << 1) | (temp & 1);
            temp >>= 1;
        }
        if (i < j) {
            std::swap(x[i], x[j]);
        }
    }

    // Cooley-Tukey Radix-2
    for (size_t k = 1; k < n; k *= 2) {
        double theta = -PI / k;
        std::complex<double> w_m(cos(theta), sin(theta));
        for (size_t i = 0; i < n; i += 2 * k) {
            std::complex<double> w(1, 0);
            for (size_t j = 0; j < k; j++) {
                std::complex<double> t = w * x[i + j + k];
                std::complex<double> u = x[i + j];
                x[i + j] = u + t;
                x[i + j + k] = u - t;
                w *= w_m;
            }
        }
    }
}

void FftProcessor::compute(const std::vector<double>& signal_amplitudes, double sample_rate, 
                           double& dominant_freq_out, std::vector<double>& magnitudes_out) {
    if (signal_amplitudes.empty()) {
        dominant_freq_out = 0.0;
        magnitudes_out.clear();
        return;
    }

    size_t original_size = signal_amplitudes.size();
    std::vector<std::complex<double>> complex_signal(original_size);
    for (size_t i = 0; i < original_size; ++i) {
        complex_signal[i] = std::complex<double>(signal_amplitudes[i], 0.0);
    }

    performFFT(complex_signal);

    size_t n = complex_signal.size();
    magnitudes_out.resize(n / 2); // Faqat ijobiy chastotalar
    
    double max_magnitude = -1.0;
    int dominant_index = 0;

    // Nyquist frekuensiyasigacha olamiz
    for (size_t i = 0; i < n / 2; ++i) {
        // Amplitudani hisoblaymiz (magnitude)
        double mag = std::abs(complex_signal[i]) / n;
        // i=0 bu DC (doimiy) komponent, uni e'tiborga olmasligimiz mumkin
        if (i == 0) {
            // Yoki DC komponentini tozalash uchun
            mag = 0.0; 
        } else {
             mag *= 2.0; // ijobiy qismga 2 marta kuch
        }

        magnitudes_out[i] = mag;

        if (mag > max_magnitude) {
            max_magnitude = mag;
            dominant_index = i;
        }
    }

    // Dominant chastotani Hz da topish
    dominant_freq_out = static_cast<double>(dominant_index) * sample_rate / static_cast<double>(n);
}

} // namespace eigenguard
