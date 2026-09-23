#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <Update.h>
#include <ESPAsyncWebServer.h>
#include <AsyncTCP.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <esp_camera.h>
#include <esp_task_wdt.h>
#include <esp_idf_version.h>
#include <driver/i2s.h>
#include <freertos/semphr.h>
#include <esp_heap_caps.h>
#include <cstdarg>
#include <math.h>
#include <memory>

// ============================================================
// XIAO ESP32-S3 SENSE - SMART GLASSES
// Version Arduino IDE + PlatformIO compatible
// ============================================================

#define FW_VERSION "1.5.0-RESILIENT2"
#define FW_BUILD_NAME "GlassesPro-Resilient-v1.5"
#define WDT_TIMEOUT_SECONDS 10

// Cámara integrada XIAO ESP32-S3 Sense
#define PWDN_GPIO_NUM  -1
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM  10
#define SIOD_GPIO_NUM  40
#define SIOC_GPIO_NUM  39
#define Y9_GPIO_NUM    48
#define Y8_GPIO_NUM    11
#define Y7_GPIO_NUM    12
#define Y6_GPIO_NUM    14
#define Y5_GPIO_NUM    16
#define Y4_GPIO_NUM    18
#define Y3_GPIO_NUM    17
#define Y2_GPIO_NUM    15
#define VSYNC_GPIO_NUM 38
#define HREF_GPIO_NUM  47
#define PCLK_GPIO_NUM  13

// Micrófono PDM integrado
#define PDM_CLK_PIN  42
#define PDM_DATA_PIN 41

// Altavoz I2S externo MAX98357A
#define I2S_SPK_BCLK GPIO_NUM_7
#define I2S_SPK_LRCK GPIO_NUM_8
#define I2S_SPK_DOUT GPIO_NUM_9

// Entrada para divisor de tensión de batería
#define BATTERY_ADC_PIN 1

// Wi-Fi propio (Punto de acceso de emergencia)
#define SOFTAP_SSID "XIAO-Glasses-AP"
#define SOFTAP_PASS "12345678"

// Baliza de descubrimiento UDP (Hotspot)
#define UDP_BEACON_PORT 4210
#define UDP_BEACON_INTERVAL_MS 1500

// Bluetooth BLE
#define BLE_DEVICE_NAME "XIAO-SmartGlasses"
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define WIFI_CONFIG_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define DEVICE_STATUS_CHAR_UUID "8b1b22e1-4547-497b-83a3-6b746a5996b7"

#define I2S_MIC_PORT I2S_NUM_0
#define I2S_SPK_PORT I2S_NUM_1
#define AUDIO_SAMPLE_RATE 16000

// ============================================================
// BATERÍA
// ============================================================

int batteryPercentFromVoltage(float voltage) {
  float pct = ((voltage - 3.30f) / 0.90f) * 100.0f;
  if (pct < 0.0f) return 0;
  if (pct > 100.0f) return 100;
  return (int)(pct + 0.5f);
}

float batteryVoltageFromAdc(int rawAdc) {
  if (rawAdc < 0) return 0.0f;
  return (rawAdc / 4095.0f) * 3.3f * 2.0f;
}

// ============================================================
// AUDIO
// ============================================================

bool microphoneReady = false;
bool speakerReady = false;
// Contadores de errores I2S para telemetría (/status, /selftest)
uint32_t i2sMicErrors = 0;
uint32_t i2sSpkErrors = 0;

bool initMicrophone() {
  i2s_config_t micConfig = {};
  micConfig.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX | I2S_MODE_PDM);
  micConfig.sample_rate = AUDIO_SAMPLE_RATE;
  micConfig.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT;
  micConfig.channel_format = I2S_CHANNEL_FMT_ONLY_LEFT;
  micConfig.communication_format = I2S_COMM_FORMAT_STAND_I2S;
  micConfig.intr_alloc_flags = ESP_INTR_FLAG_LEVEL1;
  micConfig.dma_buf_count = 4;
  micConfig.dma_buf_len = 512;
  micConfig.use_apll = false;
  micConfig.tx_desc_auto_clear = false;
  micConfig.fixed_mclk = 0;

  i2s_pin_config_t pins = {};
  pins.bck_io_num = I2S_PIN_NO_CHANGE;
  pins.ws_io_num = PDM_CLK_PIN;
  pins.data_out_num = I2S_PIN_NO_CHANGE;
  pins.data_in_num = PDM_DATA_PIN;

  esp_err_t err = i2s_driver_install(I2S_MIC_PORT, &micConfig, 0, nullptr);
  if (err != ESP_OK) {
    Serial.printf("[MIC ERROR] i2s_driver_install: %d\n", err);
    return false;
  }

  err = i2s_set_pin(I2S_MIC_PORT, &pins);
  if (err != ESP_OK) {
    Serial.printf("[MIC ERROR] i2s_set_pin: %d\n", err);
    i2s_driver_uninstall(I2S_MIC_PORT);
    return false;
  }

  Serial.println("[MIC OK] Microfono PDM iniciado a 16 kHz.");
  return true;
}

bool initSpeaker() {
  i2s_config_t speakerConfig = {};
  speakerConfig.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX);
  speakerConfig.sample_rate = AUDIO_SAMPLE_RATE;
  speakerConfig.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT;
  speakerConfig.channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT;
  speakerConfig.communication_format = I2S_COMM_FORMAT_STAND_I2S;
  speakerConfig.intr_alloc_flags = ESP_INTR_FLAG_LEVEL1;
  speakerConfig.dma_buf_count = 6;
  speakerConfig.dma_buf_len = 512;
  speakerConfig.use_apll = false;
  speakerConfig.tx_desc_auto_clear = true;
  speakerConfig.fixed_mclk = 0;

  i2s_pin_config_t pins = {};
  pins.bck_io_num = I2S_SPK_BCLK;
  pins.ws_io_num = I2S_SPK_LRCK;
  pins.data_out_num = I2S_SPK_DOUT;
  pins.data_in_num = I2S_PIN_NO_CHANGE;

  esp_err_t err = i2s_driver_install(I2S_SPK_PORT, &speakerConfig, 0, nullptr);
  if (err != ESP_OK) {
    Serial.printf("[ALTAVOZ ERROR] i2s_driver_install: %d\n", err);
    return false;
  }

  err = i2s_set_pin(I2S_SPK_PORT, &pins);
  if (err != ESP_OK) {
    Serial.printf("[ALTAVOZ ERROR] i2s_set_pin: %d\n", err);
    i2s_driver_uninstall(I2S_SPK_PORT);
    return false;
  }

  Serial.println("[ALTAVOZ OK] Salida I2S iniciada.");
  return true;
}

size_t readMicSamples(int16_t *buffer, size_t samplesToRead, uint32_t timeoutMs = 250) {
  if (!microphoneReady) return 0;
  size_t bytesRead = 0;
  esp_err_t err = i2s_read(I2S_MIC_PORT, buffer, samplesToRead * sizeof(int16_t),
                           &bytesRead, pdMS_TO_TICKS(timeoutMs));
  // Clasificación de errores: timeout/underrun (reintentable) vs silencio real
  if (err != ESP_OK) {
    i2sMicErrors++;
    i2s_zero_dma_buffer(I2S_MIC_PORT);
    // Auto-recovery: cada 5 fallos seguidos reinstala el driver PDM.
    static uint8_t consecMicFails = 0;
    if (++consecMicFails >= 5) {
      consecMicFails = 0;
      sysLog(SYS_LOG_ERROR, "MIC", "Auto-recovery: reinstalando driver PDM.");
      i2s_driver_uninstall(I2S_MIC_PORT);
      delay(50);
      microphoneReady = initMicrophone();
    }
    if (bytesRead == 0) return 0;
  } else if (bytesRead == 0) {
    i2sMicErrors++;
    return 0;
  }
  return bytesRead / sizeof(int16_t);
}

