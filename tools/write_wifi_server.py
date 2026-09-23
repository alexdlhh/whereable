# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "firmware" / "src" / "wifi_server.cpp"
ini = ROOT / "firmware" / "platformio.ini"

WIFI = r'''#include "wifi_server.h"
#include "camera_driver.h"
#include "audio_driver.h"
#include "config.h"
#include "fw_version.h"
#include "battery_utils.h"
#include "system_control.h"
#include <ArduinoJson.h>
#include <Update.h>
#include <Preferences.h>

AsyncWebServer WiFiServerManager::server(80);

static void addCors(AsyncWebServerResponse* response) {
    response->addHeader("Access-Control-Allow-Origin", "*");
    response->addHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
    response->addHeader("Access-Control-Allow-Headers", "Content-Type");
    response->addHeader("Cache-Control", "no-store");
}

static String statusJson() {
    JsonDocument doc;
    bool isSta = (WiFi.status() == WL_CONNECTED);
    int rawAdc = analogRead(BATTERY_ADC_PIN);
    float vBat = batteryVoltageFromAdc(rawAdc);
    doc["status"] = "online";
    doc["fw"] = FW_VERSION;
    doc["ip"] = isSta ? WiFi.localIP().toString() : WiFi.softAPIP().toString();
    doc["sta_ip"] = WiFi.localIP().toString();
    doc["ap_ip"] = WiFi.softAPIP().toString();
    doc["mode"] = isSta ? "STA" : "AP";
    doc["rssi"] = isSta ? WiFi.RSSI() : 0;
    doc["free_heap"] = ESP.getFreeHeap();
    doc["free_psram"] = ESP.getFreePsram();
    doc["uptime_sec"] = millis() / 1000;
    doc["camera_ok"] = CameraDriver::isOperational();
    doc["camera_failures"] = CameraDriver::failureCount();
    doc["battery_voltage"] = vBat;
    doc["battery_pct"] = batteryPercentFromVoltage(vBat);
    doc["wdt_sec"] = WDT_TIMEOUT_SECONDS;
    String response;
    serializeJson(doc, response);
    return response;
}

void WiFiServerManager::initServer() {
    server.onNotFound([](AsyncWebServerRequest* request) {
        if (request->method() == HTTP_OPTIONS) {
            AsyncWebServerResponse* response = request->beginResponse(204);
            addCors(response);
            request->send(response);
            return;
        }
        request->send(404, "application/json", "{\"error\":\"not_found\"}");
    });

    server.on("/", HTTP_GET, [](AsyncWebServerRequest* request) {
        JsonDocument doc;
        doc["name"] = "XIAO-SmartGlasses";
        doc["fw"] = FW_VERSION;
        doc["health"] = "/health";
        doc["capture"] = "/capture";
        doc["status"] = "/status";
        String body;
        serializeJson(doc, body);
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", body);
        addCors(response);
        request->send(response);
    });

    server.on("/health", HTTP_GET, [](AsyncWebServerRequest* request) {
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", "{\"ok\":true}");
        addCors(response);
        request->send(response);
    });

    server.on("/status", HTTP_GET, [](AsyncWebServerRequest* request) {
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", statusJson());
        addCors(response);
        request->send(response);
    });

    server.on("/selftest", HTTP_GET, [](AsyncWebServerRequest* request) {
        JsonDocument doc;
        doc["fw"] = FW_VERSION;
        doc["camera"] = CameraDriver::isOperational();
        doc["psram"] = ESP.getFreePsram();
        doc["heap"] = ESP.getFreeHeap();
        doc["speaker"] = "beep_queued";
        String body;
        serializeJson(doc, body);
        SystemControl::scheduleBeep(880, 180);
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", body);
        addCors(response);
        request->send(response);
    });

    server.on("/capture", HTTP_GET, [](AsyncWebServerRequest* request) {
        camera_fb_t* fb = CameraDriver::captureFrame();
        if (!fb) {
            AsyncWebServerResponse* response = request->beginResponse(
                503, "application/json", "{\"error\":\"camera_busy_or_unavailable\",\"status\":\"fail\"}");
            addCors(response);
            request->send(response);
            return;
        }

        AsyncWebServerResponse* response = request->beginResponse_P(
            200, "image/jpeg", fb->buf, fb->len
        );
        addCors(response);
        request->send(response);
        CameraDriver::releaseFrame(fb);
    });

    server.on("/play_audio", HTTP_POST,
        [](AsyncWebServerRequest *request) {
            AsyncWebServerResponse* response = request->beginResponse(200, "application/json", "{\"status\":\"ok\"}");
            addCors(response);
            request->send(response);
        },
        NULL,
        [](AsyncWebServerRequest *request, uint8_t *data, size_t len, size_t index, size_t total) {
            if (len > 0) {
                AudioDriver::playAudioChunk(data, len);
            }
        }
    );

    server.on("/beep", HTTP_GET, [](AsyncWebServerRequest* request) {
        SystemControl::scheduleBeep(880, 250);
        AsyncWebServerResponse* response = request->beginResponse(200, "text/plain", "Beep ejecutado");
        addCors(response);
        request->send(response);
    });

    server.on("/mic_sample", HTTP_GET, [](AsyncWebServerRequest* request) {
        const size_t samples = 8000;
        int16_t* buf = (int16_t*)malloc(samples * sizeof(int16_t));
        if (!buf) {
            request->send(500, "application/json", "{\"error\":\"oom\"}");
            return;
        }
        size_t got = AudioDriver::readMicSamples(buf, samples);
        AsyncWebServerResponse* response = request->beginResponse_P(
            200, "application/octet-stream", (uint8_t*)buf, got * sizeof(int16_t));
        addCors(response);
        request->send(response);
        free(buf);
    });

    server.on("/camera_config", HTTP_POST,
        [](AsyncWebServerRequest* request) {
            AsyncWebServerResponse* response = request->beginResponse(200, "application/json", "{\"status\":\"ok\"}");
            addCors(response);
            request->send(response);
        },
        NULL,
        [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t index, size_t total) {
            JsonDocument doc;
            DeserializationError err = deserializeJson(doc, data, len);
            if (!err) {
                sensor_t* s = esp_camera_sensor_get();
                if (s != nullptr) {
                    if (doc["quality"].is<int>()) s->set_quality(s, doc["quality"].as<int>());
                    if (doc["brightness"].is<int>()) s->set_brightness(s, doc["brightness"].as<int>());
                    if (doc["contrast"].is<int>()) s->set_contrast(s, doc["contrast"].as<int>());
                    if (doc["saturation"].is<int>()) s->set_saturation(s, doc["saturation"].as<int>());
                    if (doc["sharpness"].is<int>()) s->set_sharpness(s, doc["sharpness"].as<int>());
                }
            }
        }
    );

    server.on("/factory_reset", HTTP_POST, [](AsyncWebServerRequest* request) {
        Serial.println("[SYSTEM] Factory Reset.");
        Preferences prefs;
        prefs.begin("glasses_cfg", false);
        prefs.clear();
        prefs.end();
        AsyncWebServerResponse* response = request->beginResponse(
            200, "application/json", "{\"status\":\"factory_reset_completed\",\"action\":\"rebooting\"}");
        addCors(response);
        request->send(response);
        SystemControl::scheduleRestart(500);
    });

    server.on("/reboot", HTTP_POST, [](AsyncWebServerRequest* request) {
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", "{\"status\":\"rebooting\"}");
        addCors(response);
        request->send(response);
        SystemControl::scheduleRestart(400);
    });

    server.on("/update", HTTP_POST,
        [](AsyncWebServerRequest* request) {
            bool shouldReboot = !Update.hasError();
            AsyncWebServerResponse* response = request->beginResponse(
                200, "text/plain", shouldReboot ? "OK_UPDATE" : "FAIL_UPDATE"
            );
            response->addHeader("Connection", "close");
            addCors(response);
            request->send(response);
            if (shouldReboot) {
                SystemControl::scheduleRestart(600);
            }
        },
        [](AsyncWebServerRequest* request, String filename, size_t index, uint8_t* data, size_t len, bool final) {
            if (!index) {
                Serial.printf("[OTA] Inicio: %s\n", filename.c_str());
                if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
                    Update.printError(Serial);
                }
            }
            if (!Update.hasError()) {
                if (Update.write(data, len) != len) {
                    Update.printError(Serial);
                }
            }
            if (final) {
                if (Update.end(true)) {
                    Serial.printf("[OTA OK] %u bytes.\n", index + len);
                } else {
                    Update.printError(Serial);
                }
            }
        }
    );

    server.begin();
    Serial.println("[HTTP SERVER OK] API resiliente con OTA en puerto 80.");
}
'''

INI = r'''; PlatformIO Project Configuration File for Seeed Studio XIAO ESP32S3 Sense

[env:seeed_xiao_esp32s3]
platform = espressif32
board = seeed_xiao_esp32s3
framework = arduino

board_build.arduino.memory_type = qio_opi
board_build.partitions = default_8MB.csv

monitor_speed = 115200
upload_speed = 921600

build_flags =
    -DBOARD_HAS_PSRAM
    -mfix-esp32-psram-cache-issue
    -DCONFIG_SPIRAM_CACHE_WORKAROUND
    -DCORE_DEBUG_LEVEL=3

lib_deps =
    espressif/esp32-camera @ ^2.0.4
    bblanchon/ArduinoJson @ ^7.0.4
    me-no-dev/ESP Async WebServer @ ^1.2.4
    me-no-dev/AsyncTCP @ ^1.1.1

; pio test -e native
[env:native]
platform = native
test_framework = unity
build_src_filter = -<*>
'''

path.write_text(WIFI.replace('\r\n', '\n'), encoding='utf-8')
ini.write_text(INI.replace('\r\n', '\n'), encoding='utf-8')
print('wrote wifi_server.cpp and platformio.ini')
