# 📟 Instalación del firmware GlassesPro (XIAO ESP32S3 Sense) — Paso a paso

Firmware: **`1.5.1-V57-ALIGN`** (carpeta `firmware/` del proyecto).
Este es el firmware que usa la app real (Flutter): BLE + SoftAP + mDNS + OTA + watchdog.

---

## 0. Qué necesitas

| Cosa | Detalle |
|---|---|
| Placa | **Seeed Studio XIAO ESP32S3 Sense** (con PSRAM octal y cámara OV2640) |
| Cable | **USB-C de DATOS** (no solo carga; si no, no se ve el puerto COM) |
| PC | Windows / macOS / Linux |
| VS Code | Con la extensión **PlatformIO IDE** |
| Altavoz (opcional) | MAX98357A I2S para oír el beep y el TTS (pines: BCLK=7, LRC=8, DIN=9) |

> ⚠️ No uses el `.ino` simple de `arduino_WearableAI_1_3_7_WIFI_LOCKy/`: no tiene el servicio BLE que usa la app (UUIDs `4fafc201…`), ni mDNS, ni OTA. Es solo para aislar hardware.

---

## 1. Preparar el proyecto

1. Abre VS Code y abre la carpeta **`firmware/`** del proyecto (o el proyecto completo y navega a `firmware/`).
2. PlatformIO detecta `platformio.ini` automáticamente. La placa ya está configurada:
   - `board = seeed_xiao_esp32s3`
   - `board_build.arduino.memory_type = qio_opi` (PSRAM octal — **no lo cambies**)
   - `board_build.partitions = default_8MB.csv`
3. Las librerías (`esp32-camera`, `ArduinoJson`, `ESP Async WebServer`, `AsyncTCP`) se instalan **solas** la primera vez que compila (`lib_deps`). No hay que instalar nada a mano.

## 2. Conectar la placa

1. Conecta el XIAO por USB-C al PC.
2. Comprueba que aparece un puerto serie:
   - Windows: `Administrador de dispositivos → Puertos COM` (p. ej. `COM5`).
   - Si no aparece: prueba otro cable (muchos cables solo cargan) o otro puerto USB.
3. Si la placa no entra en modo flash (error `A fatal error occurred: Failed to connect to ESP32`):
   - Mantén pulsado el botón **BOOT** de la placa y conecta el USB (o pulsa BOOT justo al empezar el upload).
   - Evita conectar la batería LiPo durante el flasheo si puedes (brownout).

## 3. Compilar y subir

En la terminal de VS Code (o PowerShell):

```powershell
cd firmware
pio run -e seeed_xiao_esp32s3 -t upload
```

O desde la barra inferior de PlatformIO: selecciona el entorno **`seeed_xiao_esp32s3`** y pulsa **Upload (➜)**.

- La primera compilación descarga el toolchain y las librerías (puede tardar 5–15 min).
- Al terminar verás `SUCCESS` y la versión `1.5.1-V57-ALIGN`.

## 4. Verificar el arranque

```powershell
pio device monitor
```

(velocidad 115200, ya configurada en `platformio.ini`). Debes ver:

```
Smart Glasses Firmware 1.5.1-V57-ALIGN
[AUDIO MIC OK] ...
[AUDIO SPK OK] ...
[SoftAP activo: XIAO-Glasses-AP (IP: 192.168.4.1)]
[mDNS OK] http://glasses.local
```

Y un **beep** en el altavoz si está conectado.

> Si se reinicia en bucle: mira la causa en el monitor (`reset_reason`). Si es WDT por la cámara, es normal el primer arranque; si persiste, desconecta el flex de cámara y prueba.

## 5. Probar los endpoints (sin la app)

Conecta el móvil a la red **`XIAO-Glasses-AP`** (clave **`12345678`**, IP `192.168.4.1`) o, si ya configuraste Wi-Fi por BLE, a tu red local (`http://glasses.local`):

| Prueba | URL | Resultado esperado |
|---|---|---|
| Identidad | `http://192.168.4.1/` | JSON con `fw: 1.5.1-V57-ALIGN` |
| Telemetría | `http://192.168.4.1/status` | `status: online`, batería, heap, cámara |
| Self-test + beep | `http://192.168.4.1/selftest?beep=1` | `camera: true` + tono 880 Hz |
| Foto | `http://192.168.4.1/capture` | JPEG en el navegador |
| Foto con preset | `http://192.168.4.1/capture?preset=text_screen&ae=-2` | JPEG (preset anti-pantalla) |
| Micrófono | `http://192.168.4.1/mic_sample` | 3.200 bytes (100 ms PCM 16 kHz) |
| Tono | `http://192.168.4.1/beep` | `Beep ejecutado` |

Si `/capture` devuelve `503 camera_streaming_busy`, espera 1 s y reintenta (es el mutex de cámara, no un fallo).

## 6. Emparejar con la app

1. Abre la app **GlassesPro** (Flutter) en el móvil.
2. Pulsa el icono de **Bluetooth** (emparejar) en la barra superior.
3. Busca **`XIAO-SmartGlasses`** y conecta.
4. (Opcional) Configura el Wi-Fi de casa por BLE desde la app: la placa lo guarda en NVS y al reiniciar se conecta sola a tu red (modo `AP_STA`); el SoftAP sigue activo como red de emergencia.
5. La app detecta la IP por BLE / baliza UDP / mDNS y muestra el canal activo (BLE / Wi-Fi / SoftAP) en la cabecera.

## 7. Actualizar después (OTA, sin cable)

Una vez emparejado, no necesitas volver a conectar USB:

- Desde la app: tab **Hardware** del Diagnóstico → subir el `.bin` (endpoint `POST /update`).
- Si configuraste token OTA en NVS (`ota_token`), el envío exige el header `X-OTA-Token`.
- Si algo se tuerce: `POST /factory_reset` (borra NVS y vuelve a SoftAP) o `POST /reboot`.

---

## Solución de problemas rápida

| Síntoma | Causa probable / arreglo |
|---|---|
| No aparece puerto COM | Cable solo de carga → usa cable de datos; prueba otro USB |
| `Failed to connect to ESP32` | Pulsa **BOOT** al iniciar el upload; desconecta la batería |
| Reinicios en bucle | WDT por cámara (flex suelto) o brownout (batería débil). Prueba sin batería / sin flex |
| `camera: false` en `/status` | Flex de cámara mal encajado; el firmware cuenta fallos y reinicia el bus DVP solo (mira `camera_failures` en `/status`) |
| No hay sonido | MAX98357A: `SD` a 3.3 V, `GAIN` a GND; prueba `/beep` |
| La app no encuentra la placa | Verifica que el firmware es el de `firmware/` (el `.ino` simple no tiene el servicio BLE de la app); mira `fw` en `/status` |
| Timeouts de red / `XIAO_NETWORK_NOT_READY` | Es el problema de reconexión STA conocido: usa el SoftAP directo (192.168.4.1) mientras tanto; el firmware real ya trae watchdog y auto-reconexión |

---

## Referencias

- API completa: `docs/API_FIRMWARE.md`
- Pinout: `firmware/src/config.h`
- Versión: `firmware/src/fw_version.h`
- Guía maestra del sistema (app + hardware): `GUIA_PASO_A_PASO.md`