size_t playAudioChunk(const uint8_t *pcmData, size_t bytesToWrite) {
  if (!speakerReady || pcmData == nullptr || bytesToWrite < 2) return 0;

  const int16_t *mono = reinterpret_cast<const int16_t *>(pcmData);
  const size_t samples = bytesToWrite / sizeof(int16_t);
  const size_t chunkSize = 256;
  int16_t stereo[chunkSize * 2];
  size_t samplesProcessed = 0;

  while (samplesProcessed < samples) {
    size_t numberSamples = min(chunkSize, samples - samplesProcessed);
    for (size_t index = 0; index < numberSamples; index++) {
      int16_t sample = mono[samplesProcessed + index];
      stereo[index * 2] = sample;
      stereo[index * 2 + 1] = sample;
    }

    size_t bytesWritten = 0;
    esp_err_t werr = i2s_write(I2S_SPK_PORT, stereo, numberSamples * 2 * sizeof(int16_t),
              &bytesWritten, pdMS_TO_TICKS(250));
    if (werr != ESP_OK || bytesWritten == 0) {
      i2sSpkErrors++;
      break;
    }
    samplesProcessed += numberSamples;
  }

  return samplesProcessed * sizeof(int16_t);
}

void playTone(uint32_t frequencyHz, uint32_t durationMs) {
  if (!speakerReady) return;

  const size_t totalSamples = (AUDIO_SAMPLE_RATE * durationMs) / 1000;
  const size_t chunkSize = 256;
  int16_t buffer[chunkSize * 2];
  size_t generated = 0;

  while (generated < totalSamples) {
    size_t numberSamples = min(chunkSize, totalSamples - generated);
    for (size_t index = 0; index < numberSamples; index++) {
      float time = (float)(generated + index) / (float)AUDIO_SAMPLE_RATE;
      int16_t sample = (int16_t)(sinf(2.0f * PI * frequencyHz * time) * 12000.0f);
      buffer[index * 2] = sample;
      buffer[index * 2 + 1] = sample;
    }

    size_t bytesWritten = 0;
    i2s_write(I2S_SPK_PORT, buffer, numberSamples * 2 * sizeof(int16_t),
              &bytesWritten, pdMS_TO_TICKS(250));
    if (bytesWritten == 0) break;
    generated += numberSamples;
  }
}

// ============================================================
// CÁMARA
// ============================================================

enum CameraPreset {
  CAM_PRESET_BALANCED = 0,
  CAM_PRESET_TEXT_SCREEN = 1,
  CAM_PRESET_OUTDOOR = 2
};

SemaphoreHandle_t cameraMutex = nullptr;
bool cameraReady = false;
uint32_t cameraFailures = 0;
uint32_t camCapturesTotal = 0;
uint32_t camCapturesCorrupt = 0;
CameraPreset currentCamPreset = CAM_PRESET_TEXT_SCREEN;
int currentAeLevel = -2;
framesize_t currentFramesize = FRAMESIZE_UXGA;

bool applyCameraPreset(CameraPreset preset) {
  // Thread-safe: los handlers HTTP async llaman sin mutex. Timeout corto
  // para no bloquear /capture en curso; el cliente puede reintentar.
  bool locked = false;
  if (cameraMutex != nullptr) {
    if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(300)) != pdTRUE) {
      sysLog(SYS_LOG_WARN, "CAM", "Preset descartado: camara ocupada.");
      return false;
    }
    locked = true;
  }
  sensor_t *sensor = esp_camera_sensor_get();
  if (sensor == nullptr) { if (locked) xSemaphoreGive(cameraMutex); return false; }

  currentCamPreset = preset;
  switch (preset) {
    case CAM_PRESET_TEXT_SCREEN:
      sensor->set_brightness(sensor, 0);              // Brillo neutral (no saturar blancos)
      sensor->set_contrast(sensor, 2);                // Alto contraste para texto nítido
      sensor->set_saturation(sensor, -1);             // Menor aberración cromática en caracteres
      sensor->set_sharpness(sensor, 2);               // Máxima nitidez por DSP (compensa lente fija)
      sensor->set_whitebal(sensor, 1);
      sensor->set_awb_gain(sensor, 1);
      sensor->set_wb_mode(sensor, 0);
      sensor->set_aec2(sensor, 1);                    // Algoritmo DSP AEC2 basado en histograma
      sensor->set_ae_level(sensor, -2);               // Compensación -2 (elimina pantalla blanca quemada)
      sensor->set_gainceiling(sensor, GAINCEILING_2X);// Limitar ganancia (evita ruido y sobreexposición)
      sensor->set_bpc(sensor, 1);                     // Corrección de píxeles negros
      sensor->set_wpc(sensor, 1);                     // Corrección de píxeles blancos
      sensor->set_raw_gma(sensor, 1);                 // Curva gamma activa
      sensor->set_lenc(sensor, 1);                    // Corrección óptica de lente
      currentAeLevel = -2;
      Serial.println("[CAMARA PRESET] TEXT_SCREEN (AEC2 on, AE=-2, Sharpness=2, Contrast=2)");
      break;

    case CAM_PRESET_OUTDOOR:
      sensor->set_brightness(sensor, 0);
      sensor->set_contrast(sensor, 1);
      sensor->set_saturation(sensor, 1);
      sensor->set_sharpness(sensor, 1);
      sensor->set_whitebal(sensor, 1);
      sensor->set_awb_gain(sensor, 1);
      sensor->set_wb_mode(sensor, 0);
      sensor->set_aec2(sensor, 1);
      sensor->set_ae_level(sensor, -1);
      sensor->set_gainceiling(sensor, GAINCEILING_4X);
      sensor->set_bpc(sensor, 1);
      sensor->set_wpc(sensor, 1);
      sensor->set_raw_gma(sensor, 1);
      sensor->set_lenc(sensor, 1);
      currentAeLevel = -1;
      Serial.println("[CAMARA PRESET] OUTDOOR (AE=-1)");
      break;

    case CAM_PRESET_BALANCED:
    default:
      sensor->set_brightness(sensor, 0);
      sensor->set_contrast(sensor, 1);
      sensor->set_saturation(sensor, 0);
      sensor->set_sharpness(sensor, 1);
      sensor->set_whitebal(sensor, 1);
      sensor->set_awb_gain(sensor, 1);
      sensor->set_wb_mode(sensor, 0);
      sensor->set_aec2(sensor, 1);
      sensor->set_ae_level(sensor, 0);
      sensor->set_gainceiling(sensor, GAINCEILING_4X);
      sensor->set_bpc(sensor, 1);
      sensor->set_wpc(sensor, 1);
      sensor->set_raw_gma(sensor, 1);
      sensor->set_lenc(sensor, 1);
      currentAeLevel = 0;
      Serial.println("[CAMARA PRESET] BALANCED (AE=0)");
      break;
  }
  if (locked) xSemaphoreGive(cameraMutex);
  return true;
}

bool setCameraExposureCompensation(int level) {
  bool locked = false;
  if (cameraMutex != nullptr) {
    if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(300)) != pdTRUE) return false;
    locked = true;
  }
  sensor_t *s = esp_camera_sensor_get();
  if (s == nullptr) { if (locked) xSemaphoreGive(cameraMutex); return false; }
  if (level < -2) level = -2;
  if (level > 2) level = 2;
  s->set_ae_level(s, level);
  currentAeLevel = level;
  if (locked) xSemaphoreGive(cameraMutex);
  return true;
}

