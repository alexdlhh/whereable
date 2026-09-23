import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses_app/features/connectivity/wifi_sync_service.dart';

void main() {
  group('GlassesTelemetry.fromJson', () {
    test('parsea telemetría completa de firmware 1.2', () {
      final tele = GlassesTelemetry.fromJson({
        'status': 'online',
        'ip': '192.168.1.50',
        'sta_ip': '192.168.1.50',
        'ap_ip': '192.168.4.1',
        'mode': 'STA',
        'rssi': -62,
        'free_heap': 120000,
        'free_psram': 4000000,
        'uptime_sec': 3665,
        'battery_voltage': 3.91,
        'battery_pct': 68,
        'camera_ok': true,
        'camera_failures': 0,
        'wdt_sec': 10,
        'fw': '1.2.0',
      });
      expect(tele.status, 'online');
      expect(tele.ip, '192.168.1.50');
      expect(tele.staIp, '192.168.1.50');
      expect(tele.apIp, '192.168.4.1');
      expect(tele.rssi, -62);
      expect(tele.batteryPct, 68);
      expect(tele.batteryVoltage, closeTo(3.91, 0.001));
      expect(tele.cameraOk, isTrue);
      expect(tele.cameraFailures, 0);
      expect(tele.wdtSec, 10);
      expect(tele.fwVersion, '1.2.0');
      expect(tele.formattedUptime, '1h 1m 5s');
      expect(tele.freeHeapKb, '117.2 KB');
      expect(tele.freePsramKb, '3906.3 KB');
    });

    test('defaults seguros si faltan campos', () {
      final tele = GlassesTelemetry.fromJson({});
      expect(tele.status, 'unknown');
      expect(tele.ip, '0.0.0.0');
      expect(tele.batteryPct, 100);
      expect(tele.cameraOk, isTrue);
    });
  });
}
