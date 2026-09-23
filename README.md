# GlassesPro — gafas inteligentes de apoyo técnico

Sistema completo para **Seeed Studio XIAO ESP32S3 Sense** + app **Flutter** + backend **OpenAI-compatible** (visión + RAG + TTS) + **Filtro Edge Biométrico (Sherpa-ONNX + Vosk)**.

Pensado como herramienta de campo: identificación de piezas, diagnóstico visual, procedimientos seguros, soporte con **pantalla bloqueada (estilo app de música)** y **filtrado local por voz del técnico autorizado** para evitar enviar ruido o voces de terceros a la nube.

## Qué incluye

| Capa | Ruta | Rol |
| :--- | :--- | :--- |
| Firmware resiliente | `firmware/` | Cámara, PDM, I2S, BLE, SoftAP, OTA, WDT |
| App profesional | `mobile_app/` | Asistente de campo, Dev HUD, sync 3 niveles, Foreground Service |
| Filtro Edge & Biometría | `mobile_app/lib/features/voice_gate/` | Gatekeeper offline con Sherpa-ONNX (Speaker ID) + Vosk (Grammar/Wake-word) |
| Guía de montaje | `GUIA_PASO_A_PASO.md` | Hardware, flasheo, recuperación, pantalla bloqueada y calibración de voz |
| API gafas | `docs/API_FIRMWARE.md` | Contratos HTTP/BLE |

## Arranque rápido

```bash
# Firmware (VS Code + PlatformIO)
# Abrir firmware/ → Upload

# App
cd mobile_app
flutter pub get
flutter test
flutter run
```

Tests de firmware (sin placa):

```bash
cd firmware
pio test -e native
```

## Modo Pantalla Bloqueada (Manos Libres en Bolsillo)

Al igual que una app de música (Spotify / Podcast):
- **Foreground Service**: mantiene el enlace Wi-Fi/BLE activo sin que el sistema operativo mate el proceso al bloquear el móvil.
- **Acciones en Lockscreen**: la notificación persistente incluye botones de acción rápida (**🔍 Identificar**, **🩺 Diagnosticar**, **📋 Procedimiento**) utilizables directamente desde la pantalla de bloqueo.
- **Audio Context `playback` + `stayAwake`**: el audio TTS (por las gafas o el altavoz del teléfono) se reproduce fluidamente sin cortarse con la pantalla apagada.

## Filtro Edge de Voz: Sherpa-ONNX + Vosk

Para reducir el consumo de datos, proteger la privacidad y garantizar que **las gafas solo respondan a su técnico en entornos con más personas**:
1. **Detección VAD / Energía RMS**: descarta silencio, ruidos sordos y zumbidos sin activar el pipeline.
2. **Biometría de Locutor (Sherpa-ONNX Speaker ID)**: extrae un vector de embedding acústico espectral de 192 dimensiones normalizado L2 y evalúa la similitud de coseno contra el perfil calibrado del técnico ($\ge 68\%$). Voces de transeúntes o compañeros son rechazadas en milisegundos en el dispositivo.
3. **Reconocimiento de Intenciones & Palabras Clave (Vosk)**: filtra el prompt extrayendo palabras de activación (`gafas`, `oye gafas`, `asistente`) o comandos directos (`identifica`, `diagnostica`, `desmontar`, `voltaje`). Comandos de hardware (`bateria`, `beep`, `ping`) se resuelven localmente sin contactar la API LLM.
4. **Calibración y Diagnóstico**: gestionable en tiempo real desde la pestaña **"Filtro Voz"** del Developer HUD.

## Resiliencia

- Watchdog de hardware **después** de inicializar la cámara (evita bricks en el boot).
- SoftAP permanente `XIAO-Glasses-AP` / `192.168.4.1`.
- Mutex + reinit de cámara, OTA inalámbrica, factory reset remoto.
- Fallback de audio al altavoz del teléfono.
- Reintento Station cada 20 s y heartbeat con reconexión en la app.

## Modo diagnóstico

En la app: icono de monitor → HUD con waterfall, **Filtro Voz**, cámara, cURL, hardware (beep / self-test / OTA / reset), endpoint IA y logs.

El interruptor **Mock** permite ensayar la UI, la biometría y los atajos de campo sin gafas ni backend.