bool setCameraResolution(framesize_t frameSize) {
  if ((int)frameSize < 0 || (int)frameSize > 22) return false;
  bool locked = false;
  if (cameraMutex != nullptr) {
    if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(300)) != pdTRUE) return false;
    locked = true;
  }
  sensor_t *s = esp_camera_sensor_get();
  if (s == nullptr) { if (locked) xSemaphoreGive(cameraMutex); return false; }
  bool ok = (s->set_framesize(s, frameSize) == 0);
  if (ok) currentFramesize = frameSize;
  if (locked) xSemaphoreGive(cameraMutex);
  return ok;
}

bool setCameraQuality(int quality) {
  bool locked = false;
  if (cameraMutex != nullptr) {
    if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(300)) != pdTRUE) return false;
    locked = true;
  }
  sensor_t *s = esp_camera_sensor_get();
  if (s == nullptr) { if (locked) xSemaphoreGive(cameraMutex); return false; }
  if (quality < 10) quality = 10;
  if (quality > 63) quality = 63;
  s->set_quality(s, quality);
  if (locked) xSemaphoreGive(cameraMutex);
  return true;
}

String getCameraSettingsJson() {
  JsonDocument doc;
  doc["preset"] = (currentCamPreset == CAM_PRESET_TEXT_SCREEN) ? "text_screen" :
                  (currentCamPreset == CAM_PRESET_OUTDOOR) ? "outdoor" : "balanced";
  doc["ae_level"] = currentAeLevel;
  doc["framesize"] = (int)currentFramesize;
  doc["operational"] = cameraReady && cameraFailures < 3;
  doc["failures"] = cameraFailures;
  String out;
  serializeJson(doc, out);
  return out;
}

bool initCamera() {
  if (cameraMutex == nullptr) {
    cameraMutex = xSemaphoreCreateMutex();
  }

  if (cameraMutex != nullptr) {
    xSemaphoreTake(cameraMutex, portMAX_DELAY);
  }

  camera_config_t config = {};
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
  // OV3660 / OV5640 con 8MB PSRAM: UXGA (1600x1200) ofrece óptima nitidez para lectura de pantallas y texto
  config.frame_size = FRAMESIZE_UXGA;
  config.pixel_format = PIXFORMAT_JPEG;
  config.grab_mode = CAMERA_GRAB_LATEST;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = 10;
  config.fb_count = 2;

  if (!psramFound()) {
    Serial.println("[CAMARA] PSRAM no detectada; usando VGA.");
    config.frame_size = FRAMESIZE_VGA;
    config.fb_location = CAMERA_FB_IN_DRAM;
    config.fb_count = 1;
    config.jpeg_quality = 14;
    currentFramesize = FRAMESIZE_VGA;
  } else {
    currentFramesize = FRAMESIZE_UXGA;
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK && psramFound() && config.frame_size == FRAMESIZE_UXGA) {
    Serial.printf("[CAMARA WARN] UXGA fallo (0x%x). Intentando SXGA (1280x1024)...\n", err);
    config.frame_size = FRAMESIZE_SXGA;
    config.jpeg_quality = 12;
    currentFramesize = FRAMESIZE_SXGA;
    err = esp_camera_init(&config);
  }

  if (err != ESP_OK) {
    Serial.printf("[CAMARA ERROR] 0x%x\n", err);
    cameraReady = false;
    if (cameraMutex != nullptr) xSemaphoreGive(cameraMutex);
    return false;
  }

  sensor_t *sensor = esp_camera_sensor_get();
  if (sensor != nullptr) {
    applyCameraPreset(CAM_PRESET_TEXT_SCREEN);
  }

  cameraReady = true;
  cameraFailures = 0;
  if (cameraMutex != nullptr) xSemaphoreGive(cameraMutex);

  Serial.println("[CAMARA OK] Camara preparada (UXGA / AEC2 calibrado).");
  return true;
}

bool resetCamera() {
  // Nunca bloquear con portMAX_DELAY: puede llamarse tras liberar el mutex
  // desde captureFrame. Timeout corto y deja que initCamera re-tome.
  Serial.println("[CAMARA] Reiniciando...");
  if (cameraMutex != nullptr) {
    if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(500)) != pdTRUE) {
      sysLog(SYS_LOG_WARN, "CAM", "Reset diferido: mutex ocupado.");
      return false;
    }
    xSemaphoreGive(cameraMutex);
  }
  esp_camera_deinit();
  cameraReady = false;
  delay(100);
  return initCamera();
}

camera_fb_t *captureFrame(int preDropFrames = 1) {
  esp_task_wdt_reset();
  if (!cameraReady) {
    if (!initCamera()) return nullptr;
  }

  if (cameraMutex != nullptr &&
      xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(5000)) != pdTRUE) {
    // Timeout ampliado a 5s; alimentar WDT para no dispararlo en contención
    esp_task_wdt_reset();
    sysLog(SYS_LOG_WARN, "CAM", "Mutex ocupado al capturar frame.");
    return nullptr;
  }
  esp_task_wdt_reset();

  // Pre-descarte de fotogramas residuales para asentar AEC/AGC
  for (int i = 0; i < preDropFrames; i++) {
    camera_fb_t *dropFb = esp_camera_fb_get();
    if (dropFb != nullptr) {
      esp_camera_fb_return(dropFb);
    }
  }

  camera_fb_t *frame = esp_camera_fb_get();
  if (frame == nullptr) {
    cameraFailures++;
    camCapturesCorrupt++;
    if (cameraMutex != nullptr) xSemaphoreGive(cameraMutex);
    if (cameraFailures >= 3) resetCamera();
    return nullptr;
  }

  // Validación de marcadores JPEG SOI (FFD8) y EOI (FFD9): descarta corruptos
  // con un reintento inmediato para salvar la solicitud.
  if (frame->len < 4 || frame->buf[0] != 0xFF || frame->buf[1] != 0xD8 ||
      frame->buf[frame->len - 2] != 0xFF || frame->buf[frame->len - 1] != 0xD9) {
    camCapturesCorrupt++;
    esp_camera_fb_return(frame);
    frame = esp_camera_fb_get();
    if (frame == nullptr || frame->len < 4 || frame->buf[0] != 0xFF || frame->buf[1] != 0xD8 ||
        frame->buf[frame->len - 2] != 0xFF || frame->buf[frame->len - 1] != 0xD9) {
      if (frame != nullptr) esp_camera_fb_return(frame);
      cameraFailures++;
      bool needReset = (cameraFailures >= 3);
      if (cameraMutex != nullptr) xSemaphoreGive(cameraMutex);
      if (needReset) resetCamera();
      return nullptr;
    }
  }

  camCapturesTotal++;
  cameraFailures = 0;
  return frame;
}

void releaseFrame(camera_fb_t *frame) {
  if (frame != nullptr) esp_camera_fb_return(frame);
  if (cameraMutex != nullptr) xSemaphoreGive(cameraMutex);
}

// ============================================================
// CONTROL DEL SISTEMA
// ============================================================

bool restartPending = false;
unsigned long restartAt = 0;
bool beepPending = false;
uint32_t beepFrequency = 880;
uint32_t beepDuration = 220;

void scheduleRestart(uint32_t delayMs) {
  restartPending = true;
  restartAt = millis() + delayMs;
}

void scheduleBeep(uint32_t frequencyHz, uint32_t durationMs) {
  beepPending = true;
  beepFrequency = frequencyHz;
  beepDuration = durationMs;
}

void pollSystemControl() {
  if (beepPending) {
    beepPending = false;
    playTone(beepFrequency, beepDuration);
  }

  if (restartPending && (long)(millis() - restartAt) >= 0) {
    sysLog(2, "SYS", "Ejecutando reinicio diferido...");
    delay(50);
    ESP.restart();
  }
}

// ============================================================
// DIAGNÓSTICO: LOGS EN ANILLO, CRASH NVS, HEAP Y BATERÍA
// ============================================================

#define SYS_LOG_DEBUG 0
#define SYS_LOG_INFO  1
#define SYS_LOG_WARN  2
#define SYS_LOG_ERROR 3

