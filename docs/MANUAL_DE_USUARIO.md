# Manual de Usuario - GlassesPro (App Móvil para Gafas Inteligentes)

Bienvenido a **GlassesPro**, la aplicación móvil para soporte técnico, diagnóstico asistido por IA multimodal y visión artificial en tiempo real con tus gafas inteligentes.

---

## 📋 Tabla de Contenidos
1. [Requisitos Previos](#1-requisitos-previos)
2. [Instalación de la Aplicación](#2-instalación-de-la-aplicación)
3. [Emparejamiento y Conexión Automática (Buscador)](#3-emparejamiento-y-conexión-automática-buscador)
4. [Uso de Acciones Rápidas (Entrada Visual de las Gafas)](#4-uso-de-acciones-rápidas-entrada-visual-de-las-gafas)
5. [Consultas por Voz y Dictado de Campo](#5-consultas-por-voz-y-dictado-de-campo)
6. [Modo Pantalla Bloqueada (Uso en Bolsillo)](#6-modo-pantalla-bloqueada-uso-en-bolsillo)
7. [Gestión y Borrado de Tareas](#7-gestión-y-borrado-de-tareas)
8. [Panel de Diagnóstico y Telemetría en Tiempo Real](#8-panel-de-diagnóstico-y-telemetría-en-tiempo-real)
9. [Resolución de Problemas Frecuentes](#9-resolución-de-problemas-frecuentes)

---

## 1. Requisitos Previos

* **Gafas Inteligentes:** Batería cargada y dispositivo encendido (LED activo).
* **Teléfono Móvil Android:** Android 6.0 (SDK 23) o superior.
* **Permisos requeridos:**
  * Bluetooth y Dispositivos Cercanos.
  * Ubicación (necesario en Android para escanear redes BLE/Wi-Fi).
  * Micrófono (para dictado y calibración de voz).
  * Notificaciones (para modo en segundo plano).

---

## 2. Instalación de la Aplicación

1. Copia o descarga el archivo APK generado:
   `mobile_app/build/app/outputs/flutter-apk/app-debug.apk`
2. En tu móvil, abre el archivo APK y confirma la instalación.
3. Al abrir la app por primera vez, acepta los permisos del sistema solicitados.

---

## 3. Emparejamiento y Conexión Automática (Buscador)

La aplicación cuenta con un **Buscador Inteligente Multi-Canal** que detecta tus gafas automáticamente tanto por **Bluetooth Low Energy (BLE)** como por la **Red Local Wi-Fi**.

### Pasos para conectar:
1. En la barra superior, pulsa el icono de **Buscador / Bluetooth** (o toca el banner de estado superior).
2. Se abrirá la hoja modal **"Buscador de Gafas"**:
   * El radar comenzará a escanear automáticamente las gafas cercanas.
   * En la sección **"Dispositivos Encontrados"**, verás tus gafas con su nivel de señal y tipo de enlace.
3. Pulsa el botón **"Conectar"** junto a tu dispositivo para sincronizarlo al instante.

### Aprovisionamiento Wi-Fi Asistido (1 Solo Paso):
Si necesitas que las gafas se conecten a la red Wi-Fi de tu taller o zona de trabajo:
1. La app detectará automáticamente el nombre de red (SSID) al que está conectado tu móvil.
2. Introduce únicamente la contraseña de tu red en el campo correspondiente.
3. Pulsa **"Vincular y Enviar Wi-Fi a Gafas"**. La app se conectará por BLE y transferirá las credenciales directamente.

---

## 4. Uso de Acciones Rápidas (Entrada Visual de las Gafas)

En la pantalla principal dispones de 4 accesos rápidos orientados a tareas de campo. Cada acción realiza una **captura fotográfica real desde la cámara de las gafas** y la envía a la IA:

| Acción | Función | ¿Qué hace internamente? |
| :--- | :--- | :--- |
| **🔍 Identificar** | Reconocimiento de piezas | Captura fotograma y describe marcas, códigos y función del componente enfocado. |
| **🩺 Diagnosticar** | Detección de fallos | Analiza la imagen buscando sobrecalentamiento, cortos, flex dañados o desgaste. |
| **📋 Procedimiento** | Guía de desmontaje | Detalla los pasos seguros para desmontar o medir la pieza enfocada sin romper clips. |
| **🏷️ Nº de serie** | Lectura OCR | Lee números de serie, códigos QR y etiquetas técnicas visibles en la placa. |

> **Nota:** Puedes tocar el botón `(?)` en la cabecera de las acciones rápidas para consultar la guía explicativa en cualquier momento.

---

## 5. Consultas por Voz y Dictado de Campo

Puedes hacer cualquier pregunta técnica libre sin necesidad de teclear:
1. Pulsa el botón del **Micrófono (🎙️)** en la barra inferior de entrada.
2. Habla describiendo tu problema (ej: *"¿A cuántos voltios debe operar este condensador?"*).
3. Vuelve a pulsar el botón para detener la grabación.
4. La app procesará tu audio, filtrará ruidos con el motor biométrico Edge y enviará la consulta junto con el fotograma de las gafas.
5. La respuesta se mostrará en pantalla y se reproducirá por audio.

---

## 6. Modo Pantalla Bloqueada (Uso en Bolsillo)

Para trabajar con las manos completamente libres:
1. Pulsa el botón de **Pantalla Bloqueada** (`Icons.screen_lock_portrait`) en la esquina superior derecha del AppBar.
2. Bloquea tu teléfono y guárdalo en el bolsillo.
3. En la pantalla de bloqueo o reloj conectado aparecerán botones de acción directa (**Identificar**, **Diagnosticar**, **Procedimiento**).
4. Al pulsar cualquiera de ellos desde la notificación, la app capturará el fotograma de las gafas, ejecutará la IA y reproducirá la respuesta directamente por el altavoz de tus gafas.

---

## 7. Gestión y Borrado de Tareas

A medida que trabajas, cada interacción queda guardada como una tarjeta en el historial:
* **Copiar respuesta:** Toca el icono de copiar (📋) en cualquier tarjeta.
* **Repetir consulta:** Toca el icono de reintentar (🔄) para repetir la petición con un nuevo fotograma.
* **Borrar tarea individual:** 
  * Pulsa el icono de papelera (🗑️) en la tarjeta, o
  * Desliza la tarjeta hacia la izquierda (*Swipe to dismiss*).
* **Borrar todo el historial:** En la cabecera del historial pulsa **"Borrar todo"** y confirma en el diálogo para limpiar la sesión.

---

## 8. Panel de Diagnóstico y Telemetría en Tiempo Real

Para técnicos y supervisores, pulsando el icono del monitor cardíaco (`Icons.monitor_heart`) se abre el panel de desarrollo con 8 pestañas:

1. **Telemetría:** Monitoreo en vivo de batería (%), voltaje ($V$), señal Wi-Fi ($dBm$), memoria Heap/PSRAM libre, tiempo de actividad (Uptime) y watchdog. Con opción de **Auto-refresco cada 2 segundos**.
2. **Inputs & Sensores:**
   * **Micrófono PDM:** Prueba de entrada de micrófono de las gafas (`/mic_sample`), nivel pico, VU meter, RMS y detección de presencia de voz.
   * **Cámara:** Visualizador del último fotograma capturado y controles de calidad JPEG, brillo y contraste en el sensor.
   * **Enlace BLE/Wi-Fi:** Acceso directo al buscador y estado de la conexión.
3. **Latencias (Waterfall):** Desglose en milisegundos de captura JPEG, inferencia LLM, TTS y streaming I2S.
4. **Filtro Voz (VoiceGate):** Calibración biométrica para que las gafas solo respondan a la voz del técnico.
5. **Hardware:** Botones para beep de prueba, autodiagnóstico (`/selftest`), reinicio remoto (`/reboot`), actualización OTA de firmware (`.bin`) y factory reset de NVS.
6. **IA & API:** Selector en 1 toque entre Google Gemini (rápido), Servidor IAPymex Local u OpenAI GPT-4o.
7. **cURL:** Exportación reproducible de la petición HTTP y visualizador del JSON crudo de respuesta.
8. **Logs:** Consola de eventos y depuración en tiempo real.

---

## 9. Resolución de Problemas Frecuentes

* **Las gafas no aparecen en el buscador:**
  * Verifica que las gafas tengan batería y el LED esté encendido.
  * Asegúrate de tener Bluetooth y Ubicación activados en tu móvil.
  * Pulsa el botón "Re-escanear" en el buscador.
* **Fallo al capturar imagen:**
  * Comprueba que las gafas y el teléfono estén en la misma red Wi-Fi o conectados al punto de acceso `XIAO-Glasses-AP` (192.168.4.1).
  * Verifica en la pestaña *Telemetría* que el estado de cámara sea `Operativa (OK)`.
* **El audio no se escucha por las gafas:**
  * Si la conexión Wi-Fi tiene latencia alta, la app automáticamente reproduce la respuesta por el altavoz del teléfono (*Audio Fallback*).
