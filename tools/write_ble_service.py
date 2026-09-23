# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(__file__).resolve().parents[1] / "mobile_app" / "lib" / "features" / "connectivity" / "ble_service.dart"
p.write_text(r'''import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../../core/utils/sync_candidates.dart';

enum SyncStatus {
  disconnected,
  probingSavedIp,
  scanningBle,
  connectingBle,
  provisioningWifi,
  connected,
  error
}

class GlassesDeviceProfile {
  final String? deviceId;
  final String? deviceName;
  final String? lastKnownIp;
  final String? savedSsid;
  final bool autoReconnect;

  GlassesDeviceProfile({
    this.deviceId,
    this.deviceName,
    this.lastKnownIp,
    this.savedSsid,
    this.autoReconnect = true,
  });

  GlassesDeviceProfile copyWith({
    String? deviceId,
    String? deviceName,
    String? lastKnownIp,
    String? savedSsid,
    bool? autoReconnect,
  }) {
    return GlassesDeviceProfile(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      lastKnownIp: lastKnownIp ?? this.lastKnownIp,
      savedSsid: savedSsid ?? this.savedSsid,
      autoReconnect: autoReconnect ?? this.autoReconnect,
    );
  }
}

class BleState {
  final SyncStatus status;
  final BluetoothDevice? connectedDevice;
  final String? glassesIp;
  final int? rssi;
  final String? lastMessage;
  final GlassesDeviceProfile savedProfile;
  final bool isBleConnected;
  final bool isWifiConnected;

  BleState({
    required this.status,
    this.connectedDevice,
    this.glassesIp,
    this.rssi,
    this.lastMessage,
    required this.savedProfile,
    this.isBleConnected = false,
    this.isWifiConnected = false,
  });

  BleState copyWith({
    SyncStatus? status,
    BluetoothDevice? connectedDevice,
    String? glassesIp,
    int? rssi,
    String? lastMessage,
    GlassesDeviceProfile? savedProfile,
    bool? isBleConnected,
    bool? isWifiConnected,
  }) {
    return BleState(
      status: status ?? this.status,
      connectedDevice: connectedDevice ?? this.connectedDevice,
      glassesIp: glassesIp ?? this.glassesIp,
      rssi: rssi ?? this.rssi,
      lastMessage: lastMessage ?? this.lastMessage,
      savedProfile: savedProfile ?? this.savedProfile,
      isBleConnected: isBleConnected ?? this.isBleConnected,
      isWifiConnected: isWifiConnected ?? this.isWifiConnected,
    );
  }
}

class BleService extends StateNotifier<BleState> {
  BleService({bool autoStart = true, http.Client? httpClient})
      : _http = httpClient ?? http.Client(),
        super(BleState(
          status: SyncStatus.disconnected,
          savedProfile: GlassesDeviceProfile(),
        )) {
    if (autoStart) {
      _initPersistenceAndAutoSync();
    }
  }

  final http.Client _http;
  BluetoothCharacteristic? _wifiConfigChar;
  BluetoothCharacteristic? _statusChar;
  Timer? _heartbeatTimer;
  StreamSubscription? _scanSubscription;
  int _missedHeartbeats = 0;
  DateTime _lastReconnectAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  static const _keyDeviceId = "glasses_ble_device_id";
  static const _keyDeviceName = "glasses_ble_device_name";
  static const _keyLastIp = "glasses_last_ip";
  static const _keySavedSsid = "glasses_saved_ssid";

  Future<void> _initPersistenceAndAutoSync() async {
    final prefs = await SharedPreferences.getInstance();
    final profile = GlassesDeviceProfile(
      deviceId: prefs.getString(_keyDeviceId),
      deviceName: prefs.getString(_keyDeviceName),
      lastKnownIp: prefs.getString(_keyLastIp),
      savedSsid: prefs.getString(_keySavedSsid),
    );

    state = state.copyWith(savedProfile: profile);

    if (profile.deviceId != null || profile.lastKnownIp != null) {
      await autoConnectGlasses();
    }

    _startHeartbeatMonitor();
  }

  Future<void> _saveProfile(GlassesDeviceProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    if (profile.deviceId != null) await prefs.setString(_keyDeviceId, profile.deviceId!);
    if (profile.deviceName != null) await prefs.setString(_keyDeviceName, profile.deviceName!);
    if (profile.lastKnownIp != null) await prefs.setString(_keyLastIp, profile.lastKnownIp!);
    if (profile.savedSsid != null) await prefs.setString(_keySavedSsid, profile.savedSsid!);
    state = state.copyWith(savedProfile: profile);
  }

  Future<void> forgetDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDeviceId);
    await prefs.remove(_keyDeviceName);
    await prefs.remove(_keyLastIp);
    await prefs.remove(_keySavedSsid);

    if (state.connectedDevice != null) {
      await state.connectedDevice!.disconnect();
    }

    state = BleState(
      status: SyncStatus.disconnected,
      savedProfile: GlassesDeviceProfile(),
      lastMessage: "Dispositivo olvidado.",
    );
  }

  Future<void> autoConnectGlasses() async {
    final candidateIps = SyncCandidates.ips(lastKnownIp: state.savedProfile.lastKnownIp);

    state = state.copyWith(status: SyncStatus.probingSavedIp, lastMessage: "Verificando enlace Wi-Fi...");

    for (final ip in candidateIps) {
      try {
        final response = await _http.get(Uri.parse("http://$ip/status")).timeout(const Duration(milliseconds: 1200));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final actualIp = data["ip"] ?? ip;

          state = state.copyWith(
            status: SyncStatus.connected,
            glassesIp: actualIp,
            isWifiConnected: true,
            lastMessage: "Sincronizado vía Wi-Fi ($actualIp)",
          );
          await _saveProfile(state.savedProfile.copyWith(lastKnownIp: actualIp));
          _missedHeartbeats = 0;
          return;
        }
      } catch (_) {}
    }

    await startScanAndConnect();
  }

  Future<void> requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.microphone,
    ].request();
  }

  Future<void> startScanAndConnect() async {
    await requestPermissions();
    state = state.copyWith(status: SyncStatus.scanningBle, lastMessage: "Buscando gafas por Bluetooth...");

    try {
      await _scanSubscription?.cancel();
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          final isTargetName = r.device.platformName == ApiConstants.glassesBleName;
          final isSavedId = state.savedProfile.deviceId != null && r.device.remoteId.str == state.savedProfile.deviceId;

          if (isTargetName || isSavedId) {
            await FlutterBluePlus.stopScan();
            await _connectToDevice(r.device);
            break;
          }
        }
      });
    } catch (e) {
      state = state.copyWith(
        status: SyncStatus.error,
        lastMessage: "Error en escaneo Bluetooth: $e",
      );
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    state = state.copyWith(status: SyncStatus.connectingBle, lastMessage: "Conectando con ${device.platformName}...");
    try {
      await device.connect(autoConnect: false);
      final services = await device.discoverServices();

      for (final s in services) {
        if (s.uuid.toString().toLowerCase() == ApiConstants.bleServiceUuid.toLowerCase()) {
          for (final c in s.characteristics) {
            if (c.uuid.toString().toLowerCase() == ApiConstants.bleWifiConfigCharUuid.toLowerCase()) {
              _wifiConfigChar = c;
            } else if (c.uuid.toString().toLowerCase() == ApiConstants.bleStatusCharUuid.toLowerCase()) {
              _statusChar = c;
              await _statusChar!.setNotifyValue(true);
              _statusChar!.onValueReceived.listen(_handleStatusNotification);
            }
          }
        }
      }

      final newProfile = state.savedProfile.copyWith(
        deviceId: device.remoteId.str,
        deviceName: device.platformName,
      );
      await _saveProfile(newProfile);

      state = state.copyWith(
        status: SyncStatus.connected,
        connectedDevice: device,
        isBleConnected: true,
        lastMessage: "Enlazado por Bluetooth y guardado",
      );
    } catch (e) {
      state = state.copyWith(
        status: SyncStatus.error,
        lastMessage: "Fallo al conectar BLE: $e",
      );
    }
  }

  void _handleStatusNotification(List<int> value) {
    try {
      final jsonString = utf8.decode(value);
      final data = jsonDecode(jsonString);
      if (data.containsKey("ip")) {
        final ip = data["ip"];
        state = state.copyWith(
          glassesIp: ip,
          rssi: data["rssi"],
          isWifiConnected: data["wifi"] == true || ip != "0.0.0.0",
          lastMessage: "Telemetría recibida (IP: $ip)",
        );
        _saveProfile(state.savedProfile.copyWith(lastKnownIp: ip));
      }
    } catch (_) {}
  }

  Future<bool> sendWifiCredentials(String ssid, String password) async {
    if (_wifiConfigChar == null) {
      state = state.copyWith(lastMessage: "Gafas no conectadas por BLE para enviar Wi-Fi.");
      return false;
    }
    try {
      state = state.copyWith(status: SyncStatus.provisioningWifi, lastMessage: "Enviando credenciales Wi-Fi...");
      final payload = jsonEncode({"ssid": ssid, "password": password});
      await _wifiConfigChar!.write(utf8.encode(payload));

      await _saveProfile(state.savedProfile.copyWith(savedSsid: ssid));
      state = state.copyWith(status: SyncStatus.connected, lastMessage: "Wi-Fi '$ssid' enviado. Gafas sincronizando...");
      return true;
    } catch (e) {
      state = state.copyWith(lastMessage: "Error enviando Wi-Fi: $e");
      return false;
    }
  }

  void _startHeartbeatMonitor() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final ip = state.glassesIp ?? state.savedProfile.lastKnownIp;
      if (ip == null || ip == "0.0.0.0") return;
      try {
        final res = await _http.get(Uri.parse("http://$ip/status")).timeout(const Duration(milliseconds: 1500));
        if (res.statusCode == 200) {
          _missedHeartbeats = 0;
          if (!state.isWifiConnected) {
            state = state.copyWith(isWifiConnected: true, status: SyncStatus.connected);
          }
          return;
        }
      } catch (_) {}

      _missedHeartbeats++;
      if (state.isWifiConnected) {
        state = state.copyWith(isWifiConnected: false, lastMessage: "Heartbeat perdido ($ip)");
      }
      if (_missedHeartbeats >= 3 &&
          DateTime.now().difference(_lastReconnectAttempt) > const Duration(seconds: 15) &&
          state.savedProfile.autoReconnect) {
        _lastReconnectAttempt = DateTime.now();
        _missedHeartbeats = 0;
        await autoConnectGlasses();
      }
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _scanSubscription?.cancel();
    super.dispose();
  }
}

final bleServiceProvider = StateNotifierProvider<BleService, BleState>((ref) {
  return BleService();
});
'''.replace('\r\n', '\n'), encoding='utf-8')
print('wrote ble_service.dart')
