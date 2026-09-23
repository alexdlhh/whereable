# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "firmware" / "src"

CAMERA_CPP = r'''#include "camera_driver.h"
#include "config.h"

SemaphoreHandle_t CameraDriver::cameraMutex = nullptr;
bool CameraDriver::initialized = false;
uint32_t CameraDriver::consecutiveFailures = 0;

bool CameraDriver::initCamera() {
    if (cameraMutex == nullptr) {
        cameraMutex = xSemaphoreCreateMutex();
    }

    if (cameraMutex != nullptr) {
        xSemaphoreTake(cameraMutex, portMAX_DELAY);
    }

    camera_config_t config;
    config.ledc_channel = LEDC_CHANNEL_0;
    config.ledc_timer = LEDC_TIMER_0;
    config.pin_d0 = Y2_GPIO_NUM;
    config.pin_d1 = Y3_GPIO_NUM;
    config.pin_d2 = Y4_GPIO_NUM;
    config.pin_d3 = Y5_GPIO_NUM;
    config.pin_d4 = Y6_GPIO_NUM;
    config.pin_d5 = Y7_GPIO_NUM;
    config.pin_d6 = Y8_GPIO_NUM;
    config.pin_d7 = Y9_GPIO_NUM;
    config.pin_xclk = XCLK_GPIO_NUM;
    config.pin_pclk = PCLK_GPIO_NUM;
    config.pin_vsync = VSYNC_GPIO_NUM;
    config.pin_href = HREF_GPIO_NUM;
    config.pin_sccb_sda = SIOD_GPIO_NUM;
    config.pin_sccb_scl = SIOC_GPIO_NUM;
    config.pin_pwdn = PWDN_GPIO_NUM;
    config.pin_reset = RESET_GPIO_NUM;
    config.xclk_freq_hz = 20000000;
    config.frame_size = FRAMESIZE_UXGA;
    config.pixel_format = PIXFORMAT_JPEG;
    config.grab_mode = CAMERA_GRAB_LATEST;
    config.fb_location = CAMERA_FB_IN_PSRAM;
    config.jpeg_quality = 12;
    config.fb_count = 2;

    if (!psramFound()) {
        Serial.println("[CAM ERROR] PSRAM no detectada. Reduciendo a SVGA.");
        config.frame_size = FRAMESIZE_SVGA;
        config.fb_location = CAMERA_FB_IN_DRAM;
        config.fb_count = 1;
    }

    esp_err_t err = esp_camera_init(&config);
    if (err != ESP_OK) {
        Serial.printf("[CAM ERROR] Fallo inicializando camara: 0x%x\n", err);
        initialized = false;
        if (cameraMutex != nullptr) xSemaphoreGive(cameraMutex);
        return false;
    }

    sensor_t* s = esp_camera_sensor_get();
    if (s != nullptr) {
        s->set_brightness(s, 1);
        s->set_contrast(s, 1);
        s->set_saturation(s, 0);
        s->set_sharpness(s, 1);
        s->set_whitebal(s, 1);
        s->set_awb_gain(s, 1);
        s->set_wb_mode(s, 0);
    }

    initialized = true;
    consecutiveFailures = 0;
    if (cameraMutex != nullptr) xSemaphoreGive(cameraMutex);

    Serial.println("[CAM OK] Camara inicializada y protegida por Mutex.");
    return true;
}

bool CameraDriver::resetCamera() {
    Serial.println("[CAM WARN] Reinicializando driver de camara...");
    if (cameraMutex != nullptr) {
        xSemaphoreTake(cameraMutex, portMAX_DELAY);
    }
    esp_camera_deinit();
    initialized = false;
    if (cameraMutex != nullptr) {
        xSemaphoreGive(cameraMutex);
    }
    delay(100);
    return initCamera();
}

camera_fb_t* CameraDriver::captureFrame() {
    if (!initialized) {
        if (!initCamera()) return nullptr;
    }

    if (cameraMutex != nullptr) {
        if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(1500)) != pdTRUE) {
            Serial.println("[CAM WARN] Mutex ocupado al capturar frame.");
            return nullptr;
        }
    }

    camera_fb_t* fb = esp_camera_fb_get();
    if (fb) {
        esp_camera_fb_return(fb);
    }
    fb = esp_camera_fb_get();

    if (!fb) {
        consecutiveFailures++;
        Serial.printf("[CAM WARN] Fallo al capturar frame (%d fallos consecutivos)\n", consecutiveFailures);
        if (cameraMutex != nullptr) xSemaphoreGive(cameraMutex);
        if (consecutiveFailures >= 3) {
            resetCamera();
        }
        return nullptr;
    }

    consecutiveFailures = 0;
    return fb;
}

void CameraDriver::releaseFrame(camera_fb_t* fb) {
    if (fb) {
        esp_camera_fb_return(fb);
    }
    if (cameraMutex != nullptr) {
        xSemaphoreGive(cameraMutex);
    }
}

bool CameraDriver::isOperational() {
    return initialized && (consecutiveFailures < 3);
}

uint32_t CameraDriver::failureCount() {
    return consecutiveFailures;
}
'''

