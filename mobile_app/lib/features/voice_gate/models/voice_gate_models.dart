import 'dart:convert';

/// Motivo por el cual una captura de voz fue descartada y NO enviada al servidor.
enum VoiceGateRejectionReason {
  none,
  unauthorizedSpeaker,
  noKeywordDetected,
  silenceOrNoise,
  lowConfidence,
}

/// Configuración del filtro Edge (Sherpa-ONNX + Vosk).
class VoiceGateConfig {
  final bool enabled;
  final bool requireSpeakerMatch;
  final bool requireWakeKeyword;
  final double similarityThreshold;
  final List<String> wakeKeywords;
  final List<String> grammarWhitelist;
  final double minRmsEnergy;

  const VoiceGateConfig({
    this.enabled = true,
    this.requireSpeakerMatch = true,
    this.requireWakeKeyword = true,
    this.similarityThreshold = 0.68,
    this.wakeKeywords = const [
      'gafas',
      'oye gafas',
      'hey gafas',
      'asistente',
      'glasses',
    ],
    this.grammarWhitelist = const [
      'identifica',
      'diagnostica',
      'procedimiento',
      'desmontar',
      'medicion',
      'voltaje',
      'resistencia',
      'numero de serie',
      'placa',
      'peligro',
      'seguridad',
      'que es esto',
      'analiza',
    ],
    this.minRmsEnergy = 0.015,
  });

  VoiceGateConfig copyWith({
    bool? enabled,
    bool? requireSpeakerMatch,
    bool? requireWakeKeyword,
    double? similarityThreshold,
    List<String>? wakeKeywords,
    List<String>? grammarWhitelist,
    double? minRmsEnergy,
  }) {
    return VoiceGateConfig(
      enabled: enabled ?? this.enabled,
      requireSpeakerMatch: requireSpeakerMatch ?? this.requireSpeakerMatch,
      requireWakeKeyword: requireWakeKeyword ?? this.requireWakeKeyword,
      similarityThreshold: similarityThreshold ?? this.similarityThreshold,
      wakeKeywords: wakeKeywords ?? this.wakeKeywords,
      grammarWhitelist: grammarWhitelist ?? this.grammarWhitelist,
      minRmsEnergy: minRmsEnergy ?? this.minRmsEnergy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'requireSpeakerMatch': requireSpeakerMatch,
      'requireWakeKeyword': requireWakeKeyword,
      'similarityThreshold': similarityThreshold,
      'wakeKeywords': wakeKeywords,
      'grammarWhitelist': grammarWhitelist,
      'minRmsEnergy': minRmsEnergy,
    };
  }

  factory VoiceGateConfig.fromMap(Map<String, dynamic> map) {
    return VoiceGateConfig(
      enabled: map['enabled'] ?? true,
      requireSpeakerMatch: map['requireSpeakerMatch'] ?? true,
      requireWakeKeyword: map['requireWakeKeyword'] ?? true,
      similarityThreshold:
          (map['similarityThreshold'] as num?)?.toDouble() ?? 0.68,
      wakeKeywords: (map['wakeKeywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['gafas', 'oye gafas', 'hey gafas', 'asistente', 'glasses'],
      grammarWhitelist: (map['grammarWhitelist'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [
            'identifica',
            'diagnostica',
            'procedimiento',
            'desmontar',
            'medicion',
            'numero de serie',
            'analiza',
          ],
      minRmsEnergy: (map['minRmsEnergy'] as num?)?.toDouble() ?? 0.015,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory VoiceGateConfig.fromJson(String source) =>
      VoiceGateConfig.fromMap(jsonDecode(source));
}

/// Resultado de la evaluación del Voice Gatekeeper antes de contactar con el LLM.
class VoiceGateEvaluation {
  final bool shouldForwardToServer;
  final double speakerSimilarity;
  final bool isSpeakerAuthorized;
  final String? detectedKeyword;
  final String? recognizedText;
  final String promptForServer;
  final VoiceGateRejectionReason rejectionReason;
  final String reasonDescription;
  final int processingLatencyMs;

  const VoiceGateEvaluation({
    required this.shouldForwardToServer,
    required this.speakerSimilarity,
    required this.isSpeakerAuthorized,
    this.detectedKeyword,
    this.recognizedText,
    required this.promptForServer,
    this.rejectionReason = VoiceGateRejectionReason.none,
    required this.reasonDescription,
    this.processingLatencyMs = 0,
  });

  factory VoiceGateEvaluation.accepted({
    required double speakerSimilarity,
    String? detectedKeyword,
    String? recognizedText,
    required String promptForServer,
    int processingLatencyMs = 0,
    String? reasonDescription,
  }) {
    return VoiceGateEvaluation(
      shouldForwardToServer: true,
      speakerSimilarity: speakerSimilarity,
      isSpeakerAuthorized: true,
      detectedKeyword: detectedKeyword,
      recognizedText: recognizedText,
      promptForServer: promptForServer,
      rejectionReason: VoiceGateRejectionReason.none,
      reasonDescription: reasonDescription ?? 'Voz autorizada y comando válido para servidor.',
      processingLatencyMs: processingLatencyMs,
    );
  }

  factory VoiceGateEvaluation.rejected({
    required VoiceGateRejectionReason reason,
    required String reasonDescription,
    double speakerSimilarity = 0.0,
    bool isSpeakerAuthorized = false,
    String? detectedKeyword,
    String? recognizedText,
    int processingLatencyMs = 0,
  }) {
    return VoiceGateEvaluation(
      shouldForwardToServer: false,
      speakerSimilarity: speakerSimilarity,
      isSpeakerAuthorized: isSpeakerAuthorized,
      detectedKeyword: detectedKeyword,
      recognizedText: recognizedText,
      promptForServer: '',
      rejectionReason: reason,
      reasonDescription: reasonDescription,
      processingLatencyMs: processingLatencyMs,
    );
  }
}
