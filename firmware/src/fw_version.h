#pragma once

// V57-ALIGN: endpoints /capture, /mic_sample (100 ms), /play_audio, /beep y
// /status verificados contra el ejemplo que funciona (WearableAI_1_3_7_WIFI_LOCKy.ino).
// El firmware real ya los implementa (AsyncWebServer + PSRAM + auto-recovery);
// este bump marca la alineación con el estado V57 de la app.
#ifndef FW_VERSION
#define FW_VERSION "1.5.1-V57-ALIGN"
#endif

#ifndef FW_BUILD_NAME
#define FW_BUILD_NAME "GlassesPro-Resilient-v1.5.1-V57"
#endif

#ifndef WDT_TIMEOUT_SECONDS
#define WDT_TIMEOUT_SECONDS 10
#endif
