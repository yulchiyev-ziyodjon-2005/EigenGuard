/// FFI Bridge implementatsiyasi — 5 Bosqichli Pipeline
/// Dart FFI orqali C++ SplineProcessor, OpticalFlow, KalmanFilter,
/// FftProcessor va ApproximationProcessor ni chaqirish uchun C-ABI wrapper.

#include "ffi_bridge.h"
#include "spline_processor.h"
#include "optical_flow.h"
#include "kalman_filter.h"
#include "fft_processor.h"
#include "approximation_processor.h"
#include <cstring>
#include <cmath>
#include <vector>

using namespace eigenguard;

static const char* ENGINE_VERSION = "EigenGuard Native Engine v1.5.0";

// ============================================================
// SplineProcessor FFI Bridge
// ============================================================

EIGENGUARD_EXPORT void* spline_create() {
    try {
        return new SplineProcessor();
    } catch (...) {
        return nullptr;
    }
}

EIGENGUARD_EXPORT void spline_destroy(void* handle) {
    if (handle) {
        delete static_cast<SplineProcessor*>(handle);
    }
}

EIGENGUARD_EXPORT int32_t spline_set_data(void* handle, const double* t,
                                           const double* y, int32_t count) {
    if (!handle || !t || !y || count < 3) {
        return 0;
    }

    auto* processor = static_cast<SplineProcessor*>(handle);
    return processor->setDataPoints(t, y, static_cast<size_t>(count)) ? 1 : 0;
}

EIGENGUARD_EXPORT int32_t spline_compute(void* handle) {
    if (!handle) {
        return 0;
    }

    auto* processor = static_cast<SplineProcessor*>(handle);
    return processor->computeCoefficients() ? 1 : 0;
}

EIGENGUARD_EXPORT double spline_evaluate(void* handle, double x) {
    if (!handle) {
        return 0.0;
    }

    auto* processor = static_cast<SplineProcessor*>(handle);
    return processor->evaluate(x);
}

EIGENGUARD_EXPORT double spline_evaluate_derivative(void* handle, double x) {
    if (!handle) {
        return 0.0;
    }

    auto* processor = static_cast<SplineProcessor*>(handle);
    return processor->evaluateDerivative(x);
}

EIGENGUARD_EXPORT int32_t spline_get_coefficients(void* handle,
                                                   double* a, double* b,
                                                   double* c, double* d,
                                                   int32_t max_count) {
    if (!handle) {
        return -1;
    }

    auto* processor = static_cast<SplineProcessor*>(handle);

    if (!processor->isComputed()) {
        return -1;
    }

    const auto& coeffs = processor->getCoefficients();
    int32_t n = static_cast<int32_t>(coeffs.n);

    if (n > max_count) {
        n = max_count;
    }

    if (a) std::memcpy(a, coeffs.a.data(), n * sizeof(double));
    if (b) std::memcpy(b, coeffs.b.data(), n * sizeof(double));
    if (c) std::memcpy(c, coeffs.c.data(), n * sizeof(double));
    if (d) std::memcpy(d, coeffs.d.data(), n * sizeof(double));

    return n;
}

EIGENGUARD_EXPORT int32_t spline_get_point_count(void* handle) {
    if (!handle) {
        return 0;
    }

    auto* processor = static_cast<SplineProcessor*>(handle);
    return static_cast<int32_t>(processor->getPointCount());
}

EIGENGUARD_EXPORT int32_t spline_evaluate_batch(void* handle,
                                                 const double* x_values,
                                                 double* y_out,
                                                 int32_t count) {
    if (!handle || !x_values || !y_out || count <= 0) {
        return 0;
    }

    auto* processor = static_cast<SplineProcessor*>(handle);

    if (!processor->isComputed()) {
        return 0;
    }

    for (int32_t i = 0; i < count; ++i) {
        y_out[i] = processor->evaluate(x_values[i]);
    }

    return 1;
}

// ============================================================
// OpticalFlowProcessor FFI Bridge
// ============================================================

EIGENGUARD_EXPORT void* optical_flow_create(int32_t width, int32_t height) {
    try {
        return new OpticalFlowProcessor(width, height);
    } catch (...) {
        return nullptr;
    }
}

EIGENGUARD_EXPORT void optical_flow_destroy(void* handle) {
    if (handle) {
        delete static_cast<OpticalFlowProcessor*>(handle);
    }
}

EIGENGUARD_EXPORT float optical_flow_compute(void* handle, 
                                             const uint8_t* frame1, 
                                             const uint8_t* frame2, 
                                             float* dx_out, 
                                             float* dy_out) {
    if (!handle || !frame1 || !frame2) {
        if (dx_out) *dx_out = 0.0f;
        if (dy_out) *dy_out = 0.0f;
        return 0.0f;
    }
    auto* processor = static_cast<OpticalFlowProcessor*>(handle);
    FlowResult result = processor->computeAverageFlow(frame1, frame2);
    
    if (dx_out) *dx_out = result.dx;
    if (dy_out) *dy_out = result.dy;
    
    return result.magnitude;
}

// ============================================================
// KalmanFilter FFI Bridge (Bosqich 2)
// ============================================================

EIGENGUARD_EXPORT void* kalman_create(double process_noise,
                                       double measurement_noise,
                                       double estimation_error,
                                       double initial_value) {
    try {
        return new KalmanFilter(process_noise, measurement_noise,
                                estimation_error, initial_value);
    } catch (...) {
        return nullptr;
    }
}

EIGENGUARD_EXPORT void kalman_destroy(void* handle) {
    if (handle) {
        delete static_cast<KalmanFilter*>(handle);
    }
}

