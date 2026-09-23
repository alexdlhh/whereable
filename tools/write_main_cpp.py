# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "firmware" / "src" / "main.cpp"

CONTENT = r'''#include <Arduino.h>
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

    if (!CameraDriver::initCamera()) {
        Serial.println("[WARN] Camara no detectada o init demorado.");
    }
    if (!AudioDriver::initMic()) {
        Serial.println("[WARN] Fallo al iniciar microfono PDM.");
    }
    if (!AudioDriver::initSpeaker()) {
        Serial.println("[WARN] Fallo al iniciar altavoz I2S.");
    }

    BleManager::init(onWiFiCredentialsReceived);

    WiFi.mode(WIFI_AP_STA);
    WiFi.setSleep(false);
    WiFi.setAutoReconnect(true);
    WiFi.softAP(SOFTAP_SSID, SOFTAP_PASS);
    Serial.printf("[WIFI AP] SoftAP activo: %s (IP: %s)\n", SOFTAP_SSID, WiFi.softAPIP().toString().c_str());

    WiFiServerManager::initServer();

    if (MDNS.begin("glasses")) {
        MDNS.addService("http", "tcp", 80);
        Serial.println("[mDNS OK] http://glasses.local");
    }

    loadCredentialsFromNVS();

    // Watchdog DESPUES de init de camara (el probe DVP puede superar 8s)
    initWatchdog();
    AudioDriver::playTestTone(520, 150);
    Serial.println("[MAIN] Sistema preparado.");
}

void loop() {
    esp_task_wdt_reset();
    SystemControl::poll();

    if (wifiShouldConnect) {
        wifiShouldConnect = false;
        isConnectingWifi = true;
        wifiConnectStartTime = millis();
        Serial.printf("[WIFI] Conexion no bloqueante a: %s\n", currentSSID.c_str());
        WiFi.begin(currentSSID.c_str(), currentPassword.c_str());
    }

    if (isConnectingWifi) {
        if (WiFi.status() == WL_CONNECTED) {
            isConnectingWifi = false;
            Serial.printf("[WIFI OK] IP Station: %s\n", WiFi.localIP().toString().c_str());
            MDNS.notifyAPChange();
            SystemControl::scheduleBeep(880, 180);
        } else if (millis() - wifiConnectStartTime > 15000) {
            isConnectingWifi = false;
            Serial.println("[WIFI WARN] Timeout Station. SoftAP sigue operativo.");
        }
    } else if (currentSSID.length() > 0 && WiFi.status() != WL_CONNECTED) {
        if (millis() - lastStaRetryTime > 20000) {
            lastStaRetryTime = millis();
            wifiShouldConnect = true;
            Serial.println("[WIFI] Reintento automatico de Station...");
        }
    }

    if (millis() - lastTelemetryTime > 2000) {
        lastTelemetryTime = millis();
        if (BleManager::isConnected()) {
            JsonDocument doc;
            bool isSta = (WiFi.status() == WL_CONNECTED);
            int rawAdc = analogRead(BATTERY_ADC_PIN);
            float vBat = batteryVoltageFromAdc(rawAdc);
            doc["wifi"] = isSta;
            doc["ip"] = isSta ? WiFi.localIP().toString() : WiFi.softAPIP().toString();
            doc["mode"] = isSta ? "STA" : "AP";
            doc["rssi"] = isSta ? WiFi.RSSI() : 0;
            doc["heap"] = ESP.getFreeHeap();
            doc["psram"] = ESP.getFreePsram();
            doc["cam_ok"] = CameraDriver::isOperational();
            doc["cam_fail"] = CameraDriver::failureCount();
            doc["fw"] = FW_VERSION;
            doc["battery_voltage"] = vBat;
            doc["battery_pct"] = batteryPercentFromVoltage(vBat);

            String statusStr;
            serializeJson(doc, statusStr);
            BleManager::updateStatus(statusStr);
        }
    }

    delay(20);
}
'''

path.write_text(CONTENT.replace('\r\n', '\n'), encoding='utf-8')
print('wrote', path)