struct SysLogEntry {
  uint32_t ts;
  uint8_t level;
  char tag[12];
  char msg[80];
};

static const size_t MAX_SYS_LOG_ENTRIES = 64;
static SysLogEntry sysLogEntries[MAX_SYS_LOG_ENTRIES];
static size_t sysLogHead = 0;
static size_t sysLogCount = 0;
static portMUX_TYPE sysLogMux = portMUX_INITIALIZER_UNLOCKED;

uint32_t wifiReconnects = 0;
static float filteredVoltage = 3.85f;
static bool voltageInitialized = false;

void sysLog(uint8_t level, const char *tag, const char *msg) {
  if (tag == nullptr || msg == nullptr) return;
  portENTER_CRITICAL(&sysLogMux);
  size_t index = (sysLogHead + sysLogCount) % MAX_SYS_LOG_ENTRIES;
  if (sysLogCount == MAX_SYS_LOG_ENTRIES) {
    sysLogHead = (sysLogHead + 1) % MAX_SYS_LOG_ENTRIES;
  } else {
    sysLogCount++;
  }
  SysLogEntry &e = sysLogEntries[index];
  e.ts = millis();
  e.level = level;
  strncpy(e.tag, tag, sizeof(e.tag) - 1);
  e.tag[sizeof(e.tag) - 1] = '\0';
  strncpy(e.msg, msg, sizeof(e.msg) - 1);
  e.msg[sizeof(e.msg) - 1] = '\0';
  uint32_t ts = e.ts;
  uint8_t lv = e.level;
  char tagCopy[12]; char msgCopy[80];
  strncpy(tagCopy, e.tag, sizeof(tagCopy));
  strncpy(msgCopy, e.msg, sizeof(msgCopy));
  portEXIT_CRITICAL(&sysLogMux);
  const char *lvl = (lv == SYS_LOG_DEBUG) ? "DEBUG" : (lv == SYS_LOG_INFO) ? "INFO" : (lv == SYS_LOG_WARN) ? "WARN" : "ERROR";
  Serial.printf("[%u][%s][%s] %s\n", ts, lvl, tagCopy, msgCopy);
}

void sysLogf(uint8_t level, const char *tag, const char *format, ...) {
  char buffer[80];
  va_list args;
  va_start(args, format);
  vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  sysLog(level, tag, buffer);
}

String getSysLogsJson(int limit, int minLevel) {
  if (limit <= 0 || limit > (int)MAX_SYS_LOG_ENTRIES) limit = MAX_SYS_LOG_ENTRIES;
  // Snapshot bajo sección crítica para evitar races con handlers async.
  struct Snap { uint32_t ts; uint8_t lvl; char tag[12]; char msg[80]; };
  Snap snap[MAX_SYS_LOG_ENTRIES];
  size_t snapCount = 0;
  portENTER_CRITICAL(&sysLogMux);
  snapCount = sysLogCount;
  for (size_t i = 0; i < snapCount && i < MAX_SYS_LOG_ENTRIES; i++) {
    size_t idx = (sysLogHead + i) % MAX_SYS_LOG_ENTRIES;
    snap[i].ts = sysLogEntries[idx].ts;
    snap[i].lvl = sysLogEntries[idx].level;
    strncpy(snap[i].tag, sysLogEntries[idx].tag, sizeof(snap[i].tag));
    strncpy(snap[i].msg, sysLogEntries[idx].msg, sizeof(snap[i].msg));
  }
  portEXIT_CRITICAL(&sysLogMux);
  JsonDocument doc;
  JsonArray arr = doc.to<JsonArray>();
  size_t collected = 0;
  for (int i = (int)snapCount - 1; i >= 0 && (int)collected < limit; i--) {
    if (snap[i].lvl >= minLevel) {
      JsonObject item = arr.add<JsonObject>();
      item["ts"] = snap[i].ts;
      item["level"] = (snap[i].lvl == SYS_LOG_DEBUG) ? "DEBUG" : (snap[i].lvl == SYS_LOG_INFO) ? "INFO" : (snap[i].lvl == SYS_LOG_WARN) ? "WARN" : "ERROR";
      item["tag"] = snap[i].tag;
      item["msg"] = snap[i].msg;
      collected++;
    }
  }
  String out;
  serializeJson(doc, out);
  return out;
}

void clearSysLogs() {
  portENTER_CRITICAL(&sysLogMux);
  sysLogHead = 0;
  sysLogCount = 0;
  portEXIT_CRITICAL(&sysLogMux);
}

static const char *resetReasonToStr(esp_reset_reason_t reason) {
  switch (reason) {
    case ESP_RST_UNKNOWN: return "UNKNOWN";
    case ESP_RST_POWERON: return "POWERON";
    case ESP_RST_EXT: return "EXT_PIN";
    case ESP_RST_SW: return "SW_RESTART";
    case ESP_RST_PANIC: return "EXCEPTION_PANIC";
    case ESP_RST_INT_WDT: return "INT_WATCHDOG";
    case ESP_RST_TASK_WDT: return "TASK_WATCHDOG";
    case ESP_RST_WDT: return "OTHER_WATCHDOG";
    case ESP_RST_DEEPSLEEP: return "DEEPSLEEP";
    case ESP_RST_BROWNOUT: return "BROWNOUT_VOLTAGE_DROP";
    case ESP_RST_SDIO: return "SDIO";
    default: return "OTHER";
  }
}

void initCrashMonitoring() {
  esp_reset_reason_t reason = esp_reset_reason();
  preferences.begin("sys_diag", false);
  uint32_t bootCount = preferences.getUInt("boot_cnt", 0) + 1;
  preferences.putUInt("boot_cnt", bootCount);
  bool isCrash = (reason == ESP_RST_PANIC || reason == ESP_RST_INT_WDT ||
                  reason == ESP_RST_TASK_WDT || reason == ESP_RST_WDT ||
                  reason == ESP_RST_BROWNOUT);
  if (isCrash) {
    uint32_t crashCount = preferences.getUInt("crash_cnt", 0) + 1;
    preferences.putUInt("crash_cnt", crashCount);
    preferences.putInt("last_reason", (int)reason);
    preferences.putString("reason_str", resetReasonToStr(reason));
    preferences.putUInt("last_crash_boot", bootCount);
  }
  preferences.end();
  sysLogf(isCrash ? SYS_LOG_ERROR : SYS_LOG_INFO, "SYS", "Boot #%u - Causa: %s", bootCount, resetReasonToStr(reason));
}

String getCrashLogJson() {
  preferences.begin("sys_diag", true);
  uint32_t bootCount = preferences.getUInt("boot_cnt", 0);
  uint32_t crashCount = preferences.getUInt("crash_cnt", 0);
  int lastReason = preferences.getInt("last_reason", (int)esp_reset_reason());
  String reasonStr = preferences.getString("reason_str", resetReasonToStr((esp_reset_reason_t)lastReason));
  uint32_t lastCrashBoot = preferences.getUInt("last_crash_boot", 0);
  preferences.end();
  JsonDocument doc;
  doc["boot_count"] = bootCount;
  doc["crash_count"] = crashCount;
  doc["last_reason_code"] = lastReason;
  doc["last_reason"] = reasonStr;
  doc["last_crash_boot"] = lastCrashBoot;
  doc["current_reason"] = resetReasonToStr(esp_reset_reason());
  doc["uptime_sec"] = millis() / 1000;
  doc["free_heap"] = ESP.getFreeHeap();
  doc["heap_frag_pct"] = getHeapFragmentation();
  String out;
  serializeJson(doc, out);
  return out;
}

uint8_t getHeapFragmentation() {
  size_t freeHeap = ESP.getFreeHeap();
  size_t maxBlock = heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
  if (freeHeap == 0) return 100;
  if (maxBlock >= freeHeap) return 0;
  return 100 - (uint8_t)((maxBlock * 100) / freeHeap);
}

