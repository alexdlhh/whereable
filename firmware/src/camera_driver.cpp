#include "camera_driver.h"
#include "config.h"
#include "system_control.h"
#include <ArduinoJson.h>
#include <esp_task_wdt.h>

SemaphoreHandle_t CameraDriver::cameraMutex = nullptr;
bool CameraDriver::initialized = false;
uint32_t CameraDriver::consecutiveFailures = 0;
uint32_t CameraDriver::totalFramesCaptured = 0;
uint32_t CameraDriver::totalCorruptFrames = 0;
CameraPreset CameraDriver::currentPreset = CAM_PRESET_TEXT_SCREEN;
int CameraDriver::currentAeLevel = -2;
framesize_t CameraDriver::currentFramesize = FRAMESIZE_UXGA;

bool CameraDriver::initCamera() {
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
    config.jpeg_quality = 10; // Alta fidelidad JPEG
    config.fb_count = 2;

    if (!psramFound()) {
        Serial.println("[CAM ERROR] PSRAM no detectada. Reduciendo a VGA.");
        config.frame_size = FRAMESIZE_VGA;
        config.fb_location = CAMERA_FB_IN_DRAM;
        config.fb_count = 1;
        config.jpeg_quality = 14;
        currentFramesize = FRAMESIZE_VGA;
    } else {
        currentFramesize = FRAMESIZE_UXGA;
    }

    esp_err_t err = esp_camera_init(&config);
    if (err != ESP_OK) {
        // Fallback a SXGA si UXGA falla por memoria fragmentada
        if (psramFound() && config.frame_size == FRAMESIZE_UXGA) {
            Serial.printf("[CAM WARN] UXGA fallo (0x%x). Intentando SXGA (1280x1024)...\n", err);
            config.frame_size = FRAMESIZE_SXGA;
            config.jpeg_quality = 12;
            currentFramesize = FRAMESIZE_SXGA;
            err = esp_camera_init(&config);
        }
    }

    if (err != ESP_OK) {
        Serial.printf("[CAM ERROR] Fallo inicializando camara: 0x%x\n", err);
        initialized = false;
        if (cameraMutex != nullptr) xSemaphoreGive(cameraMutex);
        return false;
    }

    sensor_t* s = esp_camera_sensor_get();
    if (s != nullptr) {
        // Iniciar con preset de texto/pantallas optimizado para OV3660/OV5640
        applyPreset(CAM_PRESET_TEXT_SCREEN);
    }

    initialized = true;
    consecutiveFailures = 0;
    if (cameraMutex != nullptr) xSemaphoreGive(cameraMutex);

    Serial.println("[CAM OK] Camara inicializada (UXGA/DSP AEC2 calibrado) y protegida por Mutex.");
    return true;
}

