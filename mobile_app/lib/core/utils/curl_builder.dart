/// Genera un cURL reproducible sin volcar el JPEG completo ni la API key.
class CurlBuilder {
  static String redactKey(String apiKey) {
    if (apiKey.isEmpty) return '***';
    if (apiKey.length <= 8) return '***';
    return '${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}';
  }

  static String compactJsonBody(String requestJson, {int head = 160, int tail = 80}) {
    if (requestJson.length <= 320) return requestJson;
    return '${requestJson.substring(0, head)}... [payload recortado] ...${requestJson.substring(requestJson.length - tail)}';
  }

  static String chatCompletions({
    required String endpointUrl,
    required String apiKey,
    required String requestJson,
  }) {
    final redacted = redactKey(apiKey);
    final body = compactJsonBody(requestJson);
    if (endpointUrl.contains('generativelanguage.googleapis.com')) {
      return 'curl "$endpointUrl" \\\n'
          '  -H "Content-Type: application/json" \\\n'
          '  -H "X-goog-api-key: $redacted" \\\n'
          '  -X POST \\\n'
          "  -d '$body'";
    }
    return 'curl -X POST "$endpointUrl" \\\n'
        '  -H "Content-Type: application/json" \\\n'
        '  -H "Authorization: Bearer $redacted" \\\n'
        "  -d '$body'";
  }
}
