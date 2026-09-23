import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Formato exacto del endpoint GET /mic_sample del firmware.
/// PCM signed 16-bit little-endian, 16.000 Hz, mono, SIN cabecera.
/// Fuente única de verdad: toda reproducción o guardado a WAV debe usar
/// estos valores o el audio sonará acelerado/con ruido.
class MicSampleFormat {
  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int bitsPerSample = 16;

  static int get bytesPerSecond => sampleRate * channels * (bitsPerSample ~/ 8);

  /// Duración aproximada en segundos de una muestra cruda.
  static double durationSec(Uint8List rawPcm) => rawPcm.length / bytesPerSecond;
}

class GlassesTelemetry {  final String status;
  final String ip;
  final String staIp;
  final String apIp;
  final String mode;
  final int rssi;
  final int freeHeap;
  final int freePsram;
  final int uptimeSec;
  final double batteryVoltage;
  final int batteryPct;
  final bool cameraOk;
  final int cameraFailures;
  final int wdtSec;
  final String fwVersion;
  final int heapFragPct;
  final int wifiReconnects;
  final int i2sMicErrors;
  final int i2sSpkErrors;
  final int cameraCaptures;
  final int cameraCorrupt;
  final Map<String, dynamic> rawJson;

  GlassesTelemetry({
    required this.status,
    required this.ip,
    this.staIp = '0.0.0.0',
    this.apIp = '192.168.4.1',
    required this.mode,
    required this.rssi,
    required this.freeHeap,
    required this.freePsram,
    required this.uptimeSec,
    required this.batteryVoltage,
    required this.batteryPct,
    this.cameraOk = true,
    this.cameraFailures = 0,
    this.wdtSec = 10,
    this.fwVersion = 'unknown',
    this.heapFragPct = 0,
    this.wifiReconnects = 0,
    this.i2sMicErrors = 0,
    this.i2sSpkErrors = 0,
    this.cameraCaptures = 0,
    this.cameraCorrupt = 0,
    this.rawJson = const {},
  });

  String get formattedUptime {
    final d = uptimeSec ~/ 86400;
    final h = (uptimeSec % 86400) ~/ 3600;
    final m = (uptimeSec % 3600) ~/ 60;
    final s = uptimeSec % 60;
    if (d > 0) return "${d}d ${h}h ${m}m";
    if (h > 0) return "${h}h ${m}m ${s}s";
    if (m > 0) return "${m}m ${s}s";
    return "${s}s";
  }

  String get freeHeapKb => "${(freeHeap / 1024).toStringAsFixed(1)} KB";
  String get freePsramKb => "${(freePsram / 1024).toStringAsFixed(1)} KB";

  factory GlassesTelemetry.fromJson(Map<String, dynamic> json) {
    // Acepta alias HTTP (/status) + BLE notify corto (b/c/r, cam_ok, heap_frag).
    int asInt(dynamic v, int fb) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fb : fb);
    return GlassesTelemetry(
      status: (json['status'] ?? 'unknown').toString(),
      ip: (json['ip'] ?? json['sta_ip'] ?? '0.0.0.0').toString(),
      staIp: (json['sta_ip'] ?? json['ip'] ?? '0.0.0.0').toString(),
      apIp: (json['ap_ip'] ?? '192.168.4.1').toString(),
      mode: (json['mode'] ?? 'STA').toString(),
      rssi: asInt(json['rssi'] ?? json['r'], 0),
      freeHeap: asInt(json['free_heap'] ?? json['heap'], 0),
      freePsram: asInt(json['free_psram'] ?? json['psram'], 0),
      uptimeSec: asInt(json['uptime_sec'], 0),
      batteryVoltage: (json['battery_voltage'] as num?)?.toDouble() ?? 3.7,
      batteryPct: asInt(json['battery_pct'] ?? json['b'], 100),
      cameraOk: json.containsKey('camera_ok')
          ? json['camera_ok'] == true
          : json.containsKey('cam_ok')
              ? json['cam_ok'] == true
              : json.containsKey('c')
                  ? json['c'] == true
                  : true,
      cameraFailures: asInt(json['camera_failures'] ?? json['camera_fail'] ?? json['cam_fail'], 0),
      wdtSec: asInt(json['wdt_sec'], 10),
      fwVersion: (json['fw'] ?? json['fw_version'] ?? 'unknown').toString(),
      heapFragPct: asInt(json['heap_frag_pct'] ?? json['heap_frag'], 0),
      wifiReconnects: asInt(json['wifi_reconnects'], 0),
      i2sMicErrors: asInt(json['i2s_mic_errors'] ?? json['mic_errors'], 0),
      i2sSpkErrors: asInt(json['i2s_spk_errors'] ?? json['speaker_errors'], 0),
      cameraCaptures: asInt(json['camera_captures'] ?? json['cam_caps'] ?? json['camera_captures_total'], 0),
      cameraCorrupt: asInt(json['camera_corrupt'] ?? json['cam_corrupt'] ?? json['camera_corrupt_total'], 0),
      rawJson: json,
    );
  }
}

