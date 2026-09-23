#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <esp_task_wdt.h>
#include <esp_idf_version.h>

#include "config.h"
#include "fw_version.h"
#include "battery_utils.h"
#include "camera_driver.h"
#include "audio_driver.h"
#include "ble_manager.h"
#include "wifi_server.h"
#include "system_control.h"

Preferences preferences;

String currentSSID = "";
String currentPassword = "";
bool wifiShouldConnect = false;
unsigned long lastTelemetryTime = 0;
unsigned long wifiConnectStartTime = 0;
unsigned long lastStaRetryTime = 0;
bool isConnectingWifi = false;

void saveCredentialsToNVS(const String& ssid, const String& password) {
    preferences.begin("glasses_cfg", false);
    preferences.putString("ssid", ssid);
    preferences.putString("pass", password);
    preferences.end();
    Serial.println("[NVS] Credenciales Wi-Fi guardadas.");
}

void loadCredentialsFromNVS() {
    preferences.begin("glasses_cfg", true);
    currentSSID = preferences.getString("ssid", "");
    currentPassword = preferences.getString("pass", "");
    preferences.end();

    if (currentSSID.length() > 0) {
        Serial.printf("[NVS] Credenciales recuperadas: SSID=%s\n", currentSSID.c_str());
        wifiShouldConnect = true;
    } else {
        Serial.println("[NVS] Sin credenciales Wi-Fi. Esperando BLE.");
    }
}

void onWiFiCredentialsReceived(const String& ssid, const String& password) {
    Serial.printf("[MAIN] Nuevas credenciales Wi-Fi: SSID=%s\n", ssid.c_str());
    currentSSID = ssid;
    currentPassword = password;
    saveCredentialsToNVS(ssid, password);
    wifiShouldConnect = true;
}

void initWatchdog() {
#if ESP_IDF_VERSION_MAJOR >= 5
    esp_task_wdt_config_t twdt_config = {
        .timeout_ms = WDT_TIMEOUT_SECONDS * 1000,
        .idle_core_mask = (1 << portNUM_PROCESSORS) - 1,
        .trigger_panic = true
    };
    esp_task_wdt_reconfigure(&twdt_config);
#else
    esp_task_wdt_init(WDT_TIMEOUT_SECONDS, true);
#endif
    esp_task_wdt_add(NULL);
}

void setup() {
    Serial.begin(115200);
    delay(200);
    Serial.println("=========================================");
    Serial.printf("  Smart Glasses Firmware %s\n", FW_VERSION);
    Serial.println("  Alta Resiliencia & Auto-Recovery");
    Serial.println("=========================================");

    pinMode(BATTERY_ADC_PIN, INPUT);
    analogSetAttenuation(ADC_11db); // Rango completo 0-3.3V, error menor en S3
    analogReadResolution(12);

    // Inicializar monitoreo y registro de causas de reinicio en NVS
    SystemControl::initCrashMonitoring();

    if (!CameraDriver::initCamera()) {
        SystemControl::log(SYS_LOG_WARN, "CAM", "Camara no detectada o init demorado.");
    }
    if (!AudioDriver::initMic()) {
        SystemControl::log(SYS_LOG_WARN, "MIC", "Fallo al iniciar microfono PDM.");
    }
    if (!AudioDriver::initSpeaker()) {
        SystemControl::log(SYS_LOG_WARN, "SPK", "Fallo al iniciar altavoz I2S.");
    }

    BleManager::init(onWiFiCredentialsReceived);

    WiFi.mode(WIFI_AP_STA);
    WiFi.setSleep(false);
    WiFi.setAutoReconnect(true);
    // Canal AP fijo (6) para que los reintentos STA no fuercen saltos de canal.
    WiFi.softAP(SOFTAP_SSID, SOFTAP_PASS, 6);
    WiFi.onEvent([](WiFiEvent_t event, WiFiEventInfo_t info) {
        if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
            SystemControl::logf(SYS_LOG_WARN, "WIFI", "STA desconectado (razon %u).", info.wifi_sta_disconnected.reason);
        }
    });
    SystemControl::logf(SYS_LOG_INFO, "WIFI", "SoftAP activo: %s (IP: %s)", SOFTAP_SSID, WiFi.softAPIP().toString().c_str());

    WiFiServerManager::initServer();

    if (MDNS.begin("glasses")) {
        MDNS.addService("http", "tcp", 80);
        Serial.println("[mDNS OK] http://glasses.local");
    }

    loadCredentialsFromNVS();

    // Watchdog DESPUES de init de camara (el probe DVP puede superar 8s)
    initWatchdog();
    AudioDriver::playTestTone(520, 150);
    SystemControl::log(SYS_LOG_INFO, "SYS", "Sistema preparado y supervisado por WDT.");
}

