#pragma once

// Cálculo puro de batería (testeable en native Unity y en Flutter).
// Asume LiPo 1S con divisor 1:2: 3.30V = 0%, 4.20V = 100%.
inline int batteryPercentFromVoltage(float vBat) {
    float pct = ((vBat - 3.30f) / 0.90f) * 100.0f;
    if (pct < 0.0f) return 0;
    if (pct > 100.0f) return 100;
    return (int)(pct + 0.5f);
}

inline float batteryVoltageFromAdc(int rawAdc, float vRef = 3.3f, float divider = 2.0f) {
    if (rawAdc < 0) return 0.0f;
    return (rawAdc / 4095.0f) * vRef * divider;
}