float updateAndGetBatteryVoltage(float rawV) {
  if (!voltageInitialized) {
    filteredVoltage = rawV;
    voltageInitialized = true;
  } else {
    filteredVoltage = (filteredVoltage * 0.8f) + (rawV * 0.2f);
  }
  return filteredVoltage;
}

// ============================================================
// WI-FI Y BLUETOOTH
// ============================================================

Preferences preferences;
String currentSSID;
String currentPassword;
bool wifiShouldConnect = false;
bool wifiIsConnecting = false;
unsigned long wifiConnectStarted = 0;
unsigned long lastWifiRetry = 0;
unsigned long lastTelemetry = 0;

BLECharacteristic *wifiConfigCharacteristic = nullptr;
BLECharacteristic *statusCharacteristic = nullptr;
bool bleConnected = false;

WiFiUDP udpServer;
unsigned long lastUdpBeaconTime = 0;

void sendUdpBeacon() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (millis() - lastUdpBeaconTime < UDP_BEACON_INTERVAL_MS) return;

  lastUdpBeaconTime = millis();

  JsonDocument doc;
  doc["device"] = "XIAO-SmartGlasses";
  doc["ip"] = WiFi.localIP().toString();
  doc["port"] = 80;
  doc["fw"] = FW_VERSION;
  doc["rssi"] = WiFi.RSSI();
  doc["mode"] = "STA";
  String payload;
  serializeJson(doc, payload);

  IPAddress broadcastIp(255, 255, 255, 255);
  udpServer.beginPacket(broadcastIp, UDP_BEACON_PORT);
  udpServer.write((const uint8_t*)payload.c_str(), payload.length());
  udpServer.endPacket();
}

void saveCredentials(const String &ssid, const String &password) {
  preferences.begin("glasses_cfg", false);
  preferences.putString("ssid", ssid);
  preferences.putString("pass", password);
  preferences.end();
}

void loadCredentials() {
  preferences.begin("glasses_cfg", true);
  currentSSID = preferences.getString("ssid", "");
  currentPassword = preferences.getString("pass", "");
  preferences.end();
  wifiShouldConnect = currentSSID.length() > 0;
}

class GlassesServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    bleConnected = true;
    Serial.println("[BLE] Movil conectado.");
  }

  void onDisconnect(BLEServer *server) override {
    bleConnected = false;
    Serial.println("[BLE] Movil desconectado.");
    // Sin delay: onDisconnect corre en la tarea del stack BLE.
    server->getAdvertising()->start();
  }
};

class WiFiConfigCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    std::string raw = characteristic->getValue();
    if (raw.empty()) return;

    JsonDocument document;
    // Usar data()+size(): c_str() truncaría si el payload contiene 0x00.
    DeserializationError error = deserializeJson(document, raw.data(), raw.size());
    if (error) {
      Serial.printf("[BLE] JSON incorrecto: %s\n", error.c_str());
      return;
    }

    String newSSID = document["ssid"] | "";
    String newPassword = document["password"] | "";
    newSSID.trim();
    if (newSSID.length() == 0) {
      Serial.println("[BLE] SSID vacío ignorado.");
      return;
    }

    currentSSID = newSSID;
    currentPassword = newPassword;
    saveCredentials(currentSSID, currentPassword);
    wifiShouldConnect = true;
    Serial.printf("[BLE] Wi-Fi recibido: %s\n", currentSSID.c_str());
  }
};

GlassesServerCallbacks glassesServerCallbacks;
WiFiConfigCallbacks wifiConfigCallbacks;

