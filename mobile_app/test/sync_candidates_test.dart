import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses_app/core/utils/sync_candidates.dart';

void main() {
  group('SyncCandidates', () {
    test('siempre incluye mDNS y SoftAP', () {
      final ips = SyncCandidates.ips();
      expect(ips, containsAll(['glasses.local', '192.168.4.1']));
      expect(ips.first, 'glasses.local');
    });

    test('prioriza última IP conocida válida', () {
      final ips = SyncCandidates.ips(lastKnownIp: '10.0.0.42');
      expect(ips.first, '10.0.0.42');
      expect(ips, contains('glasses.local'));
      expect(ips, contains('192.168.4.1'));
    });

    test('prioriza IP descubierta por UDP por encima de la última conocida', () {
      final ips = SyncCandidates.ips(
        lastKnownIp: '10.0.0.42',
        udpDiscoveredIp: '192.168.43.125',
      );
      expect(ips.first, '192.168.43.125');
      expect(ips[1], '10.0.0.42');
      expect(ips, contains('glasses.local'));
      expect(ips, contains('192.168.4.1'));
    });

    test('ignora IP vacía o 0.0.0.0', () {
      expect(SyncCandidates.ips(lastKnownIp: '  '), isNot(contains('  ')));
      expect(SyncCandidates.ips(lastKnownIp: '0.0.0.0').first, 'glasses.local');
    });

    test('detecta SoftAP', () {
      expect(SyncCandidates.looksLikeSoftAp('192.168.4.1'), isTrue);
      expect(SyncCandidates.looksLikeSoftAp('10.0.0.5'), isFalse);
    });
  });
}
