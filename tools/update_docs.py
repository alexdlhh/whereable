from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

readme = ROOT / "README.md"
app_readme = ROOT / "mobile_app" / "README.md"
guia = ROOT / "GUIA_PASO_A_PASO.md"

readme_text = r'''# GlassesPro — gafas inteligentes de apoyo técnico

Sistema completo para **Seeed Studio XIAO ESP32S3 Sense** + app **Flutter** + backend **OpenAI-compatible** (visión + RAG + TTS).

Pensado como herramienta de campo: identificación de piezas, diagnóstico visual, procedimientos seguros, soporte con **pantalla bloqueada (estilo app de música)** y trazas de latencia.

## Qué incluye

| Capa | Ruta | Rol |
| :--- | :--- | :--- |
| Firmware resiliente | `firmware/` | Cámara, PDM, I2S, BLE, SoftAP, OTA, WDT |
| App profesional | `mobile_app/` | Asistente de campo, Dev HUD, sync 3 niveles, Foreground Service |
| Guía de montaje | `GUIA_PASO_A_PASO.md` | Hardware, flasheo, recuperación y uso con pantalla bloqueada |
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

## Resiliencia

- Watchdog de hardware **después** de inicializar la cámara (evita bricks en el boot).
- SoftAP permanente `XIAO-Glasses-AP` / `192.168.4.1`.
- Mutex + reinit de cámara, OTA inalámbrica, factory reset remoto.
- Fallback de audio al altavoz del teléfono.
- Reintento Station cada 20 s y heartbeat con reconexión en la app.

## Modo diagnóstico

En la app: icono de monitor → HUD con waterfall, cámara, cURL, hardware (beep / self-test / OTA / reset), endpoint IA y logs.

El interruptor **Mock** permite ensayar la UI y los atajos de campo sin gafas ni backend.
'''

app_readme_text = r'''# App Flutter GlassesPro

Asistente de campo (Android / iOS) con sincronización BLE+Wi-Fi, pipeline multimodal, soporte para pantalla bloqueada en segundo plano y HUD de diagnóstico.

## Comandos

```bash
flutter pub get
flutter test
flutter run
```

## Características para trabajo de campo

- **Modo Bolsillo / Pantalla Bloqueada**:
  - Servicio en primer plano (Foreground Service) con notificación persistente.
  - Botones de acción en la pantalla de bloqueo: `🔍 Identificar`, `🩺 Diagnosticar`, `📋 Procedimiento`.
  - Audio TTS continuo con pantalla apagada (`AudioContext` con `stayAwake` y categoría `playback`).
- **Atajos Técnicos**: Identificar, Diagnosticar, Procedimiento, Nº de serie.
- **HUD de Diagnóstico**: Latencias (waterfall), cámara en directo, cURL generado, logs en tiempo real, OTA y autotest.
- **Configuración Persistente**: URL base, API Key, modelo y orden de trabajo guardados en `SharedPreferences`.
'''

guia_content = guia.read_text(encoding="utf-8")
if "## 8. Flujo de trabajo de campo" in guia_content and "Modo Pantalla Bloqueada" not in guia_content:
    guia_content = guia_content.replace(
        "## 8. Flujo de trabajo de campo (app profesional)",
        r'''## 8. Flujo de trabajo de campo (app profesional y modo bolsillo)

La app está diseñada para operar como una **app de música**: puedes bloquear el móvil, meterlo al bolsillo y trabajar con ambas manos libres.

1. **Activar Modo Pantalla Bloqueada**: Pulsa el icono de candado/pantalla en la barra superior o en Diagnóstico → Hardware.
2. **Notificación persistente con acciones**:
   - En la pantalla de bloqueo verás los botones: **🔍 Identificar**, **🩺 Diagnosticar**, **📋 Procedimiento**.
   - Al pulsar un botón con el móvil bloqueado, el teléfono solicita captura a las gafas por Wi-Fi, consulta a la IA y reproduce la respuesta por audio sin necesidad de desbloquear.
3. **Audio ininterrumpido**: El motor de audio (`AudioContext` con `stayAwake` y categoría `playback`) garantiza que la voz de la IA se escuche por la patilla o el teléfono con la pantalla apagada.
4. **Atajos visuales en pantalla**: Si tienes el móvil a la vista, usa los chips superiores: Identificar, Diagnosticar, Procedimiento, Nº de serie.
5. **Contexto de trabajo**: Puedes configurar una **orden de trabajo** en Diagnóstico → IA para que cada consulta quede etiquetada.'''
    )

readme.write_text(readme_text, encoding="utf-8")
app_readme.write_text(app_readme_text, encoding="utf-8")
guia.write_text(guia_content, encoding="utf-8")
print("docs updated successfully")
