#include "wifi_server.h"
#include "camera_driver.h"
#include "audio_driver.h"
#include "config.h"
#include "fw_version.h"
#include "battery_utils.h"
#include "system_control.h"
#include <ArduinoJson.h>
#include <Update.h>
#include <Preferences.h>
#include <esp_task_wdt.h>
#include <memory>

AsyncWebServer WiFiServerManager::server(80);
WiFiUDP WiFiServerManager::udp;
unsigned long WiFiServerManager::lastUdpBeaconTime = 0;

static const size_t MAX_SNAPSHOT_BUF_SIZE = 384 * 1024; // 384 KB en PSRAM
static uint8_t* s_snapshotBuf = nullptr;
static portMUX_TYPE s_snapMux = portMUX_INITIALIZER_UNLOCKED;
static bool s_snapshotBusy = false;
static unsigned long s_snapshotStartTime = 0;
static uint8_t* s_snapshotDynBuf = nullptr;

static bool snapTryBusy() {
    bool ok = false;
    portENTER_CRITICAL(&s_snapMux);
    if (!s_snapshotBusy) { s_snapshotBusy = true; s_snapshotStartTime = millis(); ok = true; }
    portEXIT_CRITICAL(&s_snapMux);
    return ok;
}
static void snapRelease() {
    portENTER_CRITICAL(&s_snapMux);
    s_snapshotBusy = false;
    portEXIT_CRITICAL(&s_snapMux);
}
static bool snapIsBusy() {
    bool b; portENTER_CRITICAL(&s_snapMux); b = s_snapshotBusy; portEXIT_CRITICAL(&s_snapMux); return b;
}
static void snapForceResetIfStuck() {
    portENTER_CRITICAL(&s_snapMux);
    if (s_snapshotBusy && (millis() - s_snapshotStartTime > 8000)) {
        s_snapshotBusy = false;
        if (s_snapshotDynBuf) { free(s_snapshotDynBuf); s_snapshotDynBuf = nullptr; }
        portEXIT_CRITICAL(&s_snapMux);
        SystemControl::log(SYS_LOG_WARN, "HTTP", "Forzado reinicio de s_snapshotBusy por timeout de cliente.");
        return;
    }
    portEXIT_CRITICAL(&s_snapMux);
}

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
    float filteredVBat = SystemControl::updateAndGetBatteryVoltage(vBat);

    doc["status"] = "online";
    doc["fw"] = FW_VERSION;
    doc["ip"] = isSta ? WiFi.localIP().toString() : WiFi.softAPIP().toString();
    doc["sta_ip"] = WiFi.localIP().toString();
    doc["ap_ip"] = WiFi.softAPIP().toString();
    doc["mode"] = isSta ? "STA" : "AP";
    doc["rssi"] = isSta ? WiFi.RSSI() : 0;
    doc["free_heap"] = ESP.getFreeHeap();
    doc["free_psram"] = ESP.getFreePsram();
    doc["heap_frag_pct"] = SystemControl::getHeapFragmentation();
    doc["uptime_sec"] = millis() / 1000;
    doc["camera_ok"] = CameraDriver::isOperational();
    doc["camera_failures"] = CameraDriver::failureCount();
    doc["camera_captures"] = CameraDriver::totalCaptures();
    doc["camera_corrupt"] = CameraDriver::corruptCount();
    doc["wifi_reconnects"] = SystemControl::wifiReconnects;
    doc["i2s_mic_errors"] = SystemControl::i2sMicErrors;
    doc["i2s_spk_errors"] = SystemControl::i2sSpkErrors;
    doc["battery_voltage"] = filteredVBat;
    doc["battery_raw_voltage"] = vBat;
    doc["battery_pct"] = batteryPercentFromVoltage(filteredVBat);
    doc["wdt_sec"] = WDT_TIMEOUT_SECONDS;
    String response;
    serializeJson(doc, response);
    return response;
}

