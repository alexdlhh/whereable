#pragma once

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <ESPAsyncWebServer.h>

class WiFiServerManager {
public:
    static void initServer();
    static void sendUdpBeacon();
private:
    static AsyncWebServer server;
    static WiFiUDP udp;
    static unsigned long lastUdpBeaconTime;
};
