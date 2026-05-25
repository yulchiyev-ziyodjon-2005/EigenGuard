#include "optical_flow.h"
#include <cmath>
#include <iostream>

namespace eigenguard {

OpticalFlowProcessor::OpticalFlowProcessor(int width, int height)
    : m_width(width), m_height(height), m_windowSize(15), m_stride(20) {
    // Katta kameralar uchun hisoblashni yengillatish maqsadida grid stride tanlanadi
}

FlowResult OpticalFlowProcessor::computeAverageFlow(const uint8_t* frame1, const uint8_t* frame2, int roi_x, int roi_y, int roi_w, int roi_h) {
    if (!frame1 || !frame2) {
        return {0.0f, 0.0f, 0.0f};
    }

    float total_dx = 0.0f;
    float total_dy = 0.0f;
    int valid_blocks = 0;

    int half_win = m_windowSize / 2;

    int start_x = (roi_w > 0) ? roi_x : 0;
    int start_y = (roi_h > 0) ? roi_y : 0;
    int end_x = (roi_w > 0) ? roi_x + roi_w : m_width;
    int end_y = (roi_h > 0) ? roi_y + roi_h : m_height;

    // Chegaralarni xavfsiz qilish
    if (start_x < 0) start_x = 0;
    if (start_y < 0) start_y = 0;
    if (end_x > m_width) end_x = m_width;
    if (end_y > m_height) end_y = m_height;

    start_x = std::max(start_x, half_win + 1);
    start_y = std::max(start_y, half_win + 1);
    end_x = std::min(end_x, m_width - half_win - 1);
    end_y = std::min(end_y, m_height - half_win - 1);

    if (start_x >= end_x || start_y >= end_y) {
        return {0.0f, 0.0f, 0.0f};
    }

    // Kadrdan faqat ROI (chegalarni) qoldirib grid orqali o'tamiz
    for (int y = start_y; y < end_y; y += m_stride) {
        for (int x = start_x; x < end_x; x += m_stride) {
            
            float sum_ix2 = 0.0f;
            float sum_iy2 = 0.0f;
            float sum_ixiy = 0.0f;
            float sum_ixt = 0.0f;
            float sum_iyt = 0.0f;

            // Oyna ichidagi gradientlarni hisoblash
            for (int wy = -half_win; wy <= half_win; ++wy) {
                for (int wx = -half_win; wx <= half_win; ++wx) {
                    int px = x + wx;
                    int py = y + wy;
                    
                    int idx = py * m_width + px;
                    int idx_right = py * m_width + (px + 1);
                    int idx_left = py * m_width + (px - 1);
                    int idx_down = (py + 1) * m_width + px;
                    int idx_up = (py - 1) * m_width + px;

                    // X va Y o'qlari boyicha gradient (Central Difference)
                    float ix = (frame1[idx_right] - frame1[idx_left]) / 2.0f;
                    float iy = (frame1[idx_down] - frame1[idx_up]) / 2.0f;
                    
                    // Vaqt bo'yicha gradient (Difference between frames)
                    float it = static_cast<float>(frame2[idx]) - static_cast<float>(frame1[idx]);

                    sum_ix2 += ix * ix;
                    sum_iy2 += iy * iy;
                    sum_ixiy += ix * iy;
                    sum_ixt += ix * it;
                    sum_iyt += iy * it;
                }
            }

            // Cramer qoidasi orqali tenglamalar sistemasini yechish
            float det = sum_ix2 * sum_iy2 - sum_ixiy * sum_ixiy;
            if (det > 1e-4f) { // Non-singular matrix
                float u = (sum_iy2 * (-sum_ixt) - sum_ixiy * (-sum_iyt)) / det;
                float v = (sum_ix2 * (-sum_iyt) - sum_ixiy * (-sum_ixt)) / det;

                // Anomaliyalarni (judayam katta sakrash) filtrlash
                if (std::abs(u) < 20.0f && std::abs(v) < 20.0f) {
                    total_dx += u;
                    total_dy += v;
                    valid_blocks++;
                }
            }
        }
    }

    if (valid_blocks > 0) {
        float avg_dx = total_dx / valid_blocks;
        float avg_dy = total_dy / valid_blocks;
        return {
            avg_dx,
            avg_dy,
            std::sqrt(avg_dx * avg_dx + avg_dy * avg_dy)
        };
    }

    return {0.0f, 0.0f, 0.0f};
}

} // namespace eigenguard
