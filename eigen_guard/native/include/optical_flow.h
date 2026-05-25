#ifndef OPTICAL_FLOW_H
#define OPTICAL_FLOW_H

#include <cstdint>
#include <vector>

namespace eigenguard {

struct FlowResult {
    float dx;
    float dy;
    float magnitude;
};

// Lucas-Kanade asosida Optical Flow hisoblash
// frame1 va frame2 - YUV420 formatining Y (grayscale) qismi deb qabul qilinadi
class OpticalFlowProcessor {
public:
    OpticalFlowProcessor(int width, int height);
    ~OpticalFlowProcessor() = default;

    // Ikkita kadr o'rtasidagi o'rtacha siljishni hisoblaydi (grid yondashuvi)
    // roi: Region of Interest. Agar berilsa, faqat u yer tahlil qilinadi
    FlowResult computeAverageFlow(const uint8_t* frame1, const uint8_t* frame2, int roi_x = 0, int roi_y = 0, int roi_w = 0, int roi_h = 0);

private:
    int m_width;
    int m_height;
    int m_windowSize;
    int m_stride;
};

} // namespace eigenguard

#endif // OPTICAL_FLOW_H
