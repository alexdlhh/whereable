import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../../core/utils/sync_candidates.dart';
import '../../core/services/udp_discovery_service.dart';

enum SyncStatus {
  disconnected,
  probingSavedIp,
  scanningBle,
  connectingBle,
  provisioningWifi,
  connected,
  error
}

enum DeviceMedium {
  ble,
  wifi,
  softAp,
}

class DiscoveredGlassesDevice {
  final String id;
  final String name;
  final int rssi;
  final DeviceMedium medium;
  final String? ip;
  final BluetoothDevice? bluetoothDevice;
  final String? fwVersion;
  final int? batteryPct;
  final DateTime lastSeen;

  DiscoveredGlassesDevice({
    required this.id,
    required this.name,
    this.rssi = -60,
    required this.medium,
    this.ip,
    this.bluetoothDevice,
    this.fwVersion,
    this.batteryPct,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  DiscoveredGlassesDevice copyWith({
    String? id,
    String? name,
    int? rssi,
    DeviceMedium? medium,
    String? ip,
    BluetoothDevice? bluetoothDevice,
    String? fwVersion,
    int? batteryPct,
    DateTime? lastSeen,
  }) {
    return DiscoveredGlassesDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      medium: medium ?? this.medium,
      ip: ip ?? this.ip,
      bluetoothDevice: bluetoothDevice ?? this.bluetoothDevice,
      fwVersion: fwVersion ?? this.fwVersion,
      batteryPct: batteryPct ?? this.batteryPct,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  String get signalLabel {
    if (rssi >= -60) return "Excelente";
    if (rssi >= -75) return "Buena";
    if (rssi >= -85) return "Media";
    return "Débil";
  }
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
  final bool isSearching;
  final List<DiscoveredGlassesDevice> discoveredDevices;
  final String? detectedPhoneWifiSsid;
  final String? detectedPhoneIp;

  // Telemetría en tiempo real accesible directamente por la UI
  final int? batteryPct;
  final double? batteryVoltage;
  final int? heapFragPct;
  final String? fwVersion;
  final bool? cameraOk;
  final int? cameraFailures;
  final int? reconnectCount;

  BleState({
    required this.status,
    this.connectedDevice,
    this.glassesIp,
    this.rssi,
    this.lastMessage,
    required this.savedProfile,
    this.isBleConnected = false,
    this.isWifiConnected = false,
    this.isSearching = false,
    this.discoveredDevices = const [],
    this.detectedPhoneWifiSsid,
    this.detectedPhoneIp,
    this.batteryPct,
    this.batteryVoltage,
    this.heapFragPct,
    this.fwVersion,
    this.cameraOk,
    this.cameraFailures,
    this.reconnectCount,
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
    bool? isSearching,
    List<DiscoveredGlassesDevice>? discoveredDevices,
    String? detectedPhoneWifiSsid,
    String? detectedPhoneIp,
    int? batteryPct,
    double? batteryVoltage,
    int? heapFragPct,
    String? fwVersion,
    bool? cameraOk,
    int? cameraFailures,
    int? reconnectCount,
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
      isSearching: isSearching ?? this.isSearching,
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      detectedPhoneWifiSsid: detectedPhoneWifiSsid ?? this.detectedPhoneWifiSsid,
      detectedPhoneIp: detectedPhoneIp ?? this.detectedPhoneIp,
      batteryPct: batteryPct ?? this.batteryPct,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      heapFragPct: heapFragPct ?? this.heapFragPct,
      fwVersion: fwVersion ?? this.fwVersion,
      cameraOk: cameraOk ?? this.cameraOk,
      cameraFailures: cameraFailures ?? this.cameraFailures,
      reconnectCount: reconnectCount ?? this.reconnectCount,
    );
  }
}

class BleService extends StateNotifier<BleState> {
  BleService({
    bool autoStart = true,
    http.Client? httpClient,
    NetworkInfo? networkInfo,
  })  : _http = httpClient ?? http.Client(),
        _networkInfo = networkInfo ?? NetworkInfo(),
        super(BleState(
          status: SyncStatus.disconnected,
          savedProfile: GlassesDeviceProfile(),
        )) {
    if (autoStart) {
      _initPersistenceAndAutoSync();
    }
  }

  final http.Client _http;
  final NetworkInfo _networkInfo;
  final UdpDiscoveryService _udpDiscovery = UdpDiscoveryService();
  StreamSubscription<UdpGlassesBeacon>? _udpSubscription;
  String? _lastUdpBeaconIp;
  BluetoothCharacteristic? _wifiConfigChar;
  BluetoothCharacteristic? _statusChar;
  StreamSubscription<List<int>>? _statusNotificationSub;
  Timer? _heartbeatTimer;
  StreamSubscription? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  int _missedHeartbeats = 0;
  DateTime _lastReconnectAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _simulatorMode = false;
  // Cola serie de escrituras BLE: evita condiciones de carrera GATT
  // encadenando cada write tras el anterior.
  Future<void> _bleWriteChain = Future.value();

  /// Pausa el heartbeat cuando la app entra en modo simulador (ahorra batería).
  void setSimulatorMode(bool enabled) {
    _simulatorMode = enabled;
    if (enabled) _missedHeartbeats = 0;
  }

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

    await detectPhoneNetworkInfo();
    _startUdpDiscoveryListener();

    if (profile.deviceId != null || profile.lastKnownIp != null) {
      await autoConnectGlasses();
    }

    _startHeartbeatMonitor();
  }

  void _startUdpDiscoveryListener() async {
    final started = await _udpDiscovery.startListening();
    if (!started) return;

    _udpSubscription?.cancel();
    _udpSubscription = _udpDiscovery.onBeacon.listen((beacon) async {
      _lastUdpBeaconIp = beacon.ip;

      // Si aún no estamos sincronizados o la IP cambió, VERIFICAR con
      // GET /status antes de marcar connected (anti-spoof + valida fw).
      if (state.glassesIp != beacon.ip || !state.isWifiConnected) {
        try {
          final resp = await _http
              .get(Uri.parse("http://${beacon.ip}/status"))
              .timeout(const Duration(seconds: 2));
          if (resp.statusCode != 200) return;
          final data = jsonDecode(resp.body);
          if (data["fw"] == null || data["status"] == null) return;
          final actualIp = (data["ip"] ?? beacon.ip).toString();
          state = state.copyWith(
            glassesIp: actualIp,
            isWifiConnected: true,
            status: SyncStatus.connected,
            lastMessage: "Baliza UDP verificada (${actualIp} fw ${data["fw"]})",
          );
          await _saveProfile(state.savedProfile.copyWith(lastKnownIp: actualIp));
          _missedHeartbeats = 0;
          stopDiscovery();
        } catch (_) {
          // Beacon no verificable: no promovemos a connected.
        }
      }
    });
  }

  Future<void> detectPhoneNetworkInfo() async {
    try {
      final rawSsid = await _networkInfo.getWifiName();
      final phoneIp = await _networkInfo.getWifiIP();
      final cleanedSsid = _cleanSsid(rawSsid);
      state = state.copyWith(
        detectedPhoneWifiSsid: cleanedSsid,
        detectedPhoneIp: phoneIp,
      );
    } catch (_) {}
  }

  String? _cleanSsid(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1);
    }
    if (s == '<unknown ssid>' || s.isEmpty) return null;
    return s;
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
      try {
        await state.connectedDevice!.disconnect();
      } catch (_) {}
    }