bool CameraDriver::applyPreset(CameraPreset preset) {
    // Thread-safe: los handlers HTTP async llaman sin mutex. Timeout corto
    // para no bloquear /capture en curso; el cliente puede reintentar.
    bool locked = false;
    if (cameraMutex != nullptr) {
        if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(300)) != pdTRUE) {
            SystemControl::log(SYS_LOG_WARN, "CAM", "Preset descartado: camara ocupada.");
            return false;
        }
        locked = true;
    }
    sensor_t* s = esp_camera_sensor_get();
    if (s == nullptr) { if (locked) xSemaphoreGive(cameraMutex); return false; }

    currentPreset = preset;
    switch (preset) {
        case CAM_PRESET_TEXT_SCREEN:
            // Modo Pantallas & Lectura de Texto:
            // Algoritmo AEC2 basado en histograma (evita saturación en monitores/altas luces)
            s->set_brightness(s, 0);              // Brillo neutral (no inflar blancos)
            s->set_contrast(s, 2);                // Alto contraste para bordes de texto nítidos
            s->set_saturation(s, -1);             // Menor aberración cromática en caracteres
            s->set_sharpness(s, 2);               // Máxima nitidez por DSP (compensa lente fija a 40-60cm)
            s->set_whitebal(s, 1);                // AWB activo
            s->set_awb_gain(s, 1);
            s->set_wb_mode(s, 0);                 // AWB automático
            s->set_aec2(s, 1);                    // Activar DSP AEC2 avanzado
            s->set_ae_level(s, -2);               // Compensación de exposición -2 (elimina pantalla quemada en blanco)
            s->set_gainceiling(s, GAINCEILING_2X);// Limitar ganancia para evitar ruido y sobreexposición
            s->set_bpc(s, 1);                     // Corrección de píxeles negros
            s->set_wpc(s, 1);                     // Corrección de píxeles blancos saturados
            s->set_raw_gma(s, 1);                 // Curva gamma activa
            s->set_lenc(s, 1);                    // Corrección de viñeteado de lente
            currentAeLevel = -2;
            Serial.println("[CAM PRESET] Aplicado: TEXT_SCREEN (AEC2 on, AE=-2, Sharpness=2, Contrast=2)");
            break;

        case CAM_PRESET_OUTDOOR:
            s->set_brightness(s, 0);
            s->set_contrast(s, 1);
            s->set_saturation(s, 1);
            s->set_sharpness(s, 1);
            s->set_whitebal(s, 1);
            s->set_awb_gain(s, 1);
            s->set_wb_mode(s, 0);
            s->set_aec2(s, 1);
            s->set_ae_level(s, -1);
            s->set_gainceiling(s, GAINCEILING_4X);
            s->set_bpc(s, 1);
            s->set_wpc(s, 1);
            s->set_raw_gma(s, 1);
            s->set_lenc(s, 1);
            currentAeLevel = -1;
            Serial.println("[CAM PRESET] Aplicado: OUTDOOR (AE=-1, Saturation=1)");
            break;

        case CAM_PRESET_BALANCED:
        default:
            s->set_brightness(s, 0);
            s->set_contrast(s, 1);
            s->set_saturation(s, 0);
            s->set_sharpness(s, 1);
            s->set_whitebal(s, 1);
            s->set_awb_gain(s, 1);
            s->set_wb_mode(s, 0);
            s->set_aec2(s, 1);
            s->set_ae_level(s, 0);
            s->set_gainceiling(s, GAINCEILING_4X);
            s->set_bpc(s, 1);
            s->set_wpc(s, 1);
            s->set_raw_gma(s, 1);
            s->set_lenc(s, 1);
            currentAeLevel = 0;
            Serial.println("[CAM PRESET] Aplicado: BALANCED (AE=0)");
            break;
    }
    if (locked) xSemaphoreGive(cameraMutex);
    return true;
}

bool CameraDriver::setExposureCompensation(int level) {
    bool locked = false;
    if (cameraMutex != nullptr) {
        if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(300)) != pdTRUE) return false;
        locked = true;
    }
    sensor_t* s = esp_camera_sensor_get();
    if (s == nullptr) { if (locked) xSemaphoreGive(cameraMutex); return false; }
    if (level < -2) level = -2;
    if (level > 2) level = 2;
    s->set_ae_level(s, level);
    currentAeLevel = level;
    Serial.printf("[CAM] Compensacion de exposicion establecida a %d\n", level);
    if (locked) xSemaphoreGive(cameraMutex);
    return true;
}

bool CameraDriver::setResolution(framesize_t frameSize) {
    if ((int)frameSize < 0 || (int)frameSize > 22) return false;
    bool locked = false;
    if (cameraMutex != nullptr) {
        if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(300)) != pdTRUE) return false;
        locked = true;
    }
    sensor_t* s = esp_camera_sensor_get();
    if (s == nullptr) { if (locked) xSemaphoreGive(cameraMutex); return false; }
    bool ok = (s->set_framesize(s, frameSize) == 0);
    if (ok) {
        currentFramesize = frameSize;
        Serial.printf("[CAM] Resolucion cambiada a framesize=%d\n", (int)frameSize);
    }
    if (locked) xSemaphoreGive(cameraMutex);
    return ok;
}

bool CameraDriver::setQuality(int quality) {
    bool locked = false;
    if (cameraMutex != nullptr) {
        if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(300)) != pdTRUE) return false;
        locked = true;
    }
    sensor_t* s = esp_camera_sensor_get();
    if (s == nullptr) { if (locked) xSemaphoreGive(cameraMutex); return false; }
    if (quality < 10) quality = 10;
    if (quality > 63) quality = 63;
    s->set_quality(s, quality);
    Serial.printf("[CAM] Calidad JPEG cambiada a %d\n", quality);
    if (locked) xSemaphoreGive(cameraMutex);
    return true;
}