void loop() {
    esp_task_wdt_reset();
    SystemControl::poll();

    if (wifiShouldConnect) {
        wifiShouldConnect = false;
        isConnectingWifi = true;
        wifiConnectStartTime = millis();
        SystemControl::logf(SYS_LOG_INFO, "WIFI", "Conexion no bloqueante a: %s", currentSSID.c_str());
        WiFi.begin(currentSSID.c_str(), currentPassword.c_str());
    }

    if (isConnectingWifi) {
        if (WiFi.status() == WL_CONNECTED) {
            isConnectingWifi = false;
            SystemControl::wifiReconnects++;
            SystemControl::logf(SYS_LOG_INFO, "WIFI", "IP Station asignada: %s", WiFi.localIP().toString().c_str());
            MDNS.notifyAPChange();
            SystemControl::scheduleBeep(880, 180);
        } else if (millis() - wifiConnectStartTime > 15000) {
            isConnectingWifi = false;
            // Detener el escaneo en background de Station para no desestabilizar SoftAP (evita saltos de canal)
            WiFi.disconnect(false);
            SystemControl::log(SYS_LOG_WARN, "WIFI", "Timeout Station. Radio estabilizada en SoftAP (192.168.4.1).");
        }
    } else if (currentSSID.length() > 0 && WiFi.status() != WL_CONNECTED) {
        // Backoff exponencial 15s->5min; con cliente AP activo se reintenta
        // cada 5min (antes: starvation permanente) sin tumbar el SoftAP.
        bool apBusy = (WiFi.softAPgetStationNum() > 0);
        unsigned long interval = apBusy ? 300000UL : 60000UL;
        static uint8_t staFailStreak = 0;
        if (millis() - lastStaRetryTime > interval) {
            lastStaRetryTime = millis();
            staFailStreak = (staFailStreak >= 5) ? 5 : staFailStreak + 1;
            wifiShouldConnect = true;
            SystemControl::logf(SYS_LOG_INFO, "WIFI", "Reintento STA #%u (AP %s)...",
                staFailStreak, apBusy ? "ocupado" : "libre");
        }
    }

    // Emitir baliza UDP periódica en la red Station (ej. Tethering / Hotspot) para auto-descubrimiento en <100ms
    WiFiServerManager::sendUdpBeacon();

    if (millis() - lastTelemetryTime > 2000) {
        lastTelemetryTime = millis();
        if (BleManager::isConnected()) {
            JsonDocument doc;
            bool isSta = (WiFi.status() == WL_CONNECTED);
            // Promedio de 8 muestras para reducir ruido ADC del S3 (±10%).
            long acc = 0;
            for (int i = 0; i < 8; i++) { acc += analogRead(BATTERY_ADC_PIN); delay(1); }
            int rawAdc = acc / 8;
            float vBat = batteryVoltageFromAdc(rawAdc);
            float filteredVBat = SystemControl::updateAndGetBatteryVoltage(vBat);

            doc["wifi"] = isSta;
            doc["ip"] = isSta ? WiFi.localIP().toString() : WiFi.softAPIP().toString();
            doc["mode"] = isSta ? "STA" : "AP";
            doc["rssi"] = isSta ? WiFi.RSSI() : 0;
            doc["heap"] = ESP.getFreeHeap();
            doc["heap_frag"] = SystemControl::getHeapFragmentation();
            doc["psram"] = ESP.getFreePsram();
            doc["cam_ok"] = CameraDriver::isOperational();
            doc["cam_fail"] = CameraDriver::failureCount();
            doc["cam_caps"] = CameraDriver::totalCaptures();
            doc["cam_corrupt"] = CameraDriver::corruptCount();
            doc["fw"] = FW_VERSION;
            doc["battery_voltage"] = filteredVBat;
            doc["battery_pct"] = batteryPercentFromVoltage(filteredVBat);

            String statusStr;
            serializeJson(doc, statusStr);
            BleManager::updateStatus(statusStr);
        }
    }

    delay(20);
}