void initBluetooth() {
  BLEDevice::init(BLE_DEVICE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(&glassesServerCallbacks);

  BLEService *service = server->createService(SERVICE_UUID);
  wifiConfigCharacteristic = service->createCharacteristic(
      WIFI_CONFIG_CHAR_UUID, BLECharacteristic::PROPERTY_WRITE);
  wifiConfigCharacteristic->setCallbacks(&wifiConfigCallbacks);

  statusCharacteristic = service->createCharacteristic(
      DEVICE_STATUS_CHAR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  statusCharacteristic->addDescriptor(new BLE2902());
  statusCharacteristic->setValue("{\"status\":\"booting\"}");

  service->start();
  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.printf("[BLE OK] Visible como %s\n", BLE_DEVICE_NAME);
}

// ============================================================
// SERVIDOR HTTP
// ============================================================

AsyncWebServer httpServer(80);

void addCors(AsyncWebServerResponse *response) {
  response->addHeader("Access-Control-Allow-Origin", "*");
  response->addHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  response->addHeader("Access-Control-Allow-Headers", "Content-Type");
  response->addHeader("Cache-Control", "no-store");
}

String makeStatusJson() {
  JsonDocument document;
  bool stationConnected = WiFi.status() == WL_CONNECTED;
  // Promedio de 8 muestras para reducir ruido ADC del S3 (±10%).
  long acc = 0;
  for (int i = 0; i < 8; i++) { acc += analogRead(BATTERY_ADC_PIN); delay(1); }
  float rawVoltage = batteryVoltageFromAdc(acc / 8);
  float batteryVoltage = updateAndGetBatteryVoltage(rawVoltage);

  document["status"] = "online";
  document["fw"] = FW_VERSION;
  document["ip"] = stationConnected ? WiFi.localIP().toString() : WiFi.softAPIP().toString();
  document["sta_ip"] = WiFi.localIP().toString();
  document["ap_ip"] = WiFi.softAPIP().toString();
  document["mode"] = stationConnected ? "STA" : "AP";
  document["rssi"] = stationConnected ? WiFi.RSSI() : 0;
  document["free_heap"] = ESP.getFreeHeap();
  document["free_psram"] = ESP.getFreePsram();
  document["heap_frag_pct"] = getHeapFragmentation();
  document["uptime_sec"] = millis() / 1000;
  document["camera_ok"] = cameraReady && cameraFailures < 3;
  document["camera_failures"] = cameraFailures;
  document["camera_captures"] = camCapturesTotal;
  document["camera_corrupt"] = camCapturesCorrupt;
  document["wifi_reconnects"] = wifiReconnects;
  document["i2s_mic_errors"] = i2sMicErrors;
  document["i2s_spk_errors"] = i2sSpkErrors;
  document["microphone_ok"] = microphoneReady;
  document["speaker_ok"] = speakerReady;
  document["battery_voltage"] = batteryVoltage;
  document["battery_raw_voltage"] = rawVoltage;
  document["battery_pct"] = batteryPercentFromVoltage(batteryVoltage);
  document["wdt_sec"] = WDT_TIMEOUT_SECONDS;

  String result;
  serializeJson(document, result);
  return result;
}

void initHttpServer() {
  httpServer.onNotFound([](AsyncWebServerRequest *request) {
    if (request->method() == HTTP_OPTIONS) {
      AsyncWebServerResponse *response = request->beginResponse(204);
      addCors(response);
      request->send(response);
      return;
    }
    AsyncWebServerResponse *response = request->beginResponse(
        404, "application/json", "{\"error\":\"not_found\"}");
    addCors(response);
    request->send(response);
  });

  httpServer.on("/", HTTP_GET, [](AsyncWebServerRequest *request) {
    String body = "{\"name\":\"XIAO-SmartGlasses\",\"fw\":\"" FW_VERSION "\",\"health\":\"/health\",\"capture\":\"/capture\",\"status\":\"/status\",\"logs\":\"/logs\",\"crash_log\":\"/crash_log\",\"network_stats\":\"/network_stats\"}";
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", body);
    addCors(response);
    request->send(response);
  });

  httpServer.on("/health", HTTP_GET, [](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", "{\"ok\":true}");
    addCors(response);
    request->send(response);
  });

  httpServer.on("/status", HTTP_GET, [](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", makeStatusJson());
    addCors(response);
    request->send(response);
  });

  httpServer.on("/logs", HTTP_GET, [](AsyncWebServerRequest *request) {
    int limit = 50;
    int minLevel = 0;
    if (request->hasParam("limit")) limit = request->getParam("limit")->value().toInt();
    if (request->hasParam("level")) {
      String lvl = request->getParam("level")->value();
      if (lvl == "info") minLevel = SYS_LOG_INFO;
      else if (lvl == "warn") minLevel = SYS_LOG_WARN;
      else if (lvl == "error") minLevel = SYS_LOG_ERROR;
    }
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", getSysLogsJson(limit, minLevel));
    addCors(response);
    request->send(response);
  });

  httpServer.on("/logs/clear", HTTP_POST, [](AsyncWebServerRequest *request) {
    clearSysLogs();
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", "{\"status\":\"logs_cleared\"}");
    addCors(response);
    request->send(response);
  });

  httpServer.on("/crash_log", HTTP_GET, [](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", getCrashLogJson());
    addCors(response);
    request->send(response);
  });

  httpServer.on("/crash_log/clear", HTTP_POST, [](AsyncWebServerRequest *request) {
    preferences.begin("sys_diag", false);
    preferences.putUInt("crash_cnt", 0);
    preferences.putString("reason_str", "CLEARED");
    preferences.end();
    sysLog(SYS_LOG_INFO, "SYS", "Crash log reiniciado manualmente.");
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", "{\"status\":\"crash_log_cleared\"}");
    addCors(response);
    request->send(response);
  });

  httpServer.on("/network_stats", HTTP_GET, [](AsyncWebServerRequest *request) {
    JsonDocument doc;
    bool sta = (WiFi.status() == WL_CONNECTED);
    doc["sta_connected"] = sta;
    doc["mode"] = sta ? "STA" : "AP";
    doc["sta_ip"] = WiFi.localIP().toString();
    doc["ap_ip"] = WiFi.softAPIP().toString();
    doc["sta_rssi"] = sta ? WiFi.RSSI() : 0;
    doc["sta_reconnects"] = wifiReconnects;
    doc["ap_stations"] = WiFi.softAPgetStationNum();
    doc["udp_beacon_interval_ms"] = UDP_BEACON_INTERVAL_MS;
    String body;
    serializeJson(doc, body);
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", body);
    addCors(response);
    request->send(response);
  });

  httpServer.on("/selftest", HTTP_GET, [](AsyncWebServerRequest *request) {
    JsonDocument doc;
    doc["fw"] = FW_VERSION;
    doc["camera"] = cameraReady;
    doc["microphone"] = microphoneReady;
    doc["speaker"] = speakerReady;
    doc["psram"] = ESP.getFreePsram();
    doc["heap"] = ESP.getFreeHeap();
    doc["heap_frag_pct"] = getHeapFragmentation();
    doc["mic_errors"] = i2sMicErrors;
    doc["speaker_errors"] = i2sSpkErrors;
    doc["camera_captures"] = camCapturesTotal;
    doc["camera_corrupt"] = camCapturesCorrupt;
    // GET idempotente por defecto: ?beep=1 mantiene compat; ?beep=0 lo omite.
    bool wantBeep = true;
    if (request->hasParam("beep")) {
      String v = request->getParam("beep")->value();
      v.toLowerCase();
      if (v == "0" || v == "no" || v == "false" || v == "off") wantBeep = false;
    }
    doc["speaker_beep"] = wantBeep ? "beep_queued" : "beep_skipped";
    String body;
    serializeJson(doc, body);
    if (wantBeep) scheduleBeep(880, 180);
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", body);
    addCors(response);
    request->send(response);
  });

  // Diagnóstico unificado (aditivo, no rompe /status): heap+PSRAM, reset, RSSI.
  httpServer.on("/diag", HTTP_GET, [](AsyncWebServerRequest *request) {
    JsonDocument doc;
    bool sta = (WiFi.status() == WL_CONNECTED);
    doc["fw"] = FW_VERSION;
    doc["uptime_sec"] = millis() / 1000;
    doc["reset_reason"] = (int)esp_reset_reason();
    doc["free_heap"] = ESP.getFreeHeap();
    doc["free_psram"] = ESP.getFreePsram();
    doc["heap_frag_pct"] = getHeapFragmentation();
    size_t psramFree = ESP.getFreePsram();
    size_t psramMax = heap_caps_get_largest_free_block(MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    doc["psram_frag_pct"] = (psramFree == 0) ? 100 : (psramMax >= psramFree ? 0 : 100 - (psramMax * 100 / psramFree));
    doc["rssi"] = sta ? WiFi.RSSI() : 0;
    doc["mode"] = sta ? "STA" : "AP";
    doc["camera_ok"] = cameraReady && cameraFailures < 3;
    doc["battery_pct"] = batteryPercentFromVoltage(filteredVoltage);
    String body;
    serializeJson(doc, body);
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", body);
    addCors(response);
    request->send(response);
  });

  httpServer.on("/camera_settings", HTTP_GET, [](AsyncWebServerRequest *request) {
    String body = getCameraSettingsJson();
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", body);
    addCors(response);
    request->send(response);
  });

  httpServer.on("/camera_settings", HTTP_POST,
      [](AsyncWebServerRequest *request) {
        AsyncWebServerResponse *response = request->beginResponse(200, "application/json", "{\"status\":\"ok\"}");
        addCors(response);
        request->send(response);
      },
      nullptr,
      [](AsyncWebServerRequest *request, uint8_t *data, size_t len, size_t index, size_t total) {
        if (len > 0) {
          JsonDocument doc;
          DeserializationError err = deserializeJson(doc, data, len);
          if (!err) {
            if (doc.containsKey("preset")) {
              String p = doc["preset"].as<String>();
              if (p == "text_screen") applyCameraPreset(CAM_PRESET_TEXT_SCREEN);
              else if (p == "outdoor") applyCameraPreset(CAM_PRESET_OUTDOOR);
              else if (p == "balanced") applyCameraPreset(CAM_PRESET_BALANCED);
            }
            if (doc.containsKey("ae_level")) {
              setCameraExposureCompensation(doc["ae_level"].as<int>());
            }
            if (doc.containsKey("quality")) {
              setCameraQuality(doc["quality"].as<int>());
            }
            if (doc.containsKey("framesize")) {
              setCameraResolution((framesize_t)doc["framesize"].as<int>());
            }
          }
        }
      }
  );

  httpServer.on("/capture", HTTP_GET, [](AsyncWebServerRequest *request) {
    // NOTA: sin esp_task_wdt_reset() aquí: el handler corre en el worker
    // async no suscrito al WDT; el watchdog real vive en loop().

    // Buffer estático en PSRAM: evita fragmentación por ps_malloc/free por petición
    static uint8_t *snapshotBuf = nullptr;
    static portMUX_TYPE snapMux = portMUX_INITIALIZER_UNLOCKED;
    static bool snapshotBusy = false;
    static unsigned long snapshotStart = 0;
    static uint8_t *snapshotDynBuf = nullptr;
    static const size_t MAX_SNAPSHOT_SIZE = 384 * 1024;
    if (snapshotBuf == nullptr && psramFound()) {
      snapshotBuf = (uint8_t *)ps_malloc(MAX_SNAPSHOT_SIZE);
    }

    portENTER_CRITICAL(&snapMux);
    if (snapshotBusy && (millis() - snapshotStart > 8000)) {
      snapshotBusy = false;
      if (snapshotDynBuf != nullptr) { free(snapshotDynBuf); snapshotDynBuf = nullptr; }
      portEXIT_CRITICAL(&snapMux);
      sysLog(SYS_LOG_WARN, "HTTP", "Forzado reinicio de snapshotBusy por timeout.");
    } else {
      portEXIT_CRITICAL(&snapMux);
    }
    portENTER_CRITICAL(&snapMux);
    bool busy = snapshotBusy;
    portEXIT_CRITICAL(&snapMux);
    if (busy) {
      AsyncWebServerResponse *busyResp = request->beginResponse(
          503, "application/json", "{\"error\":\"camera_streaming_busy\",\"status\":\"fail\"}");
      addCors(busyResp);
      request->send(busyResp);
      return;
    }

    if (request->hasParam("preset")) {
      String p = request->getParam("preset")->value();
      if (p == "text_screen") applyCameraPreset(CAM_PRESET_TEXT_SCREEN);
      else if (p == "outdoor") applyCameraPreset(CAM_PRESET_OUTDOOR);
      else if (p == "balanced") applyCameraPreset(CAM_PRESET_BALANCED);
    }
    if (request->hasParam("ae")) {
      int ae = request->getParam("ae")->value().toInt();
      setCameraExposureCompensation(ae);
    }

    // Descarte de 1 frame previo para asentar el AEC2 y capturar con exposición calibrada
    camera_fb_t *frame = captureFrame(1);
    if (frame == nullptr) {
      AsyncWebServerResponse *response = request->beginResponse(
          503, "application/json", "{\"error\":\"camera_busy_or_unavailable\",\"status\":\"fail\"}");
      addCors(response);
      request->send(response);
      return;
    }

    size_t imageLength = frame->len;
    uint8_t *targetBuf = snapshotBuf;
    bool dynamicBuf = false;
    if (targetBuf == nullptr || imageLength > MAX_SNAPSHOT_SIZE) {
      targetBuf = psramFound() ? (uint8_t *)ps_malloc(imageLength) : (uint8_t *)malloc(imageLength);
      dynamicBuf = true;
    }
    if (targetBuf == nullptr) {
      releaseFrame(frame);
      AsyncWebServerResponse *oom = request->beginResponse(
          500, "application/json", "{\"error\":\"oom_snapshot_buffer\"}");
      addCors(oom);
      request->send(oom);
      return;
    }

    memcpy(targetBuf, frame->buf, imageLength);
    releaseFrame(frame);

    portENTER_CRITICAL(&snapMux);
    if (snapshotBusy) {
      portEXIT_CRITICAL(&snapMux);
      if (dynamicBuf) free(targetBuf);
      AsyncWebServerResponse *race = request->beginResponse(
          503, "application/json", "{\"error\":\"camera_streaming_busy\",\"status\":\"fail\"}");
      addCors(race);
      request->send(race);
      return;
    }
    snapshotBusy = true;
    snapshotStart = millis();
    if (dynamicBuf) snapshotDynBuf = targetBuf;
    portEXIT_CRITICAL(&snapMux);

    AsyncWebServerResponse *response = request->beginResponse(
        "image/jpeg", imageLength,
        [targetBuf, imageLength, dynamicBuf, &snapMux, &snapshotBusy, &snapshotDynBuf](uint8_t *buffer, size_t maxLength, size_t index) -> size_t {
          if (index >= imageLength) return 0;
          size_t bytes = min(maxLength, imageLength - index);
          memcpy(buffer, targetBuf + index, bytes);
          if (index + bytes >= imageLength) {
            portENTER_CRITICAL(&snapMux);
            snapshotBusy = false;
            if (dynamicBuf) {
              free(targetBuf);
              if (snapshotDynBuf == targetBuf) snapshotDynBuf = nullptr;
            }
            portEXIT_CRITICAL(&snapMux);
          }
          return bytes;
        });
    addCors(response);
    // Si el cliente aborta, el callback de fin nunca llega: liberar busy+buf.
    request->onDisconnect([&snapMux, &snapshotBusy, &snapshotDynBuf]() {
      portENTER_CRITICAL(&snapMux);
      snapshotBusy = false;
      if (snapshotDynBuf != nullptr) { free(snapshotDynBuf); snapshotDynBuf = nullptr; }
      portEXIT_CRITICAL(&snapMux);
    });
    request->send(response);
  });

  httpServer.on("/beep", HTTP_GET, [](AsyncWebServerRequest *request) {
    scheduleBeep(880, 250);
    AsyncWebServerResponse *response = request->beginResponse(200, "text/plain", "Beep programado");
    addCors(response);
    request->send(response);
  });

  httpServer.on("/mic_sample", HTTP_GET, [](AsyncWebServerRequest *request) {
    // Buffer por-request con vida atada a la request (shared_ptr): se
    // libera exactamente una vez al completarse O al desconectar.
    // 1600 samples = 100ms @ 16kHz.
    std::shared_ptr<int16_t> microphoneBuffer(
        (int16_t *)malloc(1600 * sizeof(int16_t)), free);
    if (microphoneBuffer == nullptr) {
      AsyncWebServerResponse *oom = request->beginResponse(
          500, "application/json", "{\"error\":\"oom_mic_buffer\"}");
      addCors(oom);
      request->send(oom);
      return;
    }
    size_t samplesRead = readMicSamples(microphoneBuffer.get(), 1600, 250);
    if (samplesRead == 0) {
      AsyncWebServerResponse *response = request->beginResponse(
          503, "application/json", "{\"error\":\"mic_read_timeout\",\"status\":\"fail\"}");
      addCors(response);
      request->send(response);
      return;
    }

    const size_t len = samplesRead * sizeof(int16_t);
    AsyncWebServerResponse *response = request->beginResponse(
        "application/octet-stream",
        len,
        [microphoneBuffer, len](uint8_t *buffer, size_t maxLen, size_t index) -> size_t {
          if (index >= len) return 0;
          size_t chunk = min(maxLen, len - index);
          memcpy(buffer, ((uint8_t *)microphoneBuffer.get()) + index, chunk);
          return chunk;
        });
    addCors(response);
    request->onDisconnect([microphoneBuffer]() {});
    request->send(response);
  });
    addCors(response);
    request->onDisconnect([microphoneBuffer]() { free(microphoneBuffer); });
    request->send(response);
  });

  httpServer.on("/play_audio", HTTP_POST,
      [](AsyncWebServerRequest *request) {
        AsyncWebServerResponse *response = request->beginResponse(200, "application/json", "{\"status\":\"ok\"}");
        addCors(response);
        request->send(response);
      },
      nullptr,
      [](AsyncWebServerRequest *request, uint8_t *data, size_t len, size_t index, size_t total) {
        if (len > 0) {
          // Límite anti-HEAD-of-line: 256KB por request, chunks pares (s16le).
          if (total > 256 * 1024) {
            sysLog(SYS_LOG_WARN, "HTTP", "play_audio descartado: payload >256KB.");
            return;
          }
          if ((len % 2) != 0) len -= 1;
          if (len > 0) playAudioChunk(data, len);
        }
      }
  );

  httpServer.on("/camera_config", HTTP_POST,
      [](AsyncWebServerRequest *request) {
        AsyncWebServerResponse *response = request->beginResponse(200, "application/json", "{\"status\":\"ok\"}");
        addCors(response);
        request->send(response);
      },
      nullptr,
      [](AsyncWebServerRequest *request, uint8_t *data, size_t len, size_t index, size_t total) {
        JsonDocument document;
        if (deserializeJson(document, data, len)) return;
        sensor_t *sensor = esp_camera_sensor_get();
        if (sensor == nullptr) return;
        auto clampI = [](int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); };
        if (document["quality"].is<int>()) sensor->set_quality(sensor, clampI(document["quality"].as<int>(), 10, 63));
        if (document["brightness"].is<int>()) sensor->set_brightness(sensor, clampI(document["brightness"].as<int>(), -2, 2));
        if (document["contrast"].is<int>()) sensor->set_contrast(sensor, clampI(document["contrast"].as<int>(), -2, 2));
        if (document["saturation"].is<int>()) sensor->set_saturation(sensor, clampI(document["saturation"].as<int>(), -2, 2));
        if (document["sharpness"].is<int>()) sensor->set_sharpness(sensor, clampI(document["sharpness"].as<int>(), -2, 2));
      }
  );

  httpServer.on("/factory_reset", HTTP_POST,
      [](AsyncWebServerRequest *request) {
        Preferences prefs;
        prefs.begin("glasses_cfg", false);
        prefs.clear();
        prefs.end();
        AsyncWebServerResponse *response = request->beginResponse(
            200, "application/json", "{\"status\":\"factory_reset\",\"action\":\"rebooting\"}");
        addCors(response);
        request->send(response);
        scheduleRestart(600);
      }
  );

  httpServer.on("/reboot", HTTP_POST, [](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", "{\"status\":\"rebooting\"}");
    addCors(response);
    request->send(response);
    scheduleRestart(500);
  });

  httpServer.on("/update", HTTP_POST,
      [](AsyncWebServerRequest *request) {
        bool success = !Update.hasError();
        // Token opcional compatible: si NVS "ota_token" está vacío se permite
        // (1 prototipo); si está configurado se exige X-OTA-Token.
        bool authorized = true;
        {
          Preferences p; p.begin("glasses_cfg", true);
          String expected = p.getString("ota_token", "");
          p.end();
          if (expected.length() > 0) {
            authorized = request->hasHeader("X-OTA-Token") &&
                         request->header("X-OTA-Token") == expected;
          }
        }
        if (!authorized) {
          AsyncWebServerResponse *denied = request->beginResponse(401, "text/plain", "FAIL_AUTH");
          denied->addHeader("Connection", "close");
          addCors(denied);
          request->send(denied);
          Update.abort();
          return;
        }
        AsyncWebServerResponse *response = request->beginResponse(
            success ? 200 : 500, "text/plain", success ? "OK_UPDATE" : "FAIL_UPDATE");
        response->addHeader("Connection", "close");
        addCors(response);
        request->send(response);
        if (success) scheduleRestart(700);
      },
      [](AsyncWebServerRequest *request, String filename, size_t index, uint8_t *data, size_t len, bool final) {
        if (index == 0 && !Update.begin(UPDATE_SIZE_UNKNOWN)) Update.printError(Serial);
        if (!Update.hasError() && Update.write(data, len) != len) { Update.printError(Serial); Update.abort(); }
        if (final && !Update.end(true)) Update.printError(Serial);
      }
  );

  httpServer.begin();
  Serial.println("[HTTP OK] Servidor iniciado en el puerto 80.");
}