class WifiSyncService {
  WifiSyncService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Captura un fotograma con opción de preset ('text_screen', 'balanced', 'outdoor')
  /// y compensación de exposición (-2 a +2). Reintenta 3 veces con backoff.
  Future<Uint8List?> fetchSnapshot(
    String ipAddress, {
    String? preset,
    int? aeLevel,
  }) async {
    var uri = Uri.parse("http://$ipAddress/capture");
    final queryParams = <String, String>{};
    if (preset != null && preset.isNotEmpty) queryParams["preset"] = preset;
    if (aeLevel != null) queryParams["ae"] = aeLevel.toString();

    if (queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _client.get(uri).timeout(const Duration(seconds: 7));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
        // 503 cámara ocupada -> backoff y reintento; otro código -> salir.
        if (response.statusCode != 503) {
          debugPrint("[Camera] HTTP ${response.statusCode}: ${response.body}");
          return null;
        }
        debugPrint("[Camera] busy 503, reintento ${attempt + 1}/3");
      } catch (e) {
        debugPrint("[Camera] Error al obtener snapshot (intento ${attempt + 1}): $e");
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    return null;
  }

  /// Envía configuración dinámica de cámara (preset, exposición, calidad)
  Future<bool> updateCameraSettings(
    String ipAddress, {
    String? preset,
    int? aeLevel,
    int? quality,
  }) async {
    final uri = Uri.parse("http://$ipAddress/camera_settings");
    final payload = <String, dynamic>{};
    if (preset != null) payload["preset"] = preset;
    if (aeLevel != null) payload["ae_level"] = aeLevel;
    if (quality != null) payload["quality"] = quality;

    try {
      final response = await _client.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendAudioToGlasses(String ipAddress, Uint8List audioBytes) async {
    final uri = Uri.parse("http://$ipAddress/play_audio");
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client.post(
          uri,
          headers: {"Content-Type": "application/octet-stream"},
          body: audioBytes,
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) return true;
      } catch (_) {}
      if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  /// Muestra cruda de GET /mic_sample.
  /// Contrato firmware: [MicSampleFormat] (S16LE, 16 kHz, mono, sin cabecera).
  /// Se devuelve TAL CUAL, sin remuestrear ni reinterpretar: cualquier
  /// transformación de formato aquí rompería la reproducción.
  Future<Uint8List?> fetchMicSample(String ipAddress) async {
    final uri = Uri.parse("http://$ipAddress/mic_sample");
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client.get(uri).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) return response.bodyBytes;
        if (response.statusCode != 503) return null;
      } catch (_) {}
      if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  Future<bool> triggerHardwareBeep(String ipAddress) async {
    return _simpleGetOk(ipAddress, "/beep", seconds: 2);
  }

  Future<bool> rebootDevice(String ipAddress) async {
    return _simplePostOk(ipAddress, "/reboot", seconds: 2);
  }

  Future<bool> factoryResetDevice(String ipAddress) async {
    return _simplePostOk(ipAddress, "/factory_reset", seconds: 3);
  }

  Future<Map<String, dynamic>?> runSelfTest(String ipAddress) async {
    try {
      final response = await _client
          .get(Uri.parse("http://$ipAddress/selftest"))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> uploadOtaFirmware(String ipAddress, Uint8List firmwareBin) async {
    final uri = Uri.parse("http://$ipAddress/update");
    try {
      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        http.MultipartFile.fromBytes('firmware', firmwareBin, filename: 'firmware.bin'),
      );
      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);
      return response.statusCode == 200 && response.body.contains("OK_UPDATE");
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateCameraConfig(
    String ipAddress, {
    int quality = 12,
    int brightness = 1,
    int contrast = 1,
  }) async {
    final uri = Uri.parse("http://$ipAddress/camera_config");
    try {
      final response = await _client.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "quality": quality,
          "brightness": brightness,
          "contrast": contrast,
        }),
      ).timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Consulta el buffer circular de eventos en RAM (/logs)
  Future<List<Map<String, dynamic>>?> fetchFirmwareLogs(
    String ipAddress, {
    int limit = 50,
    String? level,
  }) async {
    var uri = Uri.parse("http://$ipAddress/logs");
    final params = <String, String>{"limit": limit.toString()};
    if (level != null) params["level"] = level;
    uri = uri.replace(queryParameters: params);

    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> clearFirmwareLogs(String ipAddress) async {
    return _simplePostOk(ipAddress, "/logs/clear", seconds: 2);
  }

  /// Consulta la causa y registro del último crash en NVS (/crash_log)
  Future<Map<String, dynamic>?> fetchCrashLog(String ipAddress) async {
    try {
      final response = await _client
          .get(Uri.parse("http://$ipAddress/crash_log"))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> clearCrashLog(String ipAddress) async {
    return _simplePostOk(ipAddress, "/crash_log/clear", seconds: 2);
  }

  Future<Map<String, dynamic>?> fetchNetworkStats(String ipAddress) async {
    try {
      final response = await _client
          .get(Uri.parse("http://$ipAddress/network_stats"))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<GlassesTelemetry?> fetchTelemetry(String ipAddress) async {
    final uri = Uri.parse("http://$ipAddress/status");
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client.get(uri).timeout(const Duration(milliseconds: 1500));
        if (response.statusCode == 200) {
          return GlassesTelemetry.fromJson(jsonDecode(response.body));
        }
        return null;
      } catch (_) {}
      if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  Future<int> checkPingLatency(String ipAddress) async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse("http://$ipAddress/status");
      final response = await _client.get(uri).timeout(const Duration(milliseconds: 1500));
      stopwatch.stop();
      if (response.statusCode == 200) return stopwatch.elapsedMilliseconds;
      return -1;
    } catch (_) {
      return -1;
    }
  }

  Future<bool> _simpleGetOk(String ip, String path, {int seconds = 2}) async {
    try {
      final response = await _client.get(Uri.parse("http://$ip$path")).timeout(Duration(seconds: seconds));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _simplePostOk(String ip, String path, {int seconds = 2}) async {
    try {
      final response = await _client.post(Uri.parse("http://$ip$path")).timeout(Duration(seconds: seconds));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

final wifiSyncServiceProvider = Provider<WifiSyncService>((ref) {
  return WifiSyncService();
});
