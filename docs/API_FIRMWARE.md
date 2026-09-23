# API HTTP del firmware (XIAO ESP32S3 Sense)

Base: `http://<ip>:80` — IP Station, `http://glasses.local` o SoftAP `http://192.168.4.1`.

CORS está habilitado en todos los endpoints (incluido 404).

| Método | Ruta | Descripción |
| :--- | :--- | :--- |
| GET | `/` | Identidad: nombre, versión, mapa de rutas |
| GET | `/health` | Liveness `{ok:true}` |
| GET | `/status` | Telemetría: IP, RSSI, heap, PSRAM, batería, cámara, FW, WDT |
| GET | `/diag` | Diagnóstico unificado: heap+PSRAM frag, uptime, reset_reason, RSSI |
| GET | `/selftest?beep=0/1` | Diagnóstico (por defecto `beep=1` por compat; `beep=0` no pita) |
| GET | `/capture?preset=&ae=` | JPEG (503 `camera_streaming_busy`/`camera_busy_or_unavailable`, 500 `oom_snapshot_buffer`) |
| POST | `/play_audio` | PCM s16le **mono** 16 kHz, máx 256 KB/request (upmix a estéreo) |
| GET | `/beep` | Tono de prueba 880 Hz |
| GET | `/mic_sample` | 100 ms PCM (1600 samples @16 kHz); 503 `mic_read_timeout` |
| GET | `/camera_settings` | Preset actual `{preset, ae_level, framesize, operational, failures}` |
| POST | `/camera_settings` | `{preset: balanced/text_screen/outdoor, ae_level, quality, framesize}` |
| POST | `/camera_config` | JSON `{quality 10-63, brightness/contrast/saturation/sharpness -2..2}` (clamp) |
| GET | `/logs?limit&level` | Buffer circular RAM (64 entradas) |
| POST | `/logs/clear` | Vacía logs RAM |
| GET | `/crash_log` | NVS `boot_count/crash_count/last_reason` |
| POST | `/crash_log/clear` | Limpia crash NVS |
| GET | `/network_stats` | `sta_ip/ap_ip/rssi/reconnects/ap_stations/beacon_interval` |
| POST | `/reboot` | Reinicio diferido (no bloquea el servidor async) |
| POST | `/factory_reset` | Borra NVS Wi-Fi y reinicia en SoftAP |
| POST | `/update` | OTA multipart campo `firmware` → `200 OK_UPDATE` / `500 FAIL_UPDATE` / `401 FAIL_AUTH` (si NVS `ota_token` configurado, exigir header `X-OTA-Token`) |

## BLE GATT

- Servicio `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- Write Wi-Fi `beb5483e-36e1-4688-b7f5-ea07361b26a8`: JSON `{"ssid":"...","password":"..."}` (SSID vacío ignorado)
- Notify estado `8b1b22e1-4547-497b-83a3-6b746a5996b7`: resumen corto `{"fw","ip","b":pct,"c":cam_ok,"r":rssi}` (MTU 23)
- UDP beacon `255.255.255.255:4210` cada 1500 ms solo en STA: `{"device","ip","port":80,"fw","rssi","mode":"STA"}` — la app lo VERIFICA con `GET /status` antes de marcar connected.