// ============================================================
// WATCHDOG
// ============================================================

void initWatchdog() {
#if ESP_IDF_VERSION_MAJOR >= 5
  esp_task_wdt_config_t config = {
      .timeout_ms = WDT_TIMEOUT_SECONDS * 1000,
      .idle_core_mask = (1 << portNUM_PROCESSORS) - 1,
      .trigger_panic = true
  };
  esp_task_wdt_reconfigure(&config);
#else
  esp_task_wdt_init(WDT_TIMEOUT_SECONDS, true);
#endif
  esp_task_wdt_add(nullptr);
}

// ============================================================
// SETUP
// ============================================================

void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.println();
  Serial.println("========================================");
  Serial.printf(" XIAO SmartGlasses - %s\n", FW_VERSION);
  Serial.println("========================================");

  pinMode(BATTERY_ADC_PIN, INPUT);
  analogSetAttenuation(ADC_11db); // Rango completo 0-3.3V, menor error en S3
  analogReadResolution(12);

  initCrashMonitoring();

  cameraReady = initCamera();
  microphoneReady = initMicrophone();
  speakerReady = initSpeaker();

  initBluetooth();

  WiFi.mode(WIFI_AP_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  // Canal AP fijo (6) para que los reintentos STA no fuercen saltos de canal.
  WiFi.softAP(SOFTAP_SSID, SOFTAP_PASS, 6);
  WiFi.onEvent([](WiFiEvent_t event, WiFiEventInfo_t info) {
    if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
      sysLogf(SYS_LOG_WARN, "WIFI", "STA desconectado (razon %u).", info.wifi_sta_disconnected.reason);
    }
  });
  Serial.printf("[WIFI AP] %s | clave: %s | IP: %s\n", SOFTAP_SSID, SOFTAP_PASS, WiFi.softAPIP().toString().c_str());

  initHttpServer();

  if (MDNS.begin("glasses")) {
    MDNS.addService("http", "tcp", 80);
    Serial.println("[mDNS] http://glasses.local");
  }

  loadCredentials();
  initWatchdog();
  scheduleBeep(520, 150);
  Serial.println("[SISTEMA] Preparado.");
}

