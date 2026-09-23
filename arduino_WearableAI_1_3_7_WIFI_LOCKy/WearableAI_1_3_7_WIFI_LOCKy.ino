#include <WiFi.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <WebServer.h>
#include "esp_camera.h"
#include <ESP_I2S.h>

// ============================================================
// WearableAI - BASE BUENA INTEGRADA
// Basado DIRECTAMENTE en:
// XIAO_TEST_WIFI_BLE_HTTP_CAM_MIC_SPEAKER(1).ino
//
// IMPORTANTE:
// - WIFI_AP solamente
// - WebServer.h
// - SIN WIFI_AP_STA
// - SIN reconexion STA
// - SIN mDNS
// - SIN apagar/reiniciar el AP
// ============================================================

const char* FW_VERSION = "1.4.11-MIC-STREAM-100MS";
const char* AP_SSID = "XIAO-Glasses-AP";
const char* AP_PASS = "12345678";
const char* BLE_NAME = "XIAO-SmartGlasses";

WebServer server(80);

I2SClass MicI2S(I2S_NUM_0);
I2SClass SpeakerI2S(I2S_NUM_1);

// ---------------- CAMARA XIAO ESP32-S3 SENSE ----------------
#define PWDN_GPIO_NUM  -1
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM  10
#define SIOD_GPIO_NUM  40
#define SIOC_GPIO_NUM  39
#define Y9_GPIO_NUM    48
#define Y8_GPIO_NUM    11
#define Y7_GPIO_NUM    12
#define Y6_GPIO_NUM    14
#define Y5_GPIO_NUM    16
#define Y4_GPIO_NUM    18
#define Y3_GPIO_NUM    17
#define Y2_GPIO_NUM    15
#define VSYNC_GPIO_NUM 38
#define HREF_GPIO_NUM  47
#define PCLK_GPIO_NUM  13

// ---------------- MICROFONO PDM ----------------
#define MIC_CLK  42
#define MIC_DATA 41

// ---------------- ALTAVOZ MAX98357A ----------------
#define SPK_BCLK 7
#define SPK_LRC  8
#define SPK_DIN  9

bool cameraOK = false;
bool micOK = false;
bool speakerOK = false;

// ============================================================
// CAMARA
// ============================================================
bool initCamera() {
  camera_config_t c = {};
  c.ledc_channel = LEDC_CHANNEL_0;
  c.ledc_timer = LEDC_TIMER_0;

  c.pin_d0 = Y2_GPIO_NUM;
  c.pin_d1 = Y3_GPIO_NUM;
  c.pin_d2 = Y4_GPIO_NUM;
  c.pin_d3 = Y5_GPIO_NUM;
  c.pin_d4 = Y6_GPIO_NUM;
  c.pin_d5 = Y7_GPIO_NUM;
  c.pin_d6 = Y8_GPIO_NUM;
  c.pin_d7 = Y9_GPIO_NUM;

  c.pin_xclk = XCLK_GPIO_NUM;
  c.pin_pclk = PCLK_GPIO_NUM;
  c.pin_vsync = VSYNC_GPIO_NUM;
  c.pin_href = HREF_GPIO_NUM;
  c.pin_sccb_sda = SIOD_GPIO_NUM;
  c.pin_sccb_scl = SIOC_GPIO_NUM;
  c.pin_pwdn = PWDN_GPIO_NUM;
  c.pin_reset = RESET_GPIO_NUM;

  c.xclk_freq_hz = 20000000;
  c.pixel_format = PIXFORMAT_JPEG;
  c.frame_size = FRAMESIZE_QVGA;
  c.jpeg_quality = 12;
  c.fb_count = 1;
  c.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  c.fb_location = CAMERA_FB_IN_DRAM;

  return esp_camera_init(&c) == ESP_OK;
}

