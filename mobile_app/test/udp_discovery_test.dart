import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses_app/core/services/udp_discovery_service.dart';

void main() {
  group('UdpGlassesBeacon', () {
    test('deserializa correctamente JSON de baliza', () {
      final json = {
        'device': 'XIAO-SmartGlasses',
        'ip': '192.168.43.125',
        'port': 80,
        'fw': '1.3.2-CAM-HOTSPOT-FIX',
        'rssi': -52,
        'mode': 'STA',
      };

      final beacon = UdpGlassesBeacon.fromJson(json);

      expect(beacon.device, 'XIAO-SmartGlasses');
      expect(beacon.ip, '192.168.43.125');
      expect(beacon.port, 80);
      expect(beacon.fw, '1.3.2-CAM-HOTSPOT-FIX');
      expect(beacon.rssi, -52);
      expect(beacon.mode, 'STA');
      expect(beacon.timestamp, isNotNull);
    });

    test('aplica valores por defecto seguros', () {
      final json = {
        'ip': '192.168.1.50',
      };

      final beacon = UdpGlassesBeacon.fromJson(json);

      expect(beacon.device, 'XIAO-SmartGlasses');
      expect(beacon.ip, '192.168.1.50');
      expect(beacon.port, 80);
      expect(beacon.fw, isNull);
      expect(beacon.rssi, isNull);
    });
  });
}
