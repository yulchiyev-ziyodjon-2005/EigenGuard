#ifndef EIGENGUARD_FFI_BRIDGE_H
#define EIGENGUARD_FFI_BRIDGE_H

#include <stdint.h>

// Platform-specific export makrosi
#if defined(_WIN32) || defined(_WIN64)
    #define EIGENGUARD_EXPORT __declspec(dllexport)
#else
    #define EIGENGUARD_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================
// SplineProcessor FFI Bridge (Bosqich 3)
// ============================================================

EIGENGUARD_EXPORT void* spline_create();
EIGENGUARD_EXPORT void spline_destroy(void* handle);
EIGENGUARD_EXPORT int32_t spline_set_data(void* handle, const double* t,
                                           const double* y, int32_t count);
EIGENGUARD_EXPORT int32_t spline_compute(void* handle);
EIGENGUARD_EXPORT double spline_evaluate(void* handle, double x);
EIGENGUARD_EXPORT double spline_evaluate_derivative(void* handle, double x);
EIGENGUARD_EXPORT int32_t spline_get_coefficients(void* handle,
                                                   double* a, double* b,
                                                   double* c, double* d,
                                                   int32_t max_count);
EIGENGUARD_EXPORT int32_t spline_get_point_count(void* handle);
EIGENGUARD_EXPORT int32_t spline_evaluate_batch(void* handle,
                                                 const double* x_values,
                                                 double* y_out,
                                                 int32_t count);

// ============================================================
// OpticalFlowProcessor FFI Bridge (Bosqich 1)
// ============================================================

EIGENGUARD_EXPORT void* optical_flow_create(int32_t width, int32_t height);
EIGENGUARD_EXPORT void optical_flow_destroy(void* handle);
EIGENGUARD_EXPORT float optical_flow_compute(void* handle, 
                                             const uint8_t* frame1, 
                                             const uint8_t* frame2, 
                                             float* dx_out, 
                                             float* dy_out);

// ============================================================
// KalmanFilter FFI Bridge (Bosqich 2)
// ============================================================

EIGENGUARD_EXPORT void* kalman_create(double process_noise,
                                       double measurement_noise,
                                       double estimation_error,
                                       double initial_value);
EIGENGUARD_EXPORT void kalman_destroy(void* handle);
EIGENGUARD_EXPORT double kalman_update(void* handle, double measurement);

// ============================================================
// FftProcessor FFI Bridge (Bosqich 4)
// ============================================================

EIGENGUARD_EXPORT void* fft_create();
EIGENGUARD_EXPORT void fft_destroy(void* handle);

/// Dominant chastotani qaytaradi (Hz)
EIGENGUARD_EXPORT double fft_compute_dominant(void* handle,
                                               const double* signal,
                                               int32_t count,
                                               double sample_rate);

/// To'liq spektr: magnitudes massivini to'ldiradi, dominant chastotani yozadi
/// @return Chiqish elementlari soni
EIGENGUARD_EXPORT int32_t fft_compute_spectrum(void* handle,
                                                const double* signal,
                                                int32_t count,
                                                double sample_rate,
                                                double* magnitudes_out,
                                                int32_t max_out,
                                                double* dominant_freq_out);

// ============================================================
// ApproximationProcessor FFI Bridge (Bosqich 5 — §6.4)
// ============================================================

EIGENGUARD_EXPORT void* approx_create();
EIGENGUARD_EXPORT void approx_destroy(void* handle);

/// §6.4 Bashorat — parabolik fit va Time-to-Critical
/// @param direction_out: -1=KAMAYMOQDA, 0=BARQAROR, 1=OSHMOQDA
EIGENGUARD_EXPORT void approx_predict(void* handle,
                                       const double* t,
                                       const double* y,
                                       int32_t count,
                                       double y_limit,
                                       double* a_out,
                                       double* b_out,
                                       double* c_out,
                                       double* hours_out,
                                       int32_t* direction_out);

// ============================================================
// Yagona Pipeline Chaqiruvi (Camera Frame → Natija)
// ============================================================

/// Kamera kadrini qabul qilib, 1 va 2 bosqichlarni (Optical Flow + Kalman)
/// bitta chaqiruvda bajaradi.
/// @param pipeline_handle — kalman_create dan qaytgan handle
/// @param flow_handle — optical_flow_create dan qaytgan handle
/// @param frame_data — Y-plane greyscale piksellari
/// @param width, height — kadr o'lchamlari
/// @param prev_frame — oldingi kadr (nullptr bo'lsa, faqat joriy kadr saqlanadi)
/// @param dx_out, dy_out — Kalman filtrlangan siljish
/// @return tozalangan magnitud (amplituda)
EIGENGUARD_EXPORT float process_camera_frame(
    void* flow_handle,
    void* kalman_dx_handle,
    void* kalman_dy_handle,
    const uint8_t* prev_frame,
    const uint8_t* curr_frame,
    int32_t width,
    int32_t height,
    float imu_dx,
    float imu_dy,
    float* dx_out,
    float* dy_out);

// ============================================================
// Versiya ma'lumoti
// ============================================================
EIGENGUARD_EXPORT const char* eigenguard_version();

#ifdef __cplusplus
}
#endif

#endif // EIGENGUARD_FFI_BRIDGE_H
