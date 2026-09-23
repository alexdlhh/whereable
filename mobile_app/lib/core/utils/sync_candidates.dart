/// Lista determinista de IPs/hostnames a probar en el Fast-Path de sincronización.
class SyncCandidates {
  static const String mdnsHost = 'glasses.local';
  static const String softApIp = '192.168.4.1';

  static List<String> ips({String? lastKnownIp, String? udpDiscoveredIp}) {
    final result = <String>[];

    // La IP descubierta por baliza UDP tiene prioridad absoluta
    final udp = udpDiscoveredIp?.trim();
    if (udp != null && udp.isNotEmpty && udp != '0.0.0.0') {
      result.add(udp);
    }

    final last = lastKnownIp?.trim();
    if (last != null && last.isNotEmpty && last != '0.0.0.0' && !result.contains(last)) {
      result.add(last);
    }
    if (!result.contains(mdnsHost)) result.add(mdnsHost);
    if (!result.contains(softApIp)) result.add(softApIp);
    return result;
  }

  static bool looksLikeSoftAp(String? ip) {
    if (ip == null) return false;
    final v = ip.trim();
    if (v == softApIp) return true;
    // El SoftAP reparte 192.168.4.x; cualquier host de ese /24 es modo AP.
    if (v.startsWith('192.168.4.')) return true;
    return false;
  }

  /// Backoff exponencial para reintentos de sincronización:
  /// intento 0 -> 100ms, 1 -> 500ms, 2 -> 2s, resto -> 2s cap.
  static Duration backoffForAttempt(int attempt) {
    if (attempt <= 0) return const Duration(milliseconds: 100);
    if (attempt == 1) return const Duration(milliseconds: 500);
    return const Duration(seconds: 2);
  }
}
