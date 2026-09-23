import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses_app/features/connectivity/wifi_sync_service.dart';
import 'package:smart_glasses_app/core/utils/sync_candidates.dart';

void main() {
  group('Telemetría unificada HTTP + BLE notify', () {
    test('acepta alias BLE cam_ok/cam_fail/heap_frag', () {
      final t = GlassesTelemetry.fromJson({
        'status': 'online',
        'ip': '192.168.4.1',
        'fw': '1.4.0',
        'cam_ok': false,
        'cam_fail': 3,
        'heap_frag': 42,
        'rssi': -60,
      });
      expect(t.cameraOk, isFalse);
      expect(t.cameraFailures, 3);
      expect(t.heapFragPct, 42);
    });

    test('acepta notify corto b/c/r', () {
      final t = GlassesTelemetry.fromJson({'fw': '1.4.0', 'ip': '192.168.1.5', 'b': 85, 'c': true, 'r': -55});
      expect(t.batteryPct, 85);
      expect(t.cameraOk, isTrue);
      expect(t.rssi, -55);
    });

    test('defaults seguros si faltan campos', () {
      final t = GlassesTelemetry.fromJson({});
      expect(t.cameraOk, isTrue);
      expect(t.batteryPct, 100);
    });
  });

  group('SyncCandidates SoftAP', () {
    test('192.168.4.x se etiqueta como AP', () {
      expect(SyncCandidates.looksLikeSoftAp('192.168.4.1'), isTrue);
      expect(SyncCandidates.looksLikeSoftAp('192.168.4.2'), isTrue);
      expect(SyncCandidates.looksLikeSoftAp('192.168.1.5'), isFalse);
    });

    test('backoff capita a 2s', () {
      expect(SyncCandidates.backoffForAttempt(0).inMilliseconds, 100);
      expect(SyncCandidates.backoffForAttempt(2).inSeconds, 2);
      expect(SyncCandidates.backoffForAttempt(9).inSeconds, 2);
    });
  });
}