// ============================================================
// LOOP
// ============================================================

void loop() {
  esp_task_wdt_reset();
  pollSystemControl();

  if (wifiShouldConnect) {
    wifiShouldConnect = false;
    wifiIsConnecting = true;
    wifiConnectStarted = millis();
    WiFi.begin(currentSSID.c_str(), currentPassword.c_str());
    Serial.printf("[WIFI] Conectando a %s...\n", currentSSID.c_str());
  }

  if (wifiIsConnecting) {
    if (WiFi.status() == WL_CONNECTED) {
      wifiIsConnecting = false;
      wifiReconnects++;
      sysLogf(SYS_LOG_INFO, "WIFI", "Conectado IP=%s (reconex #%u)", WiFi.localIP().toString().c_str(), wifiReconnects);
      Serial.printf("[WIFI OK] IP: %s\n", WiFi.localIP().toString().c_str());
      scheduleBeep(880, 180);
    } else if (millis() - wifiConnectStarted > 15000) {
      wifiIsConnecting = false;
      // Detener el escaneo en background para no desestabilizar SoftAP (evita saltos de canal)
      WiFi.disconnect(false);
      Serial.println("[WIFI] Timeout Station. Radio estabilizada en SoftAP (192.168.4.1).");
    }
  } else if (currentSSID.length() > 0 && WiFi.status() != WL_CONNECTED) {
    // Backoff: con cliente AP activo se reintenta cada 5min (antes:
    // starvation permanente) sin tumbar el SoftAP.
    bool apBusy = (WiFi.softAPgetStationNum() > 0);
    unsigned long interval = apBusy ? 300000UL : 60000UL;
    static uint8_t staFailStreak = 0;
    if (millis() - lastWifiRetry > interval) {
      lastWifiRetry = millis();
      if (staFailStreak < 5) staFailStreak++;
      wifiShouldConnect = true;
      sysLogf(SYS_LOG_INFO, "WIFI", "Reintento STA #%u (AP %s)...",
          staFailStreak, apBusy ? "ocupado" : "libre");
    }
  }

  // Baliza UDP en red Station (Hotspot móvil) para descubrimiento en <100ms
  sendUdpBeacon();

  if (bleConnected && statusCharacteristic != nullptr && millis() - lastTelemetry > 2000) {
    lastTelemetry = millis();
    // Notify corto (<100B) para MTU 23 por defecto; el /status completo va por HTTP.
    bool sta = (WiFi.status() == WL_CONNECTED);
    JsonDocument slim;
    slim["fw"] = FW_VERSION;
    slim["ip"] = sta ? WiFi.localIP().toString() : WiFi.softAPIP().toString();
    slim["b"] = batteryPercentFromVoltage(filteredVoltage);
    slim["c"] = cameraReady && cameraFailures < 3;
    slim["r"] = sta ? WiFi.RSSI() : 0;
    String status;
    serializeJson(slim, status);
    statusCharacteristic->setValue(status.c_str());
    statusCharacteristic->notify();
  }

  delay(20);
}
