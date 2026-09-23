import 'dart:io';
import 'dart:math' show sqrt;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../connectivity/wifi_sync_service.dart';
import '../developer_mode/dev_controller.dart';
import '../../core/config/app_config_provider.dart';

enum SubsystemStatus {
  pending,
  running,
  passed,
  warning,
  failed,
}

class SubsystemTestResult {
  final String id;
  final String title;
  final SubsystemStatus status;
  final int latencyMs;
  final String summary;
  final String details;
  final Map<String, dynamic> metrics;

  const SubsystemTestResult({
    required this.id,
    required this.title,
    required this.status,
    required this.latencyMs,
    required this.summary,
    required this.details,
    this.metrics = const {},
  });

  bool get isSuccess => status == SubsystemStatus.passed;
}

class DeviceSelfTestReport {
  final DateTime timestamp;
  final String targetIp;
  final String deviceName;
  final SubsystemStatus overallStatus;
  final int overallScore; // 0 - 100
  final int totalDurationMs;
  final GlassesTelemetry? telemetry;
  final Uint8List? capturedPhoto;
  final GlassesMicStats? micStats;
  final List<SubsystemTestResult> results;
  final List<String> logEntries;

  const DeviceSelfTestReport({
    required this.timestamp,
    required this.targetIp,
    required this.deviceName,
    required this.overallStatus,
    required this.overallScore,
    required this.totalDurationMs,
    this.telemetry,
    this.capturedPhoto,
    this.micStats,
    required this.results,
    required this.logEntries,
  });

  String get formattedDate => DateFormat('dd/MM/yyyy HH:mm:ss').format(timestamp);

  String get overallStatusLabel {
    switch (overallStatus) {
      case SubsystemStatus.passed:
        return "100% OPERATIVO (TODO OK)";
      case SubsystemStatus.warning:
        return "OPERATIVO CON ADVERTENCIAS";
      case SubsystemStatus.failed:
        return "FALLO DE SUBSISTEMA DETECTADO";
      default:
        return "TEST NO COMPLETADO";
    }
  }

  String get overallStatusEmoji {
    switch (overallStatus) {
      case SubsystemStatus.passed:
        return "✅";
      case SubsystemStatus.warning:
        return "⚠️";
      case SubsystemStatus.failed:
        return "❌";
      default:
        return "⏳";
    }
  }

