# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(__file__).resolve().parents[1] / "mobile_app" / "lib" / "features" / "connectivity" / "wifi_sync_service.dart"
p.write_text(r'''import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GlassesTelemetry {
  final String status;
  final String ip;
  final String mode;
  final int rssi;
  final int freeHeap;
  final int freePsram;
  final int uptimeSec;
  final double batteryVoltage;
  final int batteryPct;
  final bool cameraOk;
  final String fwVersion;

  GlassesTelemetry({
    required this.status,
    required this.ip,
    required this.mode,
    required this.rssi,
    required this.freeHeap,
    required this.freePsram,
    required this.uptimeSec,
    required this.batteryVoltage,
    required this.batteryPct,
    this.cameraOk = true,
    this.fwVersion = 'unknown',
  });

  factory GlassesTelemetry.fromJson(Map<String, dynamic> json) {
    return GlassesTelemetry(
      status: json['status'] ?? 'unknown',
      ip: json['ip'] ?? '0.0.0.0',
      mode: json['mode'] ?? 'STA',
      rssi: json['rssi'] ?? 0,
      freeHeap: json['free_heap'] ?? 0,
      freePsram: json['free_psram'] ?? 0,
      uptimeSec: json['uptime_sec'] ?? 0,
      batteryVoltage: (json['battery_voltage'] as num?)?.toDouble() ?? 3.7,
      batteryPct: json['battery_pct'] ?? 100,
      cameraOk: json['camera_ok'] ?? true,
      fwVersion: (json['fw'] ?? json['fw_version'] ?? 'unknown').toString(),
    );
  }
}

class WifiSyncService {
  WifiSyncService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Uint8List?> fetchSnapshot(String ipAddress) async {
    final uri = Uri.parse("http://$ipAddress/capture");
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> sendAudioToGlasses(String ipAddress, Uint8List audioBytes) async {
    final uri = Uri.parse("http://$ipAddress/play_audio");
    try {
      final response = await _client.post(
        uri,
        headers: {"Content-Type": "application/octet-stream"},
        body: audioBytes,
      ).timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
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

  Future<GlassesTelemetry?> fetchTelemetry(String ipAddress) async {
    final uri = Uri.parse("http://$ipAddress/status");
    try {
      final response = await _client.get(uri).timeout(const Duration(milliseconds: 1500));
      if (response.statusCode == 200) {
        return GlassesTelemetry.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (_) {
      return null;
    }
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
'''.replace('\r\n', '\n'), encoding='utf-8')
print('wrote wifi_sync_service.dart')
