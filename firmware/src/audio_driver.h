#pragma once

#include <Arduino.h>
#include "driver/i2s.h"

class AudioDriver {
public:
    static bool initMic();
    static bool initSpeaker();
    static size_t readMicSamples(int16_t* buffer, size_t samplesToRead, uint32_t timeoutMs = 300);
    static size_t playAudioChunk(const uint8_t* pcmData, size_t bytesToWrite);
    static void playTestTone(uint32_t frequencyHz = 440, uint32_t durationMs = 300);

    static uint32_t micReadErrors();
    static uint32_t speakerErrors();

private:
    static uint32_t micErrors;
    static uint32_t spkErrors;
};
