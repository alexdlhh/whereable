# Firmware GlassesPro (XIAO ESP32S3 Sense)

Requisitos: PlatformIO, cable USB-C de **datos**, PSRAM octal (`qio_opi`).

```bash
pio run -e seeed_xiao_esp32s3 -t upload
pio device monitor
pio test -e native
```

Al boot:

1. Cámara / mic / I2S
2. BLE `XIAO-SmartGlasses`
3. SoftAP `XIAO-Glasses-AP` (clave `12345678`)
4. HTTP :80 + mDNS `glasses.local`
5. Watchdog 10 s
6. Beep de arranque

Ver `docs/API_FIRMWARE.md` y el pinout en `src/config.h`.