String CameraDriver::getCurrentSettingsJson() {
    JsonDocument doc;
    doc["preset"] = (currentPreset == CAM_PRESET_TEXT_SCREEN) ? "text_screen" :
                    (currentPreset == CAM_PRESET_OUTDOOR) ? "outdoor" : "balanced";
    doc["ae_level"] = currentAeLevel;
    doc["framesize"] = (int)currentFramesize;
    doc["operational"] = isOperational();
    doc["failures"] = consecutiveFailures;
    String out;
    serializeJson(doc, out);
    return out;
}

bool CameraDriver::resetCamera() {
    // Nunca bloquear con portMAX_DELAY: puede llamarse tras liberar el mutex
    // desde captureFrame. Usa timeout corto y deja que initCamera re-tome.
    Serial.println("[CAM WARN] Reinicializando driver de camara...");
    if (cameraMutex != nullptr) {
        if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(500)) != pdTRUE) {
            SystemControl::log(SYS_LOG_WARN, "CAM", "Reset diferido: mutex ocupado.");
            return false;
        }
        xSemaphoreGive(cameraMutex);
    }
    esp_camera_deinit();
    initialized = false;
    delay(100);
    return initCamera();
}

bool CameraDriver::isValidJpeg(const uint8_t* buf, size_t len) {
    if (!buf || len < 4) return false;
    return (buf[0] == 0xFF && buf[1] == 0xD8 &&
            buf[len - 2] == 0xFF && buf[len - 1] == 0xD9);
}

camera_fb_t* CameraDriver::captureFrame(int preDropFrames) {
    esp_task_wdt_reset();

    if (!initialized) {
        if (!initCamera()) return nullptr;
    }

    if (cameraMutex != nullptr) {
        if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(5000)) != pdTRUE) {
            SystemControl::log(SYS_LOG_WARN, "CAM", "Mutex ocupado al capturar frame.");
            return nullptr;
        }
    }

    esp_task_wdt_reset();

    // Pre-descarte de fotogramas residuales para que el bucle AEC/AGC se asiente a la iluminación actual
    for (int i = 0; i < preDropFrames; i++) {
        camera_fb_t* dropFb = esp_camera_fb_get();
        if (dropFb) {
            esp_camera_fb_return(dropFb);
        }
    }

    camera_fb_t* fb = esp_camera_fb_get();

    if (!fb) {
        consecutiveFailures++;
        SystemControl::camCapturesCorrupt++;
        SystemControl::logf(SYS_LOG_WARN, "CAM", "Fallo al capturar frame (%u fallos consecutivos)", consecutiveFailures);
        if (cameraMutex != nullptr) xSemaphoreGive(cameraMutex);
        if (consecutiveFailures >= 3) {
            resetCamera();
        }
        return nullptr;
    }

    // Validar integridad estructural del frame JPEG (SOI 0xFFD8 y EOI 0xFFD9)
    if (!isValidJpeg(fb->buf, fb->len)) {
        totalCorruptFrames++;
        SystemControl::camCapturesCorrupt++;
        SystemControl::logf(SYS_LOG_WARN, "CAM", "Frame JPEG corrupto detectado (%u bytes). Descartando.", fb->len);
        esp_camera_fb_return(fb);

        // Reintento único inmediato para salvar la solicitud
        fb = esp_camera_fb_get();
        if (!fb || !isValidJpeg(fb->buf, fb->len)) {
            if (fb) esp_camera_fb_return(fb);
            consecutiveFailures++;
            bool needReset = (consecutiveFailures >= 3);
            if (cameraMutex != nullptr) xSemaphoreGive(cameraMutex);
            if (needReset) resetCamera();
            return nullptr;
        }
    }

    consecutiveFailures = 0;
    totalFramesCaptured++;
    SystemControl::camCapturesTotal++;
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

uint32_t CameraDriver::totalCaptures() {
    return totalFramesCaptured;
}

uint32_t CameraDriver::corruptCount() {
    return totalCorruptFrames;
}
