#include "system_control.h"
#include "audio_driver.h"
#include <Preferences.h>
#include <ArduinoJson.h>
#include <esp_system.h>
#include <esp_heap_caps.h>
#include <cstdarg>

bool SystemControl::restartPending = false;
unsigned long SystemControl::restartAt = 0;
bool SystemControl::beepPending = false;
uint32_t SystemControl::beepFreq = 880;
uint32_t SystemControl::beepMs = 220;

uint32_t SystemControl::wifiReconnects = 0;
uint32_t SystemControl::i2sMicErrors = 0;
uint32_t SystemControl::i2sSpkErrors = 0;
uint32_t SystemControl::camCapturesTotal = 0;
uint32_t SystemControl::camCapturesCorrupt = 0;

SystemLogEntry SystemControl::logEntries[SystemControl::MAX_LOG_ENTRIES];
size_t SystemControl::logHead = 0;
size_t SystemControl::logCount = 0;

float SystemControl::filteredVoltage = 3.85f;
bool SystemControl::voltageInitialized = false;
portMUX_TYPE SystemControl::logMux = portMUX_INITIALIZER_UNLOCKED;

static const char* resetReasonToString(esp_reset_reason_t reason) {
    switch (reason) {
        case ESP_RST_UNKNOWN:    return "UNKNOWN";
        case ESP_RST_POWERON:    return "POWERON";
        case ESP_RST_EXT:        return "EXT_PIN";
        case ESP_RST_SW:         return "SW_RESTART";
        case ESP_RST_PANIC:      return "EXCEPTION_PANIC";
        case ESP_RST_INT_WDT:    return "INT_WATCHDOG";
        case ESP_RST_TASK_WDT:   return "TASK_WATCHDOG";
        case ESP_RST_WDT:        return "OTHER_WATCHDOG";
        case ESP_RST_DEEPSLEEP:  return "DEEPSLEEP";
        case ESP_RST_BROWNOUT:   return "BROWNOUT_VOLTAGE_DROP";
        case ESP_RST_SDIO:       return "SDIO";
        default:                 return "OTHER";
    }
}

void SystemControl::initCrashMonitoring() {
    esp_reset_reason_t reason = esp_reset_reason();
    Preferences prefs;
    prefs.begin("sys_diag", false);

    uint32_t bootCount = prefs.getUInt("boot_cnt", 0) + 1;
    prefs.putUInt("boot_cnt", bootCount);

    bool isCrash = (reason == ESP_RST_PANIC ||
                    reason == ESP_RST_INT_WDT ||
                    reason == ESP_RST_TASK_WDT ||
                    reason == ESP_RST_WDT ||
                    reason == ESP_RST_BROWNOUT);

    if (isCrash) {
        uint32_t crashCount = prefs.getUInt("crash_cnt", 0) + 1;
        prefs.putUInt("crash_cnt", crashCount);
        prefs.putInt("last_reason", (int)reason);
        prefs.putString("reason_str", resetReasonToString(reason));
        prefs.putUInt("last_crash_boot", bootCount);
    }

    prefs.end();

    logf(isCrash ? SYS_LOG_ERROR : SYS_LOG_INFO, "SYS",
         "Boot #%u - Causa: %s", bootCount, resetReasonToString(reason));
}

String SystemControl::getCrashLogJson() {
    Preferences prefs;
    prefs.begin("sys_diag", true);

    uint32_t bootCount = prefs.getUInt("boot_cnt", 0);
    uint32_t crashCount = prefs.getUInt("crash_cnt", 0);
    int lastReason = prefs.getInt("last_reason", (int)esp_reset_reason());
    String reasonStr = prefs.getString("reason_str", resetReasonToString((esp_reset_reason_t)lastReason));
    uint32_t lastCrashBoot = prefs.getUInt("last_crash_boot", 0);
    prefs.end();

    JsonDocument doc;
    doc["boot_count"] = bootCount;
    doc["crash_count"] = crashCount;
    doc["last_reason_code"] = lastReason;
    doc["last_reason"] = reasonStr;
    doc["last_crash_boot"] = lastCrashBoot;
    doc["current_reason"] = resetReasonToString(esp_reset_reason());
    doc["uptime_sec"] = millis() / 1000;
    doc["free_heap"] = ESP.getFreeHeap();
    doc["heap_frag_pct"] = getHeapFragmentation();

    String out;
    serializeJson(doc, out);
    return out;
}

void SystemControl::clearCrashLog() {
    Preferences prefs;
    prefs.begin("sys_diag", false);
    prefs.putUInt("crash_cnt", 0);
    prefs.putString("reason_str", "CLEARED");
    prefs.putInt("last_reason", (int)ESP_RST_SW);
    prefs.end();
    log(SYS_LOG_INFO, "SYS", "Crash log reiniciado manualmente.");
}