EIGENGUARD_EXPORT double kalman_update(void* handle, double measurement) {
    if (!handle) return measurement;
    auto* filter = static_cast<KalmanFilter*>(handle);
    return filter->update(measurement);
}

// ============================================================
// FftProcessor FFI Bridge (Bosqich 4)
// ============================================================

EIGENGUARD_EXPORT void* fft_create() {
    try {
        return new FftProcessor();
    } catch (...) {
        return nullptr;
    }
}

EIGENGUARD_EXPORT void fft_destroy(void* handle) {
    if (handle) {
        delete static_cast<FftProcessor*>(handle);
    }
}

EIGENGUARD_EXPORT double fft_compute_dominant(void* handle,
                                               const double* signal,
                                               int32_t count,
                                               double sample_rate) {
    if (!handle || !signal || count <= 0) return 0.0;

    auto* processor = static_cast<FftProcessor*>(handle);
    std::vector<double> sig(signal, signal + count);
    double dominant_freq = 0.0;
    std::vector<double> magnitudes;

    processor->compute(sig, sample_rate, dominant_freq, magnitudes);
    return dominant_freq;
}

EIGENGUARD_EXPORT int32_t fft_compute_spectrum(void* handle,
                                                const double* signal,
                                                int32_t count,
                                                double sample_rate,
                                                double* magnitudes_out,
                                                int32_t max_out,
                                                double* dominant_freq_out) {
    if (!handle || !signal || count <= 0) return 0;

    auto* processor = static_cast<FftProcessor*>(handle);
    std::vector<double> sig(signal, signal + count);
    double dominant_freq = 0.0;
    std::vector<double> magnitudes;

    processor->compute(sig, sample_rate, dominant_freq, magnitudes);

    if (dominant_freq_out) *dominant_freq_out = dominant_freq;

    int32_t out_count = static_cast<int32_t>(magnitudes.size());
    if (out_count > max_out) out_count = max_out;

    if (magnitudes_out && out_count > 0) {
        std::memcpy(magnitudes_out, magnitudes.data(), out_count * sizeof(double));
    }

    return out_count;
}

// ============================================================
// ApproximationProcessor FFI Bridge (Bosqich 5 — §6.4)
// ============================================================

EIGENGUARD_EXPORT void* approx_create() {
    try {
        return new ApproximationProcessor();
    } catch (...) {
        return nullptr;
    }
}

EIGENGUARD_EXPORT void approx_destroy(void* handle) {
    if (handle) {
        delete static_cast<ApproximationProcessor*>(handle);
    }
}

EIGENGUARD_EXPORT void approx_predict(void* handle,
                                       const double* t,
                                       const double* y,
                                       int32_t count,
                                       double y_limit,
                                       double* a_out,
                                       double* b_out,
                                       double* c_out,
                                       double* hours_out,
                                       int32_t* direction_out) {
    if (!handle || !t || !y || count < 3) {
        if (a_out) *a_out = 0;
        if (b_out) *b_out = 0;
        if (c_out) *c_out = 0;
        if (hours_out) *hours_out = -1;
        if (direction_out) *direction_out = 0;
        return;
    }

    auto* processor = static_cast<ApproximationProcessor*>(handle);
    PredictionResult result = processor->predict(t, y, count, y_limit);

    if (a_out) *a_out = result.a;
    if (b_out) *b_out = result.b;
    if (c_out) *c_out = result.c;
    if (hours_out) *hours_out = result.hours_to_critical;
    if (direction_out) *direction_out = static_cast<int32_t>(result.direction);
}

// ============================================================
// Yagona Pipeline: Camera Frame → Filtered Magnitude
// ============================================================

EIGENGUARD_EXPORT float process_camera_frame(
    void* flow_handle,
    void* kalman_dx_handle,
    void* kalman_dy_handle,
    const uint8_t* prev_frame,
    const uint8_t* curr_frame,
    int32_t width,
    int32_t height,
    int32_t roi_x,
    int32_t roi_y,
    int32_t roi_w,
    int32_t roi_h,
    float imu_dx,
    float imu_dy,
    float* dx_out,
    float* dy_out) {

    if (!flow_handle || !curr_frame || !prev_frame) {
        if (dx_out) *dx_out = 0.0f;
        if (dy_out) *dy_out = 0.0f;
        return 0.0f;
    }

    // Bosqich 1: Optical Flow - endi faqat berilgan ROI ichida ishlaydi
    auto* flow = static_cast<OpticalFlowProcessor*>(flow_handle);
    FlowResult raw = flow->computeAverageFlow(prev_frame, curr_frame, roi_x, roi_y, roi_w, roi_h);

    // IMU qiymatini ayirish (Qo'l qaltirashini tozalash)
    float adjusted_dx = raw.dx - imu_dx;
    float adjusted_dy = raw.dy - imu_dy;

    float filtered_dx = adjusted_dx;
    float filtered_dy = adjusted_dy;

    // Bosqich 2: Kalman Filtri (shovqin tozalash)
    if (kalman_dx_handle) {
        auto* kx = static_cast<KalmanFilter*>(kalman_dx_handle);
        filtered_dx = static_cast<float>(kx->update(static_cast<double>(adjusted_dx)));
    }
    if (kalman_dy_handle) {
        auto* ky = static_cast<KalmanFilter*>(kalman_dy_handle);
        filtered_dy = static_cast<float>(ky->update(static_cast<double>(adjusted_dy)));
    }

    if (dx_out) *dx_out = filtered_dx;
    if (dy_out) *dy_out = filtered_dy;

    // Natija: tozalangan magnitud
    return std::sqrt(filtered_dx * filtered_dx + filtered_dy * filtered_dy);
}

// ============================================================
// Versiya
// ============================================================

EIGENGUARD_EXPORT const char* eigenguard_version() {
    return ENGINE_VERSION;
}