    state = BleState(
      status: SyncStatus.disconnected,
      savedProfile: GlassesDeviceProfile(),
      lastMessage: "Dispositivo olvidado.",
      discoveredDevices: const [],
      detectedPhoneWifiSsid: state.detectedPhoneWifiSsid,
      detectedPhoneIp: state.detectedPhoneIp,
    );
  }

  Future<void> autoConnectGlasses() async {
    final candidateIps = SyncCandidates.ips(
      lastKnownIp: state.savedProfile.lastKnownIp,
      udpDiscoveredIp: _lastUdpBeaconIp,
    );

    state = state.copyWith(status: SyncStatus.probingSavedIp, lastMessage: "Verificando enlace Wi-Fi...");

    for (int i = 0; i < candidateIps.length; i++) {
      final ip = candidateIps[i];
      // Backoff escalonado: 1200ms, +400ms por intento para no saturar la red.
      final timeoutMs = 900 + i * 400;
      try {
        final response = await _http.get(Uri.parse("http://$ip/status")).timeout(Duration(milliseconds: timeoutMs));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          // Validar que sea realmente la gafa (evita falsos positivos con otro ESP).
          if (data["fw"] == null || data["status"] == null) continue;
          final actualIp = (data["ip"] ?? ip).toString();

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
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
        Permission.microphone,
      ].request();
    } catch (_) {}
  }

  /// Inicia el escaneo y buscador inteligente automatizado (BLE + Red Local).
  Future<void> startAutoDiscovery({bool force = true}) async {
    await requestPermissions();
    await detectPhoneNetworkInfo();

    final initialList = <DiscoveredGlassesDevice>[];

    // Si ya hay un dispositivo BLE conectado, agregarlo inmediatamente a la lista
    if (state.connectedDevice != null) {
      initialList.add(DiscoveredGlassesDevice(
        id: state.connectedDevice!.remoteId.str,
        name: state.connectedDevice!.platformName.isNotEmpty
            ? state.connectedDevice!.platformName
            : (state.savedProfile.deviceName ?? ApiConstants.glassesBleName),
        rssi: state.rssi ?? -50,
        medium: DeviceMedium.ble,
        bluetoothDevice: state.connectedDevice,
        lastSeen: DateTime.now(),
      ));
    }
    if (state.glassesIp != null && state.glassesIp != '0.0.0.0') {
      final isAp = SyncCandidates.looksLikeSoftAp(state.glassesIp!);
      initialList.add(DiscoveredGlassesDevice(
        id: "wifi_${state.glassesIp}",
        name: isAp ? "XIAO-Glasses (Punto de Acceso)" : "XIAO-SmartGlasses (Wi-Fi)",
        rssi: state.rssi ?? -55,
        medium: isAp ? DeviceMedium.softAp : DeviceMedium.wifi,
        ip: state.glassesIp,
        lastSeen: DateTime.now(),
      ));
    }

    state = state.copyWith(
      isSearching: true,
      status: state.isBleConnected || state.isWifiConnected ? SyncStatus.connected : SyncStatus.scanningBle,
      lastMessage: "Buscando gafas por Bluetooth y Red Local...",
      discoveredDevices: force ? initialList : state.discoveredDevices,
    );

    // 1. Escaneo de Red Local / Wi-Fi en paralelo
    _probeLocalNetworkForGlasses();

    // 2. Escaneo BLE en paralelo
    try {
      await _scanSubscription?.cancel();
      try {
        if (await FlutterBluePlus.isScanning.first.timeout(const Duration(milliseconds: 300), onTimeout: () => false)) {
          await FlutterBluePlus.stopScan();
        }
      } catch (_) {}

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        final currentList = List<DiscoveredGlassesDevice>.from(state.discoveredDevices);
        var changed = false;

        for (final r in results) {
          final name = r.device.platformName;
          final advName = r.advertisementData.advName;
          final displayName = name.isNotEmpty ? name : (advName.isNotEmpty ? advName : "Dispositivo BLE");
          final isGlasses = displayName.contains(ApiConstants.glassesBleName) ||
              displayName.toLowerCase().contains("glasses") ||
              displayName.toLowerCase().contains("xiao") ||
              r.advertisementData.serviceUuids.any((u) => u.toString().toLowerCase() == ApiConstants.bleServiceUuid.toLowerCase());

          // Si es unas gafas o coincide con dispositivo guardado
          if (isGlasses || (state.savedProfile.deviceId != null && r.device.remoteId.str == state.savedProfile.deviceId)) {
            final devId = r.device.remoteId.str;
            final existingIdx = currentList.indexWhere((d) => d.id == devId);

            final discovered = DiscoveredGlassesDevice(
              id: devId,
              name: displayName.isNotEmpty ? displayName : ApiConstants.glassesBleName,
              rssi: r.rssi,
              medium: DeviceMedium.ble,
              bluetoothDevice: r.device,
              lastSeen: DateTime.now(),
            );

            if (existingIdx >= 0) {
              currentList[existingIdx] = discovered;
            } else {
              currentList.add(discovered);
            }
            changed = true;
          }
        }

        if (changed) {
          state = state.copyWith(discoveredDevices: currentList);
        }
      });
    } catch (e) {
      debugPrint("Error escaneo BLE: $e");
    }
  }

  Future<void> stopDiscovery() async {
    try {
      await _scanSubscription?.cancel();
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    state = state.copyWith(isSearching: false);
  }

  void _probeLocalNetworkForGlasses() async {
    final candidateIps = SyncCandidates.ips(lastKnownIp: state.savedProfile.lastKnownIp);

    // Si tenemos IP del móvil en Wi-Fi (ej: 192.168.1.45), agregar candidatos de subred comunes
    final phoneIp = state.detectedPhoneIp;
    if (phoneIp != null && phoneIp.contains('.')) {
      final prefix = phoneIp.substring(0, phoneIp.lastIndexOf('.') + 1);
      final subnetProbes = [
        '${prefix}1',
        '${prefix}2',
        '${prefix}3',
        '${prefix}10',
        '${prefix}20',
        '${prefix}50',
        '${prefix}100',
        '${prefix}150',
        '${prefix}200',
      ];
      for (final p in subnetProbes) {
        if (!candidateIps.contains(p)) candidateIps.add(p);
      }
    }

    for (final ip in candidateIps) {
      if (!state.isSearching && state.status == SyncStatus.connected) break;
      _probeSingleIp(ip);
    }
  }

  Future<void> _probeSingleIp(String ip) async {
    try {
      final response = await _http.get(Uri.parse("http://$ip/status")).timeout(const Duration(milliseconds: 1400));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["fw"] == null || data["status"] == null) return;
        final actualIp = (data["ip"] ?? ip).toString();
        final isSoftAp = SyncCandidates.looksLikeSoftAp(actualIp);
        final devId = "wifi_$actualIp";
        final name = isSoftAp ? "XIAO-Glasses (Punto de Acceso)" : "XIAO-SmartGlasses (Wi-Fi)";

        final discovered = DiscoveredGlassesDevice(
          id: devId,
          name: name,
          rssi: data["rssi"] ?? -55,
          medium: isSoftAp ? DeviceMedium.softAp : DeviceMedium.wifi,
          ip: actualIp,
          fwVersion: data["fw"]?.toString(),
          batteryPct: data["battery_pct"] is num ? (data["battery_pct"] as num).toInt() : null,
          lastSeen: DateTime.now(),
        );

        final currentList = List<DiscoveredGlassesDevice>.from(state.discoveredDevices);
        final existingIdx = currentList.indexWhere((d) => d.id == devId || d.ip == actualIp);
        if (existingIdx >= 0) {
          currentList[existingIdx] = discovered;
        } else {
          currentList.insert(0, discovered);
        }

        state = state.copyWith(
          discoveredDevices: currentList,
          glassesIp: actualIp,
          isWifiConnected: true,
          status: state.status == SyncStatus.scanningBle || state.status == SyncStatus.probingSavedIp
              ? SyncStatus.connected
              : state.status,
          lastMessage: "Gafas encontradas y sincronizadas en red local ($actualIp)",
        );

        // Si era el IP guardado o SoftAP activo, detenemos búsqueda activa para no agotar batería/recursos
        if (actualIp == state.savedProfile.lastKnownIp || isSoftAp) {
          stopDiscovery();
        }
      }
    } catch (_) {}
  }

  /// Conecta a un dispositivo encontrado en 1 toque.
  Future<bool> connectToDiscoveredDevice(DiscoveredGlassesDevice device) async {
    state = state.copyWith(status: SyncStatus.connectingBle, lastMessage: "Conectando con ${device.name}...");

    if (device.medium == DeviceMedium.ble && device.bluetoothDevice != null) {
      await stopDiscovery();
      await _connectToDevice(device.bluetoothDevice!);
      return state.isBleConnected;
    } else if (device.ip != null) {
      await stopDiscovery();
      state = state.copyWith(
        status: SyncStatus.connected,
        glassesIp: device.ip,
        isWifiConnected: true,
        lastMessage: "Enlazado por Wi-Fi (${device.ip})",
      );
      await _saveProfile(state.savedProfile.copyWith(lastKnownIp: device.ip));
      return true;
    }
    return false;
  }

  /// Conecta directamente por IP manual.
  Future<bool> connectDirectIp(String ip) async {
    state = state.copyWith(status: SyncStatus.probingSavedIp, lastMessage: "Probando enlace en $ip...");
    try {
      final response = await _http.get(Uri.parse("http://$ip/status")).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        state = state.copyWith(
          status: SyncStatus.connected,
          glassesIp: ip,
          isWifiConnected: true,
          lastMessage: "Conectado exitosamente a $ip",
        );
        await _saveProfile(state.savedProfile.copyWith(lastKnownIp: ip));
        return true;
      }
    } catch (e) {
      state = state.copyWith(lastMessage: "Fallo al conectar con $ip");
    }
    return false;
  }

  /// Conecta por BLE y aprovisiona Wi-Fi en un solo flujo automático.
  Future<bool> pairAndProvisionWifi({
    required DiscoveredGlassesDevice device,
    required String ssid,
    required String password,
  }) async {
    if (device.bluetoothDevice != null) {
      await stopDiscovery();
      await _connectToDevice(device.bluetoothDevice!);
      if (!state.isBleConnected) {
        return false;
      }
    }
    return await sendWifiCredentials(ssid, password);
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
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 8));

      // Negociar MTU a 512 bytes para máxima velocidad de telemetría y aprovisionamiento
      try {
        await device.requestMtu(512);
      } catch (_) {}

      _connectionStateSub?.cancel();
      _connectionStateSub = device.connectionState.listen((connState) {
        if (connState == BluetoothConnectionState.disconnected) {
          state = state.copyWith(
            isBleConnected: false,
            status: state.isWifiConnected ? SyncStatus.connected : SyncStatus.disconnected,
            lastMessage: "Bluetooth desconectado.",
          );
        } else if (connState == BluetoothConnectionState.connected) {
          state = state.copyWith(isBleConnected: true);
        }
      });

      final services = await device.discoverServices();

      for (final s in services) {
        if (s.uuid.toString().toLowerCase() == ApiConstants.bleServiceUuid.toLowerCase()) {
          for (final c in s.characteristics) {
            if (c.uuid.toString().toLowerCase() == ApiConstants.bleWifiConfigCharUuid.toLowerCase()) {
              _wifiConfigChar = c;
            } else if (c.uuid.toString().toLowerCase() == ApiConstants.bleStatusCharUuid.toLowerCase()) {
              _statusChar = c;
              await _statusChar!.setNotifyValue(true);
              _statusNotificationSub?.cancel();
              _statusNotificationSub = _statusChar!.onValueReceived.listen(_handleStatusNotification);
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
        final vBat = data["battery_voltage"] is num ? (data["battery_voltage"] as num).toDouble() : state.batteryVoltage;
        final bPct = data["battery_pct"] is num ? (data["battery_pct"] as num).toInt() : state.batteryPct;
        final hFrag = data["heap_frag"] is num ? (data["heap_frag"] as num).toInt() : state.heapFragPct;
        final fw = data["fw"]?.toString() ?? state.fwVersion;
        final cOk = data["cam_ok"] is bool ? data["cam_ok"] as bool : state.cameraOk;
        final cFail = data["cam_fail"] is num ? (data["cam_fail"] as num).toInt() : state.cameraFailures;
        final reconn = data["wifi_reconnects"] is num ? (data["wifi_reconnects"] as num).toInt() : state.reconnectCount;

        state = state.copyWith(
          glassesIp: ip,
          rssi: data["rssi"] is num ? (data["rssi"] as num).toInt() : state.rssi,
          isWifiConnected: data["wifi"] == true || ip != "0.0.0.0",
          batteryPct: bPct,
          batteryVoltage: vBat,
          heapFragPct: hFrag,
          fwVersion: fw,
          cameraOk: cOk,
          cameraFailures: cFail,
          reconnectCount: reconn,
          lastMessage: "Telemetría recibida (IP: $ip · Bat: ${bPct ?? '?'}%)",
        );
        _saveProfile(state.savedProfile.copyWith(lastKnownIp: ip));
      }
    } catch (_) {}
  }

  Future<bool> _safeBleWrite(BluetoothCharacteristic char, List<int> bytes, {int maxRetries = 2}) async {
    // Serializar escrituras: cada llamada espera a la anterior.
    final completer = Completer<bool>();
    _bleWriteChain = _bleWriteChain.then((_) async {
      for (int attempt = 0; attempt <= maxRetries; attempt++) {
        try {
          await char.write(bytes, withoutResponse: false);
          if (!completer.isCompleted) completer.complete(true);
          return;
        } catch (e) {
          if (attempt == maxRetries) {
            if (!completer.isCompleted) completer.completeError(e);
            return;
          }
          // Backoff exponencial 150ms -> 300ms -> 600ms
          await Future.delayed(Duration(milliseconds: 150 * (1 << attempt)));
        }
      }
    });
    return completer.future;
  }

  Future<bool> sendWifiCredentials(String ssid, String password) async {
    if (ssid.trim().isEmpty) {
      state = state.copyWith(lastMessage: "SSID vacío: no se envía nada por BLE.");
      return false;
    }
    if (_wifiConfigChar == null) {
      state = state.copyWith(lastMessage: "Gafas no conectadas por BLE para enviar Wi-Fi.");
      return false;
    }
    try {
      state = state.copyWith(status: SyncStatus.provisioningWifi, lastMessage: "Enviando credenciales Wi-Fi...");
      final payload = jsonEncode({"ssid": ssid.trim(), "password": password});
      await _safeBleWrite(_wifiConfigChar!, utf8.encode(payload));

      await _saveProfile(state.savedProfile.copyWith(savedSsid: ssid.trim()));
      // ACK real llega vía UDP beacon + GET /status (verificado) o heartbeat.
      // Espera de gracia 4s para que la gafa asocie STA antes de dar feedback.
      state = state.copyWith(status: SyncStatus.provisioningWifi, lastMessage: "Wi-Fi '$ssid' enviado. Esperando asociación STA (4s)...");
      await Future<void>.delayed(const Duration(seconds: 4));
      if (state.isWifiConnected) {
        state = state.copyWith(status: SyncStatus.connected, lastMessage: "Gafas sincronizadas en Wi-Fi.");
      } else {
        state = state.copyWith(lastMessage: "Credenciales enviadas. La gafa está asociando STA (verifica banner)...");
      }
      return true;
    } catch (e) {
      state = state.copyWith(lastMessage: "Error enviando Wi-Fi: $e");
      return false;
    }
  }

  void _startHeartbeatMonitor() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_simulatorMode) return; // En simulador no polear hardware real.
      if (state.isSearching) return; // No competir con escaneo BLE activo.
      final ip = state.glassesIp ?? state.savedProfile.lastKnownIp;
      if (ip == null || ip == "0.0.0.0") return;
      try {
        final res = await _http.get(Uri.parse("http://$ip/status")).timeout(const Duration(milliseconds: 2500));
        if (res.statusCode == 200) {
          _missedHeartbeats = 0;
          final data = jsonDecode(res.body);
          final bPct = data["battery_pct"] is num ? (data["battery_pct"] as num).toInt() : state.batteryPct;
          final vBat = data["battery_voltage"] is num ? (data["battery_voltage"] as num).toDouble() : state.batteryVoltage;
          final hFrag = (data["heap_frag_pct"] ?? data["heap_frag"]) is num
              ? ((data["heap_frag_pct"] ?? data["heap_frag"]) as num).toInt()
              : state.heapFragPct;
          final fw = (data["fw"] ?? data["fw_version"])?.toString() ?? state.fwVersion;
          final cOkRaw = data["camera_ok"] ?? data["cam_ok"];
          final cOk = cOkRaw is bool ? cOkRaw : state.cameraOk;
          final cFailRaw = data["camera_failures"] ?? data["cam_fail"];
          final cFail = cFailRaw is num ? (cFailRaw as num).toInt() : state.cameraFailures;
          final reconn = data["wifi_reconnects"] is num ? (data["wifi_reconnects"] as num).toInt() : state.reconnectCount;

          state = state.copyWith(
            isWifiConnected: true,
            status: SyncStatus.connected,
            batteryPct: bPct,
            batteryVoltage: vBat,
            heapFragPct: hFrag,
            fwVersion: fw,
            cameraOk: cOk,
            cameraFailures: cFail,
            reconnectCount: reconn,
          );
          return;
        }
      } catch (_) {}

      _missedHeartbeats++;
      if (_missedHeartbeats >= 3 && state.isWifiConnected) {
        state = state.copyWith(isWifiConnected: false, lastMessage: "Wi-Fi no responde en $ip");
      }
      
      // No reescanear si ya estamos conectados por BLE
      if (_missedHeartbeats >= 5 &&
          !state.isBleConnected &&
          DateTime.now().difference(_lastReconnectAttempt) > const Duration(seconds: 25) &&
          state.savedProfile.autoReconnect) {
        _lastReconnectAttempt = DateTime.now();
        _missedHeartbeats = 0;
        await autoConnectGlasses();
      }
    });
  }

  @override
  void dispose() {
    _udpSubscription?.cancel();
    _udpDiscovery.dispose();
    _heartbeatTimer?.cancel();
    _scanSubscription?.cancel();
    _connectionStateSub?.cancel();
    _statusNotificationSub?.cancel();
    super.dispose();
  }
}

final bleServiceProvider = StateNotifierProvider<BleService, BleState>((ref) {
  return BleService();
});