void SystemControl::log(uint8_t level, const char* tag, const char* msg) {
    if (!tag || !msg) return;

    portENTER_CRITICAL(&logMux);
    size_t index = (logHead + logCount) % MAX_LOG_ENTRIES;
    if (logCount == MAX_LOG_ENTRIES) {
        logHead = (logHead + 1) % MAX_LOG_ENTRIES;
    } else {
        logCount++;
    }

    SystemLogEntry& entry = logEntries[index];
    entry.timestampMs = millis();
    entry.level = level;
    strncpy(entry.tag, tag, sizeof(entry.tag) - 1);
    entry.tag[sizeof(entry.tag) - 1] = '\0';
    strncpy(entry.msg, msg, sizeof(entry.msg) - 1);
    entry.msg[sizeof(entry.msg) - 1] = '\0';
    uint32_t ts = entry.timestampMs;
    uint8_t lvl = entry.level;
    char tagCopy[12]; char msgCopy[80];
    strncpy(tagCopy, entry.tag, sizeof(tagCopy));
    strncpy(msgCopy, entry.msg, sizeof(msgCopy));
    portEXIT_CRITICAL(&logMux);

    const char* lvlStr = (lvl == SYS_LOG_DEBUG) ? "DEBUG" :
                         (lvl == SYS_LOG_INFO)  ? "INFO"  :
                         (lvl == SYS_LOG_WARN)  ? "WARN"  : "ERROR";
    Serial.printf("[%u][%s][%s] %s\n", ts, lvlStr, tagCopy, msgCopy);
}

void SystemControl::logf(uint8_t level, const char* tag, const char* format, ...) {
    char buffer[80];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    log(level, tag, buffer);
}

String SystemControl::getLogsJson(int limit, int minLevel) {
    if (limit <= 0 || limit > (int)MAX_LOG_ENTRIES) limit = MAX_LOG_ENTRIES;

    // Snapshot bajo sección crítica para evitar races con handlers async.
    struct Snap { uint32_t ts; uint8_t lvl; char tag[12]; char msg[80]; };
    Snap snap[MAX_LOG_ENTRIES];
    size_t snapCount = 0;
    portENTER_CRITICAL(&logMux);
    snapCount = logCount;
    for (size_t i = 0; i < snapCount && i < MAX_LOG_ENTRIES; i++) {
        size_t idx = (logHead + i) % MAX_LOG_ENTRIES;
        snap[i].ts = logEntries[idx].timestampMs;
        snap[i].lvl = logEntries[idx].level;
        strncpy(snap[i].tag, logEntries[idx].tag, sizeof(snap[i].tag));
        strncpy(snap[i].msg, logEntries[idx].msg, sizeof(snap[i].msg));
    }
    portEXIT_CRITICAL(&logMux);

    JsonDocument doc;
    JsonArray arr = doc.to<JsonArray>();

    size_t collected = 0;
    // Iterar del más reciente al más antiguo
    for (int i = (int)snapCount - 1; i >= 0 && (int)collected < limit; i--) {
        const Snap& e = snap[i];
        if (e.lvl >= minLevel) {
            JsonObject item = arr.add<JsonObject>();
            item["ts"] = e.ts;
            item["level"] = (e.lvl == SYS_LOG_DEBUG) ? "DEBUG" :
                            (e.lvl == SYS_LOG_INFO)  ? "INFO"  :
                            (e.lvl == SYS_LOG_WARN)  ? "WARN"  : "ERROR";
            item["tag"] = e.tag;
            item["msg"] = e.msg;
            collected++;
        }
    }

    String out;
    serializeJson(doc, out);
    return out;
}

void SystemControl::clearLogs() {
    portENTER_CRITICAL(&logMux);
    logHead = 0;
    logCount = 0;
    portEXIT_CRITICAL(&logMux);
}

uint8_t SystemControl::getHeapFragmentation() {
    size_t freeHeap = ESP.getFreeHeap();
    size_t maxBlock = heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    if (freeHeap == 0) return 100;
    if (maxBlock >= freeHeap) return 0;
    return 100 - (uint8_t)((maxBlock * 100) / freeHeap);
}

float SystemControl::updateAndGetBatteryVoltage(float rawV) {
    if (!voltageInitialized) {
        filteredVoltage = rawV;
        voltageInitialized = true;
    } else {
        // Filtro pasabajos exponencial (alpha = 0.2)
        filteredVoltage = (filteredVoltage * 0.8f) + (rawV * 0.2f);
    }
    return filteredVoltage;
}

float SystemControl::getFilteredBatteryVoltage() {
    return filteredVoltage;
}

void SystemControl::scheduleRestart(uint32_t delayMs) {
    restartPending = true;
    restartAt = millis() + delayMs;
    logf(SYS_LOG_WARN, "SYS", "Reinicio programado en %u ms", delayMs);
}

void SystemControl::scheduleBeep(uint32_t freqHz, uint32_t durationMs) {
    beepPending = true;
    beepFreq = freqHz;
    beepMs = durationMs;
}

bool SystemControl::isRestartPending() {
    return restartPending;
}

void SystemControl::poll() {
    if (beepPending) {
        beepPending = false;
        AudioDriver::playTestTone(beepFreq, beepMs);
    }
    if (restartPending && (long)(millis() - restartAt) >= 0) {
        log(SYS_LOG_WARN, "SYS", "Ejecutando reinicio diferido...");
        delay(50);
        ESP.restart();
    }
}
