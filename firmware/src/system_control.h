#pragma once

#include <Arduino.h>

enum SystemLogLevel {
    SYS_LOG_DEBUG = 0,
    SYS_LOG_INFO  = 1,
    SYS_LOG_WARN  = 2,
    SYS_LOG_ERROR = 3
};

struct SystemLogEntry {
    uint32_t timestampMs;
    uint8_t level;
    char tag[12];
    char msg[80];
};

// Reinicios y beeps diferidos, buffer de logs circular y diagnostico NVS
class SystemControl {
public:
    static void initCrashMonitoring();
    static void scheduleRestart(uint32_t delayMs = 400);
    static void scheduleBeep(uint32_t freqHz = 880, uint32_t durationMs = 220);
    static void poll();
    static bool isRestartPending();

    // Logs en anillo (RAM)
    static void log(uint8_t level, const char* tag, const char* msg);
    static void logf(uint8_t level, const char* tag, const char* format, ...);
    static String getLogsJson(int limit = 50, int minLevel = 0);
    static void clearLogs();

    // Crash log persistente en NVS
    static String getCrashLogJson();
    static void clearCrashLog();

    // Metricas y contadores de estabilidad
    static uint32_t wifiReconnects;
    static uint32_t i2sMicErrors;
    static uint32_t i2sSpkErrors;
    static uint32_t camCapturesTotal;
    static uint32_t camCapturesCorrupt;

    static uint8_t getHeapFragmentation();
    static float updateAndGetBatteryVoltage(float rawV);
    static float getFilteredBatteryVoltage();

private:
    static bool restartPending;
    static unsigned long restartAt;
    static bool beepPending;
    static uint32_t beepFreq;
    static uint32_t beepMs;

    // Buffer circular para 64 entradas de log (~6 KB)
    static const size_t MAX_LOG_ENTRIES = 64;
    static SystemLogEntry logEntries[MAX_LOG_ENTRIES];
    static size_t logHead;
    static size_t logCount;

    // Filtro IIR / media movil para bateria
    static float filteredVoltage;
    static bool voltageInitialized;

    static portMUX_TYPE logMux;
};
