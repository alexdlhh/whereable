import 'dart:typed_data';

/// Servicio de reconocimiento y filtrado de intenciones/palabras clave offline Vosk.
/// Funciona de forma local con gramática restringida para reducir consumo y proteger privacidad.
class VoskKeywordService {
  VoskKeywordService({
    List<String>? customWakeWords,
    List<String>? customGrammar,
  })  : _wakeWords = customWakeWords ??
            const [
              'gafas',
              'oye gafas',
              'hey gafas',
              'dime gafas',
              'asistente',
              'glasses',
            ],
        _grammar = customGrammar ??
            const [
              'identifica',
              'diagnostica',
              'procedimiento',
              'desmontar',
              'medicion',
              'medición',
              'tension',
              'tensión',
              'voltaje',
              'resistencia',
              'continuidad',
              'numero de serie',
              'número de serie',
              'placa',
              'averia',
              'avería',
              'fusible',
              'borne',
              'esquema',
              'peligro',
              'seguridad',
              'que es esto',
              'qué es esto',
              'analiza',
              'bateria',
              'batería',
              'beep',
              'ping',
            ];

  final List<String> _wakeWords;
  final List<String> _grammar;

  List<String> get wakeWords => List.unmodifiable(_wakeWords);
  List<String> get grammar => List.unmodifiable(_grammar);

  /// Normaliza texto en español eliminando tildes y diacríticos para matching robusto.
  static String normalizeSpanish(String text) {
    return text
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .trim();
  }

  /// Evalúa un texto transcrito o reconocido localmente para determinar si contiene
  /// una palabra clave de activación y/o una intención válida de soporte técnico.
  ({
    bool hasWakeWord,
    String? matchedWakeWord,
    bool hasGrammarMatch,
    String? matchedIntent,
    String cleanPrompt,
    bool isLocalOnlyAction,
  }) evaluateTextIntent(String rawText) {
    final rawTrimmed = rawText.trim();
    if (rawTrimmed.isEmpty) {
      return (
        hasWakeWord: false,
        matchedWakeWord: null,
        hasGrammarMatch: false,
        matchedIntent: null,
        cleanPrompt: '',
        isLocalOnlyAction: false,
      );
    }

    final normalized = normalizeSpanish(rawTrimmed);

    String? foundWakeWord;
    for (final kw in _wakeWords) {
      final normKw = normalizeSpanish(kw);
      if (normalized.startsWith(normKw) || normalized.contains(normKw)) {
        foundWakeWord = kw;
        break;
      }
    }

    // Extraer prompt limpio eliminando la palabra de activación
    String cleanPrompt = rawTrimmed;
    if (foundWakeWord != null) {
      final reg = RegExp(RegExp.escape(foundWakeWord), caseSensitive: false);
      cleanPrompt = cleanPrompt.replaceFirst(reg, '').trim();
      cleanPrompt = cleanPrompt.replaceFirst(RegExp(r'^[,.:;¿?¡! ]+'), '');
    }

    String? foundIntent;
    for (final cmd in _grammar) {
      final normCmd = normalizeSpanish(cmd);
      if (normalized.contains(normCmd)) {
        foundIntent = cmd;
        break;
      }
    }

    // Comandos que se pueden resolver 100% en local sin llamar al servidor LLM
    final isLocalOnly = foundIntent != null &&
        (normalizeSpanish(foundIntent) == 'bateria' ||
            normalizeSpanish(foundIntent) == 'beep' ||
            normalizeSpanish(foundIntent) == 'ping');

    return (
      hasWakeWord: foundWakeWord != null,
      matchedWakeWord: foundWakeWord,
      hasGrammarMatch: foundIntent != null,
      matchedIntent: foundIntent,
      cleanPrompt: cleanPrompt.isNotEmpty ? cleanPrompt : rawTrimmed,
      isLocalOnlyAction: isLocalOnly,
    );
  }

  /// Procesa un bloque de audio PCM simulando el comportamiento de acceptWaveformBytes de Vosk
  /// para pruebas locales y detección rápida de patrones acústicos de voz.
  Future<String?> processPcmChunk(Uint8List pcmChunk) async {
    if (pcmChunk.length < 160) return null;
    return null;
  }
}