// ============================================================
// MICROFONO
// ============================================================
bool initMic() {
  MicI2S.setPinsPdmRx(MIC_CLK, MIC_DATA);
  bool ok = MicI2S.begin(
    I2S_MODE_PDM_RX, 16000,
    I2S_DATA_BIT_WIDTH_16BIT,
    I2S_SLOT_MODE_MONO
  );
  if (!ok) return false;
  delay(150);
  char dummy[256];
  size_t discarded = MicI2S.readBytes(dummy, sizeof(dummy));
  Serial.printf("[MIC] Arranque: %u bytes descartados\n", (unsigned)discarded);
  return true;
}

// ============================================================
// ALTAVOZ
// ============================================================
bool initSpeaker() {
  SpeakerI2S.setPins(SPK_BCLK, SPK_LRC, SPK_DIN, -1);
  return SpeakerI2S.begin(
    I2S_MODE_STD, 16000,
    I2S_DATA_BIT_WIDTH_16BIT,
    I2S_SLOT_MODE_STEREO
  );
}

void beep(unsigned int ms = 180) {
  if (!speakerOK) return;
  const int sampleRate = 16000, frequency = 880;
  const int totalSamples = (sampleRate * ms) / 1000;
  const size_t chunkSize = 128;
  int16_t stereo[chunkSize * 2];
  int generated = 0;
  while (generated < totalSamples) {
    size_t count = min((int)chunkSize, totalSamples - generated);
    for (size_t i=0; i<count; i++) {
      int n = generated + (int)i;
      int period = sampleRate / frequency;
      int16_t v = ((n % period) < (period / 2)) ? 5000 : -5000;
      stereo[i*2]=v; stereo[i*2+1]=v;
    }
    SpeakerI2S.write((uint8_t*)stereo, count * 2 * sizeof(int16_t));
    generated += count;
  }
}

