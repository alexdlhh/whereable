#include "audio_driver.h"
#include "config.h"
#include "system_control.h"
#include <esp_task_wdt.h>

#define I2S_MIC_PORT     I2S_NUM_0
#define I2S_SPK_PORT     I2S_NUM_1
#define AUDIO_SAMPLE_RATE 16000

uint32_t AudioDriver::micErrors = 0;
uint32_t AudioDriver::spkErrors = 0;

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
        i2s_driver_uninstall(I2S_MIC_PORT);
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

size_t AudioDriver::readMicSamples(int16_t* buffer, size_t samplesToRead, uint32_t timeoutMs) {
    if (!buffer || samplesToRead == 0) return 0;
    esp_task_wdt_reset();

    size_t bytesRead = 0;
    esp_err_t err = i2s_read(I2S_MIC_PORT, (char*)buffer, samplesToRead * sizeof(int16_t), &bytesRead, pdMS_TO_TICKS(timeoutMs));
    if (err != ESP_OK) {
        micErrors++;
        SystemControl::i2sMicErrors++;
        if (err == ESP_ERR_TIMEOUT) {
            SystemControl::log(SYS_LOG_WARN, "MIC", "Timeout en i2s_read (underrun DMA).");
            i2s_zero_dma_buffer(I2S_MIC_PORT);
        } else {
            SystemControl::logf(SYS_LOG_WARN, "MIC", "Error i2s_read: 0x%x", err);
        }
        // Auto-recovery: cada 5 errores seguidos reinstala el driver PDM.
        static uint8_t consecMicFails = 0;
        consecMicFails++;
        if (consecMicFails >= 5) {
            consecMicFails = 0;
            SystemControl::log(SYS_LOG_ERROR, "MIC", "Auto-recovery: reinstalando driver PDM.");
            i2s_driver_uninstall(I2S_MIC_PORT);
            delay(50);
            initMic();
        }
    } else {
        // Éxito parcial (bytesRead>0) no cuenta como error aunque err!=OK ya se trató.
    }

    return bytesRead / sizeof(int16_t);
}

size_t AudioDriver::playAudioChunk(const uint8_t* pcmData, size_t bytesToWrite) {
    if (!pcmData || bytesToWrite == 0) return 0;

    const int16_t* mono = reinterpret_cast<const int16_t*>(pcmData);
    const size_t samples = bytesToWrite / sizeof(int16_t);
    const size_t chunk = 256;
    int16_t stereo[chunk * 2];
    size_t writtenTotal = 0;

    for (size_t s = 0; s < samples; ) {
        esp_task_wdt_reset();
        size_t n = min(chunk, samples - s);
        for (size_t i = 0; i < n; i++) {
            stereo[i * 2] = mono[s + i];
            stereo[i * 2 + 1] = mono[s + i];
        }
        size_t bytesWritten = 0;
        esp_err_t err = i2s_write(I2S_SPK_PORT, stereo, n * 2 * sizeof(int16_t), &bytesWritten, pdMS_TO_TICKS(250));
        if (err != ESP_OK || bytesWritten == 0) {
            spkErrors++;
            SystemControl::i2sSpkErrors++;
            SystemControl::logf(SYS_LOG_WARN, "SPK", "Error i2s_write: 0x%x", err);
            break;
        }
        writtenTotal += bytesWritten;
        s += n;
    }
    return writtenTotal;
}

uint32_t AudioDriver::micReadErrors() {
    return micErrors;
}

uint32_t AudioDriver::speakerErrors() {
    return spkErrors;
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
