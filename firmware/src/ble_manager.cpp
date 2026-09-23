#include "ble_manager.h"
#include "config.h"
#include <ArduinoJson.h>

BLEServer* BleManager::pServer = nullptr;
BLECharacteristic* BleManager::pWiFiConfigChar = nullptr;
BLECharacteristic* BleManager::pStatusChar = nullptr;
bool BleManager::deviceConnected = false;
WiFiCredentialsCallback BleManager::credentialsCallback = nullptr;

void BleManager::init(WiFiCredentialsCallback onCredentialsReceived) {
    credentialsCallback = onCredentialsReceived;

    BLEDevice::init(BLE_DEVICE_NAME);
    pServer = BLEDevice::createServer();
    static BleManager instance;
    pServer->setCallbacks(&instance);

    BLEService* pService = pServer->createService(SERVICE_UUID);

    // Característica para aprovisionamiento Wi-Fi (Escritura desde móvil)
    pWiFiConfigChar = pService->createCharacteristic(
        WIFI_CONFIG_CHAR_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pWiFiConfigChar->setCallbacks(&instance);

    // Característica de Telemetría/Estado (Lectura y Notificación al móvil)
    pStatusChar = pService->createCharacteristic(
        DEVICE_STATUS_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    pStatusChar->addDescriptor(new BLE2902());

    pService->start();

    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[BLE OK] Servidor BLE iniciado esperando conexión móvil...");
}

void BleManager::onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("[BLE] Móvil conectado por Bluetooth.");
}

void BleManager::onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("[BLE] Móvil desconectado. Reiniciando publicidad BLE...");
    // Sin delay: onDisconnect corre en la tarea del stack BLE.
    pServer->getAdvertising()->start();
}

void BleManager::onWrite(BLECharacteristic* pCharacteristic) {
    std::string raw = pCharacteristic->getValue();
    if (raw.empty() || !credentialsCallback) return;
    Serial.println("[BLE] Recibidas credenciales Wi-Fi desde móvil.");
    JsonDocument doc;
    DeserializationError error = deserializeJson(doc, raw.data(), raw.size());
    if (!error) {
        String ssid = doc["ssid"].as<String>();
        String pass = doc["password"] | "";
        ssid.trim();
        if (ssid.length() == 0) {
            Serial.println("[BLE] SSID vacío ignorado.");
            return;
        }
        credentialsCallback(ssid, pass);
    } else {
        Serial.printf("[BLE JSON ERROR] %s\n", error.c_str());
    }
}

void BleManager::updateStatus(const String& statusJson) {
    if (!deviceConnected || !pStatusChar) return;
    // MTU por defecto 23 -> payload ~20B. Enviar resumen corto compatible:
    // {"fw":"..","ip":"..","b":85,"c":1} en vez del /status completo.
    String slim = statusJson;
    if (slim.length() > 100) {
        JsonDocument doc;
        if (!deserializeJson(doc, statusJson)) {
            JsonDocument out;
            if (doc["fw"].is<const char*>()) out["fw"] = doc["fw"].as<String>();
            if (doc["ip"].is<const char*>()) out["ip"] = doc["ip"].as<String>();
            out["b"] = doc["battery_pct"] | -1;
            out["c"] = doc["camera_ok"] | false;
            out["r"] = doc["rssi"] | 0;
            slim = "";
            serializeJson(out, slim);
        } else {
            slim = slim.substring(0, 100);
        }
    }
    pStatusChar->setValue(slim.c_str());
    pStatusChar->notify();
}

bool BleManager::isConnected() {
    return deviceConnected;
}