AUDIO_CPP = r'''#include "audio_driver.h"
#include "config.h"

#define I2S_MIC_PORT     I2S_NUM_0
#define I2S_SPK_PORT     I2S_NUM_1
#define AUDIO_SAMPLE_RATE 16000

bool AudioDriver::initMic() {
    i2s_config_t i2s_config = {
        .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX | I2S_MODE_PDM),
        .sample_rate = AUDIO_SAMPLE_RATE,
        .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
        .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
        .communication_format = I2S_COMM_FORMAT_STAND_I2S,
        .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
        .dma_buf_count = 4,
        .dma_buf_len = 512,
        .use_apll = false,
        .tx_desc_auto_clear = false,
        .fixed_mclk = 0
    };

    i2s_pin_config_t pin_config = {
        .bck_io_num = I2S_PIN_NO_CHANGE,
        .ws_io_num = PDM_CLK_PIN,
        .data_out_num = I2S_PIN_NO_CHANGE,
        .data_in_num = PDM_DATA_PIN
    };

    esp_err_t err = i2s_driver_install(I2S_MIC_PORT, &i2s_config, 0, NULL);
    if (err != ESP_OK) {
        Serial.printf("[AUDIO MIC ERROR] Driver install fail: %d\n", err);
        return false;
    }

    err = i2s_set_pin(I2S_MIC_PORT, &pin_config);
    if (err != ESP_OK) {
        Serial.printf("[AUDIO MIC ERROR] Set pin fail: %d\n", err);
        return false;
    }

    Serial.println("[AUDIO MIC OK] Microfono PDM inicializado (16kHz).");
    return true;
}

bool AudioDriver::initSpeaker() {
    i2s_config_t spk_config = {
        .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX),
        .sample_rate = AUDIO_SAMPLE_RATE,
        .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
        .channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT,
        .communication_format = I2S_COMM_FORMAT_STAND_I2S,
        .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
        .dma_buf_count = 6,
        .dma_buf_len = 512,
        .use_apll = false,
        .tx_desc_auto_clear = true,
        .fixed_mclk = 0
    };

    i2s_pin_config_t spk_pins = {
        .bck_io_num = I2S_SPK_BCLK,
        .ws_io_num = I2S_SPK_LRCK,
        .data_out_num = I2S_SPK_DOUT,
        .data_in_num = I2S_PIN_NO_CHANGE
    };

    esp_err_t err = i2s_driver_install(I2S_SPK_PORT, &spk_config, 0, NULL);
    if (err != ESP_OK) {
        Serial.printf("[AUDIO SPK ERROR] Driver install fail: %d\n", err);
        return false;
    }

    err = i2s_set_pin(I2S_SPK_PORT, &spk_pins);
    if (err != ESP_OK) {
        Serial.printf("[AUDIO SPK ERROR] Pin config fail: %d\n", err);
        return false;
    }

    Serial.println("[AUDIO SPK OK] Altavoz I2S inicializado.");
    return true;
}

size_t AudioDriver::readMicSamples(int16_t* buffer, size_t samplesToRead) {
    size_t bytesRead = 0;
    i2s_read(I2S_MIC_PORT, (char*)buffer, samplesToRead * sizeof(int16_t), &bytesRead, pdMS_TO_TICKS(200));
    return bytesRead / sizeof(int16_t);
}

size_t AudioDriver::playAudioChunk(const uint8_t* pcmData, size_t bytesToWrite) {
    const int16_t* mono = reinterpret_cast<const int16_t*>(pcmData);
    const size_t samples = bytesToWrite / sizeof(int16_t);
    const size_t chunk = 256;
    int16_t stereo[chunk * 2];
    size_t writtenTotal = 0;

    for (size_t s = 0; s < samples; ) {
        size_t n = min(chunk, samples - s);
        for (size_t i = 0; i < n; i++) {
            stereo[i * 2] = mono[s + i];
            stereo[i * 2 + 1] = mono[s + i];
        }
        size_t bytesWritten = 0;
        i2s_write(I2S_SPK_PORT, stereo, n * 2 * sizeof(int16_t), &bytesWritten, pdMS_TO_TICKS(250));
        if (bytesWritten == 0) {
            break;
        }
        writtenTotal += bytesWritten;
        s += n;
    }
    return writtenTotal;
}

void AudioDriver::playTestTone(uint32_t frequencyHz, uint32_t durationMs) {
    const size_t sampleCount = (AUDIO_SAMPLE_RATE * durationMs) / 1000;
    const size_t bufferSize = 256;
    int16_t buffer[bufferSize * 2];

    size_t generated = 0;
    while (generated < sampleCount) {
        size_t chunk = min((size_t)bufferSize, sampleCount - generated);
        for (size_t i = 0; i < chunk; i++) {
            float t = (float)(generated + i) / (float)AUDIO_SAMPLE_RATE;
            int16_t sample = (int16_t)(sin(2.0f * M_PI * frequencyHz * t) * 12000.0f);
            buffer[i * 2] = sample;
            buffer[i * 2 + 1] = sample;
        }
        size_t bytesWritten = 0;
        i2s_write(I2S_SPK_PORT, (const uint8_t*)buffer, chunk * 2 * sizeof(int16_t), &bytesWritten, pdMS_TO_TICKS(250));
        if (bytesWritten == 0) {
            break;
        }
        generated += chunk;
    }
}
'''

def main():
    (SRC / "camera_driver.cpp").write_text(CAMERA_CPP.replace('\r\n', '\n'), encoding='utf-8')
    (SRC / "audio_driver.cpp").write_text(AUDIO_CPP.replace('\r\n', '\n'), encoding='utf-8')
    print('wrote camera_driver.cpp and audio_driver.cpp')

if __name__ == '__main__':
    main()
