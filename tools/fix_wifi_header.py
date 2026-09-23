from pathlib import Path
p = Path(__file__).resolve().parents[1] / "firmware" / "src" / "wifi_server.h"
p.write_text('''#pragma once

#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>

class WiFiServerManager {
public:
    static void initServer();
private:
    static AsyncWebServer server;
};
''', encoding='utf-8')
print('wifi_server.h cleaned')
