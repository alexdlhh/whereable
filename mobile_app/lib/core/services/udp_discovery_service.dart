import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Información de baliza emitida por las gafas inteligentes sobre UDP.
class UdpGlassesBeacon {
  final String device;
  final String ip;
  final int port;
  final String? fw;
  final int? rssi;
  final String? mode;
  final DateTime timestamp;

  UdpGlassesBeacon({
    required this.device,
    required this.ip,
    this.port = 80,
    this.fw,
    this.rssi,
    this.mode,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory UdpGlassesBeacon.fromJson(Map<String, dynamic> json) {
    return UdpGlassesBeacon(
      device: json['device']?.toString() ?? 'XIAO-SmartGlasses',
      ip: json['ip']?.toString() ?? '',
      port: (json['port'] is num) ? (json['port'] as num).toInt() : 80,
      fw: json['fw']?.toString(),
      rssi: (json['rssi'] is num) ? (json['rssi'] as num).toInt() : null,
      mode: json['mode']?.toString(),
    );
  }
}

/// Servicio que escucha balizas UDP en el puerto 4210 para descubrimiento instantáneo
/// cuando las gafas se conectan al Hotspot/Zona Wi-Fi del teléfono móvil.
class UdpDiscoveryService {
  static const int beaconPort = 4210;

  RawDatagramSocket? _socket;
  final _beaconController = StreamController<UdpGlassesBeacon>.broadcast();
  bool _isListening = false;

  String? _lastEmittedIp;
  int? _lastEmittedRssi;
  DateTime _lastEmittedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<UdpGlassesBeacon> get onBeacon => _beaconController.stream;
  bool get isListening => _isListening;

  Future<bool> startListening() async {
    if (_isListening) return true;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        beaconPort,
        reuseAddress: true,
        reusePort: false,
      );
      _socket!.broadcastEnabled = true;
      _isListening = true;

      _socket!.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket?.receive();
            if (datagram != null) {
              _processDatagram(datagram);
            }
          }
        },
        onError: (e) {
          stopListening();
        },
      );
      return true;
    } catch (_) {
      _isListening = false;
      return false;
    }
  }

  void _processDatagram(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data).trim();
      final json = jsonDecode(text);
      if (json is Map<String, dynamic> && json.containsKey('device') && json.containsKey('ip')) {
        final beacon = UdpGlassesBeacon.fromJson(json);
        if (beacon.ip.isNotEmpty && beacon.ip != '0.0.0.0') {
          final now = DateTime.now();
          final sameIp = _lastEmittedIp == beacon.ip;
          final msSinceLast = now.difference(_lastEmittedAt).inMilliseconds;
          final rssiDelta = (_lastEmittedRssi != null && beacon.rssi != null)
              ? (beacon.rssi! - _lastEmittedRssi!).abs()
              : 999;

          // Deduplicar ráfagas idénticas dentro de 2.5s a menos que haya un cambio apreciable de señal
          if (sameIp && msSinceLast < 2500 && rssiDelta < 12) {
            return;
          }

          _lastEmittedIp = beacon.ip;
          _lastEmittedRssi = beacon.rssi;
          _lastEmittedAt = now;

          _beaconController.add(beacon);
        }
      }
    } catch (_) {}
  }

  void stopListening() {
    _isListening = false;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  void dispose() {
    stopListening();
    _beaconController.close();
  }
}