void WiFiServerManager::initServer() {
    if (s_snapshotBuf == nullptr && psramFound()) {
        s_snapshotBuf = (uint8_t*)ps_malloc(MAX_SNAPSHOT_BUF_SIZE);
        if (s_snapshotBuf) {
            SystemControl::logf(SYS_LOG_INFO, "CAM", "Buffer estatico snapshot reservado en PSRAM (%u KB).", MAX_SNAPSHOT_BUF_SIZE / 1024);
        }
    }

    server.onNotFound([](AsyncWebServerRequest* request) {
        if (request->method() == HTTP_OPTIONS) {
            AsyncWebServerResponse* response = request->beginResponse(204);
            addCors(response);
            request->send(response);
            return;
        }
        AsyncWebServerResponse* response = request->beginResponse(404, "application/json", "{\"error\":\"not_found\"}");
        addCors(response);
        request->send(response);
    });

    server.on("/", HTTP_GET, [](AsyncWebServerRequest* request) {
        JsonDocument doc;
        doc["name"] = "XIAO-SmartGlasses";
        doc["fw"] = FW_VERSION;
        doc["health"] = "/health";
        doc["capture"] = "/capture";
        doc["status"] = "/status";
        doc["logs"] = "/logs";
        doc["crash_log"] = "/crash_log";
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

    server.on("/logs", HTTP_GET, [](AsyncWebServerRequest* request) {
        int limit = 50;
        int minLevel = 0;
        if (request->hasParam("limit")) {
            limit = request->getParam("limit")->value().toInt();
        }
        if (request->hasParam("level")) {
            String lvl = request->getParam("level")->value();
            if (lvl == "info") minLevel = SYS_LOG_INFO;
            else if (lvl == "warn") minLevel = SYS_LOG_WARN;
            else if (lvl == "error") minLevel = SYS_LOG_ERROR;
        }
        String body = SystemControl::getLogsJson(limit, minLevel);
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", body);
        addCors(response);
        request->send(response);
    });

    server.on("/logs/clear", HTTP_POST, [](AsyncWebServerRequest* request) {
        SystemControl::clearLogs();
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", "{\"status\":\"logs_cleared\"}");
        addCors(response);
        request->send(response);
    });

    server.on("/crash_log", HTTP_GET, [](AsyncWebServerRequest* request) {
        String body = SystemControl::getCrashLogJson();
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", body);
        addCors(response);
        request->send(response);
    });

    server.on("/crash_log/clear", HTTP_POST, [](AsyncWebServerRequest* request) {
        SystemControl::clearCrashLog();
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", "{\"status\":\"crash_log_cleared\"}");
        addCors(response);
        request->send(response);
    });

    server.on("/network_stats", HTTP_GET, [](AsyncWebServerRequest* request) {
        JsonDocument doc;
        bool isSta = (WiFi.status() == WL_CONNECTED);
        doc["sta_connected"] = isSta;
        doc["mode"] = isSta ? "STA" : "AP";
        doc["sta_ip"] = WiFi.localIP().toString();
        doc["ap_ip"] = WiFi.softAPIP().toString();
        doc["sta_rssi"] = isSta ? WiFi.RSSI() : 0;
        doc["sta_reconnects"] = SystemControl::wifiReconnects;
        doc["ap_stations"] = WiFi.softAPgetStationNum();
        doc["udp_beacon_interval_ms"] = UDP_BEACON_INTERVAL_MS;
        String body;
        serializeJson(doc, body);
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", body);
        addCors(response);
        request->send(response);
    });

    server.on("/selftest", HTTP_GET, [](AsyncWebServerRequest* request) {
        JsonDocument doc;
        doc["fw"] = FW_VERSION;
        doc["camera"] = CameraDriver::isOperational();
        doc["psram"] = ESP.getFreePsram();
        doc["heap"] = ESP.getFreeHeap();
        doc["heap_frag_pct"] = SystemControl::getHeapFragmentation();
        // GET idempotente por defecto: ?beep=1 mantiene compat con clientes
        // antiguos que esperan pitido; ?beep=0 lo omite.
        bool wantBeep = true;
        if (request->hasParam("beep")) {
            String v = request->getParam("beep")->value();
            v.toLowerCase();
            if (v == "0" || v == "no" || v == "false" || v == "off") wantBeep = false;
        }
        doc["speaker"] = wantBeep ? "beep_queued" : "beep_skipped";
        doc["mic_errors"] = AudioDriver::micReadErrors();
        doc["speaker_errors"] = AudioDriver::speakerErrors();
        String body;
        serializeJson(doc, body);
        if (wantBeep) SystemControl::scheduleBeep(880, 180);
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", body);
        addCors(response);
        request->send(response);
    });

    // Diagnóstico unificado (aditivo, no rompe /status): heap+PSRAM, reset, RSSI.
    server.on("/diag", HTTP_GET, [](AsyncWebServerRequest* request) {
        JsonDocument doc;
        bool isSta = (WiFi.status() == WL_CONNECTED);
        doc["fw"] = FW_VERSION;
        doc["uptime_sec"] = millis() / 1000;
        doc["reset_reason"] = (int)esp_reset_reason();
        doc["free_heap"] = ESP.getFreeHeap();
        doc["free_psram"] = ESP.getFreePsram();
        doc["heap_frag_pct"] = SystemControl::getHeapFragmentation();
        size_t psramFree = ESP.getFreePsram();
        size_t psramMax = heap_caps_get_largest_free_block(MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
        doc["psram_frag_pct"] = (psramFree == 0) ? 100 : (psramMax >= psramFree ? 0 : 100 - (psramMax * 100 / psramFree));
        doc["rssi"] = isSta ? WiFi.RSSI() : 0;
        doc["mode"] = isSta ? "STA" : "AP";
        doc["camera_ok"] = CameraDriver::isOperational();
        doc["battery_pct"] = batteryPercentFromVoltage(SystemControl::getFilteredBatteryVoltage());
        String body;
        serializeJson(doc, body);
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", body);
        addCors(response);
        request->send(response);
    });

    // Endpoint de lectura de configuración de cámara
    server.on("/camera_settings", HTTP_GET, [](AsyncWebServerRequest* request) {
        String body = CameraDriver::getCurrentSettingsJson();
        AsyncWebServerResponse* response = request->beginResponse(200, "application/json", body);
        addCors(response);
        request->send(response);
    });

    // Endpoint de ajuste dinámico de cámara (presets, exposición, calidad)
    server.on("/camera_settings", HTTP_POST,
        [](AsyncWebServerRequest* request) {
            AsyncWebServerResponse* response = request->beginResponse(200, "application/json", "{\"status\":\"ok\"}");
            addCors(response);
            request->send(response);
        },
        NULL,
        [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t index, size_t total) {
            if (len > 0) {
                JsonDocument doc;
                DeserializationError err = deserializeJson(doc, data, len);
                if (!err) {
                    if (doc.containsKey("preset")) {
                        String p = doc["preset"].as<String>();
                        if (p == "text_screen") {
                            CameraDriver::applyPreset(CAM_PRESET_TEXT_SCREEN);
                        } else if (p == "outdoor") {
                            CameraDriver::applyPreset(CAM_PRESET_OUTDOOR);
                        } else if (p == "balanced") {
                            CameraDriver::applyPreset(CAM_PRESET_BALANCED);
                        }
                    }
                    if (doc.containsKey("ae_level")) {
                        CameraDriver::setExposureCompensation(doc["ae_level"].as<int>());
                    }
                    if (doc.containsKey("quality")) {
                        CameraDriver::setQuality(doc["quality"].as<int>());
                    }
                    if (doc.containsKey("framesize")) {
                        CameraDriver::setResolution((framesize_t)doc["framesize"].as<int>());
                    }
                }
            }
        }
    );

    server.on("/capture", HTTP_GET, [](AsyncWebServerRequest* request) {
        // NOTA: no esp_task_wdt_reset() aquí: este handler corre en el worker
        // async no suscrito al WDT; el watchdog real vive en loop().
        // Si la transmision anterior se quedo colgada mas de 8s, liberar watchdog de buffer
        snapForceResetIfStuck();

        if (snapIsBusy()) {
            AsyncWebServerResponse* response = request->beginResponse(
                503, "application/json", "{\"error\":\"camera_streaming_busy\",\"status\":\"fail\"}");
            addCors(response);
            request->send(response);
            return;
        }

        // Soporte de ajuste opcional por query string: ?preset=text_screen o ?ae=-2
        if (request->hasParam("preset")) {
            String p = request->getParam("preset")->value();
            if (p == "text_screen") CameraDriver::applyPreset(CAM_PRESET_TEXT_SCREEN);
            else if (p == "outdoor") CameraDriver::applyPreset(CAM_PRESET_OUTDOOR);
            else if (p == "balanced") CameraDriver::applyPreset(CAM_PRESET_BALANCED);
        }
        if (request->hasParam("ae")) {
            int ae = request->getParam("ae")->value().toInt();
            CameraDriver::setExposureCompensation(ae);
        }

        // Descarta 1 frame previo para asentar el AGC/AEC y capturar la imagen estabilizada
        camera_fb_t* fb = CameraDriver::captureFrame(1);
        if (!fb) {
            AsyncWebServerResponse* response = request->beginResponse(
                503, "application/json", "{\"error\":\"camera_busy_or_unavailable\",\"status\":\"fail\"}");
            addCors(response);
            request->send(response);
            return;
        }

        const size_t len = fb->len;
        uint8_t* targetBuf = s_snapshotBuf;
        bool allocatedDynamic = false;

        if (!targetBuf || len > MAX_SNAPSHOT_BUF_SIZE) {
            targetBuf = psramFound() ? (uint8_t*)ps_malloc(len) : (uint8_t*)malloc(len);
            allocatedDynamic = true;
        }

        if (!targetBuf) {
            CameraDriver::releaseFrame(fb);
            AsyncWebServerResponse* response = request->beginResponse(
                500, "application/json", "{\"error\":\"oom_snapshot_buffer\"}");
            addCors(response);
            request->send(response);
            return;
        }

        memcpy(targetBuf, fb->buf, len);
        CameraDriver::releaseFrame(fb);

        if (!snapTryBusy()) {
            if (allocatedDynamic) free(targetBuf);
            AsyncWebServerResponse* busy = request->beginResponse(
                503, "application/json", "{\"error\":\"camera_streaming_busy\",\"status\":\"fail\"}");
            addCors(busy);
            request->send(busy);
            return;
        }
        if (allocatedDynamic) {
            portENTER_CRITICAL(&s_snapMux);
            s_snapshotDynBuf = targetBuf;
            portEXIT_CRITICAL(&s_snapMux);
        }

        AsyncWebServerResponse* response = request->beginResponse(
            "image/jpeg",
            len,
            [targetBuf, len, allocatedDynamic](uint8_t* buffer, size_t maxLen, size_t index) -> size_t {
                if (index >= len) return 0;
                size_t chunk = min(maxLen, len - index);
                memcpy(buffer, targetBuf + index, chunk);
                if (index + chunk >= len) {
                    snapRelease();
                    if (allocatedDynamic) {
                        free(targetBuf);
                        portENTER_CRITICAL(&s_snapMux);
                        if (s_snapshotDynBuf == targetBuf) s_snapshotDynBuf = nullptr;
                        portEXIT_CRITICAL(&s_snapMux);
                    }
                }
                return chunk;
            }
        );
        addCors(response);
        // Si el cliente aborta, el callback de fin nunca llega: liberar busy+buf.
        response->setCode(200);
        request->onDisconnect([]() {
            snapRelease();
            portENTER_CRITICAL(&s_snapMux);
            if (s_snapshotDynBuf) { free(s_snapshotDynBuf); s_snapshotDynBuf = nullptr; }
            portEXIT_CRITICAL(&s_snapMux);
        });
        request->send(response);
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
                // Límite anti-HEAD-of-line: 256KB por request, chunks pares (s16le).
                if (total > 256 * 1024) {
                    SystemControl::log(SYS_LOG_WARN, "HTTP", "play_audio descartado: payload >256KB.");
                    return;
                }
                if ((len % 2) != 0) len -= 1;
                if (len > 0) AudioDriver::playAudioChunk(data, len);
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
        // Buffer por-request con vida atada a la request (shared_ptr): se
        // libera exactamente una vez al completarse O al desconectar.
        // 1600 samples = 100ms @16kHz.
        const size_t samples = 1600;
        std::shared_ptr<int16_t> micBuf(
            (int16_t*)malloc(samples * sizeof(int16_t)), free);
        if (!micBuf) {
            AsyncWebServerResponse* oom = request->beginResponse(
                500, "application/json", "{\"error\":\"oom_mic_buffer\"}");
            addCors(oom);
            request->send(oom);
            return;
        }
        size_t got = AudioDriver::readMicSamples(micBuf.get(), samples, 250);
        if (got == 0) {
            AsyncWebServerResponse* response = request->beginResponse(
                503, "application/json", "{\"error\":\"mic_read_timeout\",\"status\":\"fail\"}");
            addCors(response);
            request->send(response);
            return;
        }

        const size_t len = got * sizeof(int16_t);
        AsyncWebServerResponse* response = request->beginResponse(
            "application/octet-stream",
            len,
            [micBuf, len](uint8_t* buffer, size_t maxLen, size_t index) -> size_t {
                if (index >= len) return 0;
                size_t chunk = min(maxLen, len - index);
                memcpy(buffer, ((uint8_t*)micBuf.get()) + index, chunk);
                return chunk;
            }
        );
        addCors(response);
        request->onDisconnect([micBuf]() {});
        request->send(response);
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
                    auto clampI = [](int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); };
                    if (doc["quality"].is<int>()) s->set_quality(s, clampI(doc["quality"].as<int>(), 10, 63));
                    if (doc["brightness"].is<int>()) s->set_brightness(s, clampI(doc["brightness"].as<int>(), -2, 2));
                    if (doc["contrast"].is<int>()) s->set_contrast(s, clampI(doc["contrast"].as<int>(), -2, 2));
                    if (doc["saturation"].is<int>()) s->set_saturation(s, clampI(doc["saturation"].as<int>(), -2, 2));
                    if (doc["sharpness"].is<int>()) s->set_sharpness(s, clampI(doc["sharpness"].as<int>(), -2, 2));
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
            bool ok = !Update.hasError();
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
                AsyncWebServerResponse* denied = request->beginResponse(401, "text/plain", "FAIL_AUTH");
                denied->addHeader("Connection", "close");
                addCors(denied);
                request->send(denied);
                Update.abort();
                return;
            }
            AsyncWebServerResponse* response = request->beginResponse(
                ok ? 200 : 500, "text/plain", ok ? "OK_UPDATE" : "FAIL_UPDATE"
            );
            response->addHeader("Connection", "close");
            addCors(response);
            request->send(response);
            if (ok) {
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
                    Update.abort();
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

void WiFiServerManager::sendUdpBeacon() {
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
    udp.beginPacket(broadcastIp, UDP_BEACON_PORT);
    udp.write((const uint8_t*)payload.c_str(), payload.length());
    udp.endPacket();
}