// ============================================================
// HTTP
// ============================================================
void setupHttp() {

  server.on("/", HTTP_GET, []() {
    Serial.println("[HTTP] /");
    server.send(200, "text/plain", "XIAO OK");
  });

  server.on("/status", HTTP_GET, []() {
    Serial.println("[HTTP] /status");

    String json = "{";
    json += "\"fw\":\"" + String(FW_VERSION) + "\",";
    json += "\"ip\":\"" + WiFi.softAPIP().toString() + "\",";
    json += "\"clients\":" + String(WiFi.softAPgetStationNum()) + ",";
    json += "\"camera\":" + String(cameraOK ? "true" : "false") + ",";
    json += "\"mic\":" + String(micOK ? "true" : "false") + ",";
    json += "\"speaker\":" + String(speakerOK ? "true" : "false");
    json += "}";

    server.send(200, "application/json", json);
  });

  server.on("/selftest", HTTP_GET, []() {
    Serial.println("[HTTP] /selftest");

    size_t jpegBytes = 0;
    bool captureOK = false;

    if (cameraOK) {
      camera_fb_t* fb = esp_camera_fb_get();
      if (fb) {
        jpegBytes = fb->len;
        captureOK = true;
        esp_camera_fb_return(fb);
      }
    }

    if (server.hasArg("beep") && server.arg("beep") == "1") {
      beep();
    }

    String json = "{";
    json += "\"fw\":\"" + String(FW_VERSION) + "\",";
    json += "\"camera\":" + String(cameraOK ? "true" : "false") + ",";
    json += "\"capture\":" + String(captureOK ? "true" : "false") + ",";
    json += "\"jpeg_bytes\":" + String(jpegBytes) + ",";
    json += "\"mic\":" + String(micOK ? "true" : "false") + ",";
    json += "\"speaker\":" + String(speakerOK ? "true" : "false");
    json += "}";

    server.send(200, "application/json", json);
  });

  server.on("/capture", HTTP_GET, []() {
    Serial.println("[HTTP] /capture");

    if (!cameraOK) {
      server.send(503, "text/plain", "camera_not_ready");
      return;
    }

    camera_fb_t* fb = esp_camera_fb_get();
    if (!fb) {
      server.send(500, "text/plain", "capture_failed");
      return;
    }

    Serial.printf("[CAMARA] JPEG %u bytes\n", (unsigned)fb->len);

    server.setContentLength(fb->len);
    server.send(200, "image/jpeg", "");

    WiFiClient client = server.client();
    size_t sent = 0;

    while (sent < fb->len && client.connected()) {
      size_t chunk = fb->len - sent;
      if (chunk > 1024) chunk = 1024;

      size_t n = client.write(fb->buf + sent, chunk);
      if (n == 0) break;

      sent += n;
      delay(0);
    }

    esp_camera_fb_return(fb);
    Serial.printf("[HTTP] /capture enviados %u bytes\n", (unsigned)sent);
  });

  // ------------------------------------------------------------
  // MICROFONO PARA ASR
  // 100 ms exactos por peticion:
  // 16.000 muestras/s * 2 bytes * 0,100 s = 3.200 bytes.
  //
  // La version anterior capturaba 16.000 bytes (~500 ms) y cada
  // peticion HTTP podia introducir pausas grandes entre bloques.
  // Para reconocimiento continuo enviamos bloques cortos y frescos.
  // ------------------------------------------------------------
  server.on("/mic_sample", HTTP_GET, []() {
    if (!micOK) {
      server.send(503, "text/plain", "mic_not_ready");
      return;
    }

    const size_t targetBytes = 3200;   // 100 ms PCM S16LE mono 16 kHz
    const size_t blockSize   = 512;
    static uint8_t audio[targetBytes];

    size_t total = 0;
    unsigned long started = millis();

    // Limite holgado: un bloque real dura 100 ms.
    while (total < targetBytes && (millis() - started) < 350) {
      const size_t remaining = targetBytes - total;
      const size_t requestSize =
        remaining > blockSize ? blockSize : remaining;

      const size_t got =
        MicI2S.readBytes((char*)audio + total, requestSize);

      if (got > 0) {
        total += got;
      } else {
        delay(1);
      }

      // Mantiene vivos Wi-Fi/RTOS mientras leemos PDM.
      delay(0);
    }

    if (total < targetBytes) {
      Serial.printf("[MIC] bloque incompleto %u/%u bytes\n", (unsigned)total, (unsigned)targetBytes);

      if (total == 0) {
        server.send(503, "text/plain", "microphone_no_data");
        return;
      }
    }

    server.setContentLength(total);
    server.send(200, "application/octet-stream", "");

    WiFiClient client = server.client();
    size_t sent = 0;

    while (sent < total && client.connected()) {
      size_t chunk = total - sent;
      if (chunk > 1024) chunk = 1024;

      const size_t n = client.write(audio + sent, chunk);
      if (n == 0) break;

      sent += n;
      delay(0);
    }

    // No imprimimos una linea por cada bloque correcto: el modo IA
    // puede pedir muchos bloques por segundo y saturar el Serial.
    if (sent != total) {
      Serial.printf("[MIC] envio incompleto %u/%u bytes\n", (unsigned)sent, (unsigned)total);
    }
  });

  server.on("/beep", HTTP_GET, []() {
    Serial.println("[HTTP] /beep");

    if (!speakerOK) {
      server.send(503, "text/plain", "speaker_not_ready");
      return;
    }

    beep();
    server.send(200, "text/plain", "OK");
  });

  // PCM S16LE mono, 16 kHz.
  // La app envia el audio en el cuerpo de un POST.
  // Se reproduce por bloques para no reservar un buffer grande en RAM.
  server.on("/play_audio", HTTP_POST,
    []() {
      Serial.println("[HTTP] /play_audio fin");
      server.send(200, "text/plain", "OK");
    },
    []() {
      HTTPUpload& upload = server.upload();

      if (!speakerOK) {
        return;
      }

      if (upload.status == UPLOAD_FILE_START) {
        Serial.println("[HTTP] /play_audio inicio");
        /* ESP_I2S: no usa zero_dma legacy */
      }
      else if (upload.status == UPLOAD_FILE_WRITE) {
        const uint8_t* p = upload.buf;
        size_t bytes = upload.currentSize;

        // Entrada mono 16-bit -> salida estereo L/R para MAX98357A.
        const size_t samples = bytes / 2;
        int16_t stereo[256 * 2];

        size_t pos = 0;
        while (pos < samples) {
          size_t n = samples - pos;
          if (n > 256) n = 256;

          for (size_t i = 0; i < n; ++i) {
            int16_t s;
            memcpy(&s, p + ((pos + i) * 2), sizeof(int16_t));
            stereo[i * 2] = s;
            stereo[i * 2 + 1] = s;
          }

          size_t written = SpeakerI2S.write(
            (uint8_t*)stereo,
            n * 2 * sizeof(int16_t)
          );
          if (written == 0) break;
          pos += n;
        }
      }
      else if (upload.status == UPLOAD_FILE_END) {
        Serial.printf("[HTTP] /play_audio recibidos %u bytes\n",
                      (unsigned)upload.totalSize);
        /* ESP_I2S: no usa zero_dma legacy */
      }
      else if (upload.status == UPLOAD_FILE_ABORTED) {
        Serial.println("[HTTP] /play_audio abortado");
        /* ESP_I2S: no usa zero_dma legacy */
      }
    }
  );

  server.onNotFound([]() {
    Serial.print("[HTTP] 404 ");
    Serial.println(server.uri());
    server.send(404, "text/plain", "not_found");
  });

  server.begin();
  Serial.println("HTTP: OK - WebServer puerto 80");
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(1500);

  Serial.println();
  Serial.println("========================================");
  Serial.println(" WearableAI 1.4.11 - MIC STREAM 100MS");
  Serial.println("========================================");

  // EXACTAMENTE el esquema Wi-Fi de la base que funcionaba.
  WiFi.mode(WIFI_AP);
  WiFi.setSleep(false);

  bool apOK = WiFi.softAP(AP_SSID, AP_PASS);

  Serial.printf("SoftAP: %s\n", apOK ? "OK" : "ERROR");
  Serial.print("SSID: ");
  Serial.println(AP_SSID);
  Serial.print("IP: ");
  Serial.println(WiFi.softAPIP());

  // BLE simple: no modifica Wi-Fi.
  BLEDevice::init(BLE_NAME);
  BLEDevice::createServer();
  BLEDevice::getAdvertising()->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.print("BLE: OK - ");
  Serial.println(BLE_NAME);

  // HTTP con la misma libreria WebServer.h de la base buena.
  setupHttp();

  cameraOK = initCamera();
  Serial.printf("CAMARA: %s\n", cameraOK ? "OK" : "ERROR");

  if (cameraOK) {
    camera_fb_t* fb = esp_camera_fb_get();
    if (fb) {
      Serial.printf("CAMARA JPEG: %u bytes\n", (unsigned)fb->len);
      esp_camera_fb_return(fb);
    }
  }

  micOK = initMic();
  Serial.printf("MICROFONO PDM: %s\n", micOK ? "OK" : "ERROR");

  speakerOK = initSpeaker();
  Serial.printf("ALTAVOZ I2S: %s\n", speakerOK ? "OK" : "ERROR");

  Serial.println("----------------------------------------");
  Serial.println("LISTO");
  Serial.println("Conecta el movil a XIAO-Glasses-AP");
  Serial.println("Prueba: http://192.168.4.1/status");
  Serial.println("----------------------------------------");
}

// ============================================================
// LOOP
// ============================================================
void loop() {
  server.handleClient();

  static int lastClients = -1;
  int clients = WiFi.softAPgetStationNum();

  if (clients != lastClients) {
    Serial.printf("Clientes conectados: %d\n", clients);
    lastClients = clients;
  }

  delay(20);
}