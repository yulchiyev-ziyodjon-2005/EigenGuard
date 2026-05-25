#include "kalman_filter.h"

namespace eigenguard {

KalmanFilter::KalmanFilter(double process_noise, double measurement_noise, double estimation_error, double initial_value) {
    this->q = process_noise;
    this->r = measurement_noise;
    this->p = estimation_error;
    this->x = initial_value;
}

double KalmanFilter::update(double measurement) {
    // Prediction update
    p = p + q;

    // Measurement update
    k = p / (p + r);
    x = x + k * (measurement - x);
    p = (1.0 - k) * p;

    return x;
}

} // namespace eigenguard
