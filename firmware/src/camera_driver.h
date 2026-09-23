#pragma once

#include "esp_camera.h"
#include <Arduino.h>
#include <freertos/semphr.h>

enum CameraPreset {
    CAM_PRESET_BALANCED = 0,
    CAM_PRESET_TEXT_SCREEN = 1,
    CAM_PRESET_OUTDOOR = 2
};

class CameraDriver {
public:
    static bool initCamera();
    static camera_fb_t* captureFrame(int preDropFrames = 1);
    static void releaseFrame(camera_fb_t* fb);
    static bool resetCamera();
    static bool isOperational();
    static uint32_t failureCount();
    static uint32_t totalCaptures();
    static uint32_t corruptCount();
    static bool isValidJpeg(const uint8_t* buf, size_t len);

    // Ajustes dinámicos de sensor
    static bool applyPreset(CameraPreset preset);
    static bool setResolution(framesize_t frameSize);
    static bool setExposureCompensation(int level); // -2 a +2
    static bool setQuality(int quality); // 10 a 63 (menor es mejor)
    static String getCurrentSettingsJson();

private:
    static SemaphoreHandle_t cameraMutex;
    static bool initialized;
    static uint32_t consecutiveFailures;
    static uint32_t totalFramesCaptured;
    static uint32_t totalCorruptFrames;
    static CameraPreset currentPreset;
    static int currentAeLevel;
    static framesize_t currentFramesize;
};
