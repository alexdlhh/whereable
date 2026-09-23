# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

constants = ROOT / "mobile_app" / "lib" / "core" / "constants" / "api_constants.dart"
constants.write_text(r'''class ApiConstants {
  static const String defaultAiBaseUrl = "https://api.openai.com/v1";
  static const String defaultApiKey = "YOUR_API_KEY_HERE";
  static const String defaultModel = "gpt-4o";

  static const String chatCompletionsEndpoint = "/chat/completions";
  static const String transcriptionsEndpoint = "/audio/transcriptions";
  static const String speechEndpoint = "/audio/speech";

  static const String glassesBleName = "XIAO-SmartGlasses";
  static const String bleServiceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String bleWifiConfigCharUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String bleStatusCharUuid = "8b1b22e1-4547-497b-83a3-6b746a5996b7";

  static const String systemInstruction = """
Eres un asistente de soporte técnico de campo para un profesional con gafas inteligentes.
Habla en español, breve y accionable (la respuesta se leerá en voz alta).
Reglas:
1. Prioriza seguridad: corte de tensión, ESD, no forzar flex ni clips.
2. Si hay imagen, nombra lo que ves (marcas, códigos, daños) antes de indicar pasos.
3. Pasos numerados, un verbo por paso, máximo 6 pasos salvo que pidan más.
4. Si el encuadre es malo, indica cómo mover la cabeza o la luz.
5. No inventes números de serie ni lecturas que no se vean.
""";
}
'''.replace('\r\n', '\n'), encoding='utf-8')

guia = (ROOT / "GUIA_PASO_A_PASO.md").read_text(encoding='utf-8')
extra = r'''

---

## 8. Flujo de trabajo de campo (app profesional)

1. Empareja una vez (BLE) y aprovisiona el Wi-Fi del taller o el hotspot del móvil.
2. En el siguiente encendido, la app hace Fast-Path a la última IP / `glasses.local`.
3. Mira la pieza y usa los atajos: **Identificar**, **Diagnosticar**, **Procedimiento**, **Nº de serie**.
4. Copia la respuesta o pulsa repetir. El audio sale por la patilla; si falla, por el teléfono.
5. Opcional: indica una **orden de trabajo** en Diagnóstico → IA para etiquetar el contexto al modelo.

---

## 9. OTA y recuperación

1. Compila el `.bin` con PlatformIO (`firmware/.pio/build/seeed_xiao_esp32s3/firmware.bin`).
2. En la app: Diagnóstico → Hardware → **OTA .bin**.
3. No cortes la batería durante la subida. Las gafas reinician solas.
4. Si no responden: conéctate a `XIAO-Glasses-AP` / `192.168.4.1` y reintenta.
5. **Reset NVS** borra el Wi-Fi corrupto. El Watchdog (10 s) recupera cuelgues de DMA.

---

## 10. Tests

```bash
cd mobile_app
flutter pub get
flutter test

cd ../firmware
pio test -e native
```

Los tests de Flutter cubren batería, cURL redactado, candidatos de sync, WAV/resample, telemetría JSON, mocks y la pantalla principal.

---

## 11. API HTTP resumida

Ver `docs/API_FIRMWARE.md`. Endpoints nuevos: `/`, `/health`, `/selftest`, `/mic_sample`. Reinicio y factory reset son **diferidos** (no `delay` dentro del handler Async).

---

## 12. Solución de problemas

| Síntoma | Qué hacer |
| :--- | :--- |
| App no encuentra gafas | SoftAP `XIAO-Glasses-AP`, IP `192.168.4.1`, o BLE scan |
| Cámara 503 | Flex, luz, o 3 fallos → auto-reinit. Self-test en HUD |
| Audio agudo/rápido | El firmware espera PCM mono 16 kHz; la app remuestrea 24→16 |
| OTA FAIL_UPDATE | Binario de la env `seeed_xiao_esp32s3`, no otro board |
| Brick aparente | Espera 10 s (WDT), SoftAP sigue activo |
'''

if '## 8. Flujo de trabajo' not in guia:
    (ROOT / "GUIA_PASO_A_PASO.md").write_text(guia.rstrip() + extra, encoding='utf-8')
print('wrote constants and guia')
