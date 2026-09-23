# App Flutter GlassesPro

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
