#pragma once

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

typedef void (*WiFiCredentialsCallback)(const String& ssid, const String& password);

class BleManager : public BLEServerCallbacks, public BLECharacteristicCallbacks {
public:
    static void init(WiFiCredentialsCallback onCredentialsReceived);
    static void updateStatus(const String& statusJson);
    static bool isConnected();

    void onConnect(BLEServer* pServer) override;
    void onDisconnect(BLEServer* pServer) override;
    void onWrite(BLECharacteristic* pCharacteristic) override;

private:
    static BLEServer* pServer;
    static BLECharacteristic* pWiFiConfigChar;
    static BLECharacteristic* pStatusChar;
    static bool deviceConnected;
    static WiFiCredentialsCallback credentialsCallback;
};
