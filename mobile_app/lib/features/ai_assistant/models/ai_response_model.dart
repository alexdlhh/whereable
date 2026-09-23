class AiPipelineMetrics {
  final int cameraCaptureMs;
  final int sttMs;
  final int llmLatencyMs;
  final int ttsMs;
  final int glassesAudioTransferMs;
  final int totalRoundTripMs;
  final bool audioFallbackToPhone;

  AiPipelineMetrics({
    this.cameraCaptureMs = 0,
    this.sttMs = 0,
    this.llmLatencyMs = 0,
    this.ttsMs = 0,
    this.glassesAudioTransferMs = 0,
    this.totalRoundTripMs = 0,
    this.audioFallbackToPhone = false,
  });

  AiPipelineMetrics copyWith({
    int? cameraCaptureMs,
    int? sttMs,
    int? llmLatencyMs,
    int? ttsMs,
    int? glassesAudioTransferMs,
    int? totalRoundTripMs,
    bool? audioFallbackToPhone,
  }) {
    return AiPipelineMetrics(
      cameraCaptureMs: cameraCaptureMs ?? this.cameraCaptureMs,
      sttMs: sttMs ?? this.sttMs,
      llmLatencyMs: llmLatencyMs ?? this.llmLatencyMs,
      ttsMs: ttsMs ?? this.ttsMs,
      glassesAudioTransferMs: glassesAudioTransferMs ?? this.glassesAudioTransferMs,
      totalRoundTripMs: totalRoundTripMs ?? this.totalRoundTripMs,
      audioFallbackToPhone: audioFallbackToPhone ?? this.audioFallbackToPhone,
    );
  }
}

class AiInteractionResult {
  final String userQuery;
  final String assistantResponse;
  final AiPipelineMetrics metrics;
  final Map<String, dynamic> rawRequestPayload;
  final Map<String, dynamic> rawResponsePayload;
  final String generatedCurl;
  final DateTime timestamp;
  final bool usedMock;
  final bool cameraMissing;

  AiInteractionResult({
    required this.userQuery,
    required this.assistantResponse,
    required this.metrics,
    required this.rawRequestPayload,
    required this.rawResponsePayload,
    required this.generatedCurl,
    required this.timestamp,
    this.usedMock = false,
    this.cameraMissing = false,
  });
}