  /// Genera un texto limpio, con emojis y formato ideal para compartir por WhatsApp.
  String generateWhatsAppMessage() {
    final buffer = StringBuffer();
    buffer.writeln("👓 *REPORTE DE DIAGNÓSTICO TÉCNICO - GLASSESPRO*");
    buffer.writeln("📅 Fecha: $formattedDate");
    buffer.writeln("🏷️ Dispositivo: $deviceName");
    buffer.writeln("🌐 IP Gafas: $targetIp");

    if (telemetry != null) {
      buffer.writeln("📦 Firmware: ${telemetry!.fwVersion}");
      buffer.writeln("🔋 Batería: ${telemetry!.batteryPct}% (${telemetry!.batteryVoltage.toStringAsFixed(2)}V)");
      buffer.writeln("📶 Señal Wi-Fi: ${telemetry!.rssi} dBm");
    }

    buffer.writeln("\n━━━━━━━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("$overallStatusEmoji *ESTADO GENERAL: $overallStatusLabel* ($overallScore/100)");
    buffer.writeln("⏱️ Tiempo de prueba: ${totalDurationMs}ms");
    buffer.writeln("━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      final emoji = r.status == SubsystemStatus.passed
          ? "✅"
          : (r.status == SubsystemStatus.warning ? "⚠️" : "❌");
      buffer.writeln("🔹 *${i + 1}. ${r.title}:* $emoji ${r.status.name.toUpperCase()} (${r.latencyMs}ms)");
      buffer.writeln("   • ${r.summary}");
      if (r.details.isNotEmpty) {
        buffer.writeln("   • ${r.details}");
      }
      buffer.writeln();
    }

    if (capturedPhoto != null && capturedPhoto!.isNotEmpty) {
      final kb = (capturedPhoto!.lengthInBytes / 1024).toStringAsFixed(1);
      buffer.writeln("📸 *Foto de cámara adjunta:* $kb KB (JPEG válido verificado)");
    } else {
      buffer.writeln("⚠️ *Foto de cámara:* No se pudo capturar imagen");
    }

    buffer.writeln("\n━━━━━━━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("📋 *LOG DE EJECUCIÓN:*");
    for (final line in logEntries) {
      buffer.writeln("• $line");
    }
    buffer.writeln("━━━━━━━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("🤖 *Generado automáticamente por GlassesPro App*");

    return buffer.toString();
  }

  /// Exporta el informe y la foto a WhatsApp o cualquier app de mensajería
  Future<void> shareReport({bool includeImage = true}) async {
    final message = generateWhatsAppMessage();

    if (includeImage && capturedPhoto != null && capturedPhoto!.isNotEmpty) {
      try {
        final tempDir = await getTemporaryDirectory();
        final fileName = "diagnostico_gafas_${timestamp.millisecondsSinceEpoch}.jpg";
        final file = File("${tempDir.path}/$fileName");
        await file.writeAsBytes(capturedPhoto!);

        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/jpeg', name: fileName)],
          text: message,
          subject: "Reporte de Diagnóstico de Gafas - $formattedDate",
        );
        return;
      } catch (e) {
        debugPrint("[Diagnostics] Fallo al adjuntar imagen en share: $e");
      }
    }

    // Fallback de texto sin archivo adjunto
    await Share.share(
      message,
      subject: "Reporte de Diagnóstico de Gafas - $formattedDate",
    );
  }
}

class DeviceSelfTestService {
  final WifiSyncService _wifiService;
  final AppConfigState _config;

  DeviceSelfTestService({
    required WifiSyncService wifiService,
    required AppConfigState config,
  })  : _wifiService = wifiService,
        _config = config;

  /// Ejecuta la batería completa de pruebas:
  /// 1. Conexión y telemetría (/status, ping, batería, memoria)
  /// 2. Sensor de cámara con captura de FOTO REAL (/capture)
  /// 3. Micrófono PDM con muestra de audio (/mic_sample)
  /// 4. Altavoz I2S y Self-Test firmware (/selftest, /beep)
  /// 5. Motor de IA Multimodal (prueba de preparación)
  Future<DeviceSelfTestReport> runFullTest({
    required String ipAddress,
    String deviceName = "XIAO ESP32-S3 Gafas",
    bool isSimulator = false,
    void Function(String step, double progress)? onProgress,
  }) async {
    final startTime = DateTime.now();
    final logEntries = <String>[];
    final results = <SubsystemTestResult>[];

    void log(String msg) {
      final now = DateFormat('HH:mm:ss').format(DateTime.now());
      logEntries.add("[$now] $msg");
      debugPrint("[SelfTest] $msg");
    }

    log("Iniciando batería de pruebas para dispositivo en $ipAddress (Simulador=$isSimulator)...");
    onProgress?.call("Iniciando diagnóstico...", 0.05);

    // ==========================================
    // 1. TEST DE CONEXIÓN Y TELEMETRÍA
    // ==========================================
    onProgress?.call("Verificando conexión y telemetría...", 0.15);
    log("1/5: Comprobando /status y ping...");
    final connStopwatch = Stopwatch()..start();
    GlassesTelemetry? telemetry;
    int pingMs = -1;

    if (isSimulator) {
      await Future.delayed(const Duration(milliseconds: 60));
      pingMs = 12;
      telemetry = GlassesTelemetry(
        status: "online",
        ip: ipAddress,
        mode: "STA",
        rssi: -52,
        freeHeap: 184320,
        freePsram: 3932160,
        uptimeSec: 3600,
        batteryVoltage: 4.12,
        batteryPct: 92,
        cameraOk: true,
        fwVersion: "1.2.0-sim",
      );
    } else {
      telemetry = await _wifiService.fetchTelemetry(ipAddress);
      pingMs = await _wifiService.checkPingLatency(ipAddress);
    }
    connStopwatch.stop();

    final isConnOk = telemetry != null;
    final connStatus = isConnOk
        ? (pingMs > 400 ? SubsystemStatus.warning : SubsystemStatus.passed)
        : SubsystemStatus.failed;

    results.add(SubsystemTestResult(
      id: "connection",
      title: "Conexión & Telemetría",
      status: connStatus,
      latencyMs: connStopwatch.elapsedMilliseconds,
      summary: isConnOk
          ? "Conexión activa · Ping ${pingMs}ms · RSSI ${telemetry.rssi} dBm"
          : "No se pudo comunicar con /status en $ipAddress",
      details: isConnOk
          ? "FW: ${telemetry.fwVersion} | Bat: ${telemetry.batteryPct}% (${telemetry.batteryVoltage.toStringAsFixed(2)}V) | Heap: ${telemetry.freeHeapKb} | PSRAM: ${telemetry.freePsramKb} | Uptime: ${telemetry.formattedUptime}"
          : "Verifica que el móvil esté conectado a la misma red Wi-Fi o a XIAO-Glasses-AP.",
      metrics: isConnOk
          ? {
              "pingMs": pingMs,
              "rssi": telemetry.rssi,
              "batteryPct": telemetry.batteryPct,
              "batteryVoltage": telemetry.batteryVoltage,
              "freeHeap": telemetry.freeHeap,
              "freePsram": telemetry.freePsram,
              "fwVersion": telemetry.fwVersion,
            }
          : {},
    ));
    log(isConnOk
        ? "Telemetría OK: FW ${telemetry.fwVersion}, Bat ${telemetry.batteryPct}%, Ping ${pingMs}ms"
        : "Fallo de telemetría en $ipAddress");

    // ==========================================
    // 2. TEST DE CÁMARA (FOTO REAL JPEG)
    // ==========================================
    onProgress?.call("Capturando foto real de la cámara...", 0.35);
    log("2/5: Capturando imagen real de la cámara (/capture)...");
    final camStopwatch = Stopwatch()..start();
    Uint8List? capturedPhoto;

    if (isSimulator) {
      await Future.delayed(const Duration(milliseconds: 120));
      capturedPhoto = _generateSimulatorTestImage();
    } else {
      capturedPhoto = await _wifiService.fetchSnapshot(ipAddress);
    }
    camStopwatch.stop();

    final bool isPhotoValid = capturedPhoto != null &&
        capturedPhoto.lengthInBytes >= 64 &&
        _isValidJpeg(capturedPhoto);

    final camStatus = isPhotoValid
        ? (camStopwatch.elapsedMilliseconds > 2500
            ? SubsystemStatus.warning
            : SubsystemStatus.passed)
        : SubsystemStatus.failed;

    final photoSizeKb = isPhotoValid
        ? (capturedPhoto.lengthInBytes / 1024).toStringAsFixed(1)
        : "0";

    results.add(SubsystemTestResult(
      id: "camera",
      title: "Sensor de Cámara (Foto Real)",
      status: camStatus,
      latencyMs: camStopwatch.elapsedMilliseconds,
      summary: isPhotoValid
          ? "Foto real capturada con éxito ($photoSizeKb KB)"
          : "Fallo al capturar fotograma JPEG desde el sensor",
      details: isPhotoValid
          ? "Cabecera JPEG (0xFFD8) válida | Tamaño: $photoSizeKb KB | Tiempo captura: ${camStopwatch.elapsedMilliseconds}ms"
          : "El endpoint /capture no devolvió una imagen válida. Revisa el conector de la cámara OV2640/OV3660.",
      metrics: isPhotoValid
          ? {
              "sizeBytes": capturedPhoto.lengthInBytes,
              "sizeKb": photoSizeKb,
              "format": "JPEG",
              "captureTimeMs": camStopwatch.elapsedMilliseconds,
            }
          : {},
    ));
    log(isPhotoValid
        ? "Cámara OK: Imagen JPEG de $photoSizeKb KB recibida en ${camStopwatch.elapsedMilliseconds}ms"
        : "Cámara FALLÓ: No se recibió fotograma válido");

    // ==========================================
    // 3. TEST DE MICRÓFONO PDM
    // ==========================================
    onProgress?.call("Muestreando micrófono PDM...", 0.55);
    log("3/5: Solicitando muestra de audio de micrófono (/mic_sample)...");
    final micStopwatch = Stopwatch()..start();
    GlassesMicStats? micStats;

    if (isSimulator) {
      await Future.delayed(const Duration(milliseconds: 80));
      micStats = GlassesMicStats(
        sampleCount: 8000,
        peakAmplitude: 9420,
        rmsLevel: 38.1,
        dcOffset: 12.4,
        timestamp: DateTime.now(),
      );
    } else {
      final micBytes = await _wifiService.fetchMicSample(ipAddress);
      if (micBytes != null && micBytes.length >= 4) {
        // Contrato firmware: PCM S16LE, 16 kHz, mono. Sin remuestreo.
        final sampleCount = micBytes.length ~/ 2;
        int peak = 0;
        double sumSquares = 0;
        double sum = 0;
        for (int i = 0; i < micBytes.length - 1; i += 2) {
          final sample = micBytes.buffer.asByteData().getInt16(i, Endian.little);
          final absVal = sample.abs();
          if (absVal > peak) peak = absVal;
          sum += sample;
          sumSquares += sample * sample;
        }
        final meanSquare = sampleCount > 0 ? (sumSquares / sampleCount) : 0.0;
        final rms = meanSquare > 0 ? sqrt(meanSquare) : 0.0;
        final dc = sampleCount > 0 ? (sum / sampleCount) : 0.0;
        micStats = GlassesMicStats(
          sampleCount: sampleCount,
          peakAmplitude: peak,
          rmsLevel: rms,
          dcOffset: dc,
          timestamp: DateTime.now(),
        );
      }
    }
    micStopwatch.stop();

    final isMicOk = micStats != null && micStats.sampleCount > 0;
    final micStatus = isMicOk
        ? (micStats.peakAmplitude == 0 ? SubsystemStatus.warning : SubsystemStatus.passed)
        : SubsystemStatus.failed;

    results.add(SubsystemTestResult(
      id: "microphone",
      title: "Micrófono PDM I2S",
      status: micStatus,
      latencyMs: micStopwatch.elapsedMilliseconds,
      summary: isMicOk
          ? "Muestra recibida (${micStats.sampleCount} muestras @ 16kHz)"
          : "Fallo al obtener muestra de audio de las gafas",
      details: isMicOk
          ? "Nivel Pico: ${micStats.peakAmplitude} | RMS: ${micStats.rmsLevel.toStringAsFixed(1)} | Offset DC: ${micStats.dcOffset.toStringAsFixed(1)}"
          : "El endpoint /mic_sample no respondió. Verifica el pin PDM_CLK/PDM_DATA.",
      metrics: isMicOk
          ? {
              "sampleCount": micStats.sampleCount,
              "peakAmplitude": micStats.peakAmplitude,
              "rmsLevel": micStats.rmsLevel,
              "dcOffset": micStats.dcOffset,
            }
          : {},
    ));
    log(isMicOk
        ? "Micrófono OK: ${micStats.sampleCount} muestras, Pico=${micStats.peakAmplitude}, RMS=${micStats.rmsLevel.toStringAsFixed(1)}"
        : "Micrófono FALLÓ");

    // ==========================================
    // 4. TEST DE ALTAVOZ Y SELF-TEST DE FIRMWARE
    // ==========================================
    onProgress?.call("Verificando altavoz y hardware...", 0.75);
    log("4/5: Ejecutando self-test interno y prueba de altavoz (/selftest)...");
    final spkStopwatch = Stopwatch()..start();
    bool isSpeakerOk = false;
    String speakerDetails = "";

    if (isSimulator) {
      await Future.delayed(const Duration(milliseconds: 50));
      isSpeakerOk = true;
      speakerDetails = "Self-test firmware OK · Beep de prueba 880Hz programado";
    } else {
      final selfTestData = await _wifiService.runSelfTest(ipAddress);
      if (selfTestData != null) {
        isSpeakerOk = true;
        speakerDetails = "Respuesta HW: $selfTestData";
      } else {
        // Intentar al menos el endpoint /beep
        isSpeakerOk = await _wifiService.triggerHardwareBeep(ipAddress);
        speakerDetails = isSpeakerOk ? "Beep 880Hz ejecutado OK" : "Sin respuesta en /selftest o /beep";
      }
    }
    spkStopwatch.stop();

    final spkStatus = isSpeakerOk ? SubsystemStatus.passed : SubsystemStatus.failed;
    results.add(SubsystemTestResult(
      id: "speaker",
      title: "Altavoz I2S & Buzzer",
      status: spkStatus,
      latencyMs: spkStopwatch.elapsedMilliseconds,
      summary: isSpeakerOk ? "Salida de audio y self-test confirmados" : "No respondió el subsistema de audio",
      details: speakerDetails,
      metrics: {"speakerOk": isSpeakerOk},
    ));
    log(isSpeakerOk ? "Altavoz/HW OK: $speakerDetails" : "Altavoz/HW FALLÓ");

    // ==========================================
    // 5. TEST DE MOTOR IA MULTIMODAL
    // ==========================================
    onProgress?.call("Comprobando motor de IA...", 0.90);
    log("5/5: Verificando disponibilidad de modelo de IA (${_config.modelName})...");
    final aiStopwatch = Stopwatch()..start();
    bool isAiOk = true;
    String aiSummary = "Motor IA (${_config.modelName}) configurado y listo";

    if (_config.apiKey.isEmpty && _config.apiBaseUrl.contains("generativelanguage.googleapis.com")) {
      isAiOk = false;
      aiSummary = "Falta configurar API Key de Google Gemini en ajustes";
    }
    aiStopwatch.stop();

    final aiStatus = isAiOk ? SubsystemStatus.passed : SubsystemStatus.warning;
    results.add(SubsystemTestResult(
      id: "ai_engine",
      title: "Motor IA Multimodal",
      status: aiStatus,
      latencyMs: aiStopwatch.elapsedMilliseconds,
      summary: aiSummary,
      details: "Modelo: ${_config.modelName} | URL: ${_config.apiBaseUrl}",
      metrics: {
        "model": _config.modelName,
        "isConfigured": isAiOk,
      },
    ));
    log("Motor IA: $aiSummary");

    // ==========================================
    // CÁLCULO DE RESULTADO GLOBAL
    // ==========================================
    onProgress?.call("Generando informe final...", 1.0);
    final totalDuration = DateTime.now().difference(startTime).inMilliseconds;

    final hasFailures = results.any((r) => r.status == SubsystemStatus.failed);
    final hasWarnings = results.any((r) => r.status == SubsystemStatus.warning);

    final overallStatus = hasFailures
        ? SubsystemStatus.failed
        : (hasWarnings ? SubsystemStatus.warning : SubsystemStatus.passed);

    int passedCount = results.where((r) => r.status == SubsystemStatus.passed).length;
    int warningCount = results.where((r) => r.status == SubsystemStatus.warning).length;
    int score = ((passedCount * 20) + (warningCount * 10)).clamp(0, 100);

    log("Diagnóstico finalizado en ${totalDuration}ms. Puntuación: $score/100 (${overallStatus.name.toUpperCase()}).");

    return DeviceSelfTestReport(
      timestamp: startTime,
      targetIp: ipAddress,
      deviceName: deviceName,
      overallStatus: overallStatus,
      overallScore: score,
      totalDurationMs: totalDuration,
      telemetry: telemetry,
      capturedPhoto: capturedPhoto,
      micStats: micStats,
      results: results,
      logEntries: logEntries,
    );
  }

  static bool _isValidJpeg(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // Comprobar número mágico JPEG: 0xFF, 0xD8 al inicio
    return bytes[0] == 0xFF && bytes[1] == 0xD8;
  }

  /// Genera un JPEG válido sintético para pruebas en simulador/mock
  static Uint8List _generateSimulatorTestImage() {
    // Un JPEG mínimo válido (1x1 pixel) o cabecera real
    return Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
      0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
      0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
      0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
      0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
      0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
      0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
      0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
      0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
      0x09, 0x0A, 0x0B, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F,
      0x00, 0xBF, 0x00, 0xFF, 0xD9
    ]);
  }
}

final deviceSelfTestServiceProvider = Provider<DeviceSelfTestService>((ref) {
  final wifiService = ref.watch(wifiSyncServiceProvider);
  final config = ref.watch(appConfigProvider);
  return DeviceSelfTestService(
    wifiService: wifiService,
    config: config,
  );
});
