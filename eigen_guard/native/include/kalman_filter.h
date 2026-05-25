#pragma once

namespace eigenguard {

class KalmanFilter {
public:
    KalmanFilter(double process_noise, double measurement_noise, double estimation_error, double initial_value);
    
    // Yangi shovqinli qiymatni kiritamiz va tozalangan qiymatni olamiz
    double update(double measurement);

private:
    double q; // Process noise covariance
    double r; // Measurement noise covariance
    double x; // Value
    double p; // Estimation error covariance
    double k; // Kalman gain
};

} // namespace eigenguard
