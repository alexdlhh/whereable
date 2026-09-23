# -*- coding: utf-8 -*-
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "firmware" / "src"

FILES = {}

FILES["config.h"] = r'''#pragma once

#include <Arduino.h>
#include "fw_version.h"

// ==========================================
// 1. PINOUT DE CÁMARA (XIAO ESP32S3 SENSE)
// Conector FPC integrado en la placa superior
// ==========================================
#define PWDN_GPIO_NUM     -1
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM     10
#define SIOD_GPIO_NUM     40
#define SIOC_GPIO_NUM     39

#define Y9_GPIO_NUM       48
#define Y8_GPIO_NUM       11
#define Y7_GPIO_NUM       12
#define Y6_GPIO_NUM       14
#define Y5_GPIO_NUM       16
#define Y4_GPIO_NUM       18
#define Y3_GPIO_NUM       17
#define Y2_GPIO_NUM       15
#define VSYNC_GPIO_NUM    38
#define HREF_GPIO_NUM     47
#define PCLK_GPIO_NUM     13

// ==========================================
// 2. PINOUT MICRÓFONO PDM (INTEGRADO EN PLACA)
// ==========================================
#define PDM_CLK_PIN       42
#define PDM_DATA_PIN      41

// ==========================================
// 3. PINOUT ALTAVOZ I2S EXTERNO (MAX98357A / DAC)
// Conexión a la patilla de las gafas
// ==========================================
#define I2S_SPK_BCLK      GPIO_NUM_7
#define I2S_SPK_LRCK      GPIO_NUM_8
#define I2S_SPK_DOUT      GPIO_NUM_9

// ==========================================
// 4. MONITORIZACIÓN DE BATERÍA (PIN ADC)
// ==========================================
#define BATTERY_ADC_PIN   1

// ==========================================
// 5. RED WI-FI SOFTAP FALLBACK
// ==========================================
#define SOFTAP_SSID       "XIAO-Glasses-AP"
#define SOFTAP_PASS       "12345678"

// ==========================================
// 6. IDENTIFICADORES BLE (GATT UUIDs)
// ==========================================
#define SERVICE_UUID            "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define WIFI_CONFIG_CHAR_UUID   "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define DEVICE_STATUS_CHAR_UUID "8b1b22e1-4547-497b-83a3-6b746a5996b7"

#define BLE_DEVICE_NAME         "XIAO-SmartGlasses"
'''

FILES["camera_driver.h"] = r'''#pragma once

#include "esp_camera.h"
#include <Arduino.h>
#include <freertos/semphr.h>

class CameraDriver {
public:
    static bool initCamera();
    static camera_fb_t* captureFrame();
    static void releaseFrame(camera_fb_t* fb);
    static bool resetCamera();
    static bool isOperational();
    static uint32_t failureCount();

private:
    static SemaphoreHandle_t cameraMutex;
    static bool initialized;
    static uint32_t consecutiveFailures;
};
'''

def main():
    for name, content in FILES.items():
        path = SRC / name
        path.write_text(content.replace('\r\n', '\n'), encoding='utf-8')
        print(f'wrote {path}')

if __name__ == '__main__':
    main()
