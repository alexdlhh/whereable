import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/voice_gate_models.dart';
import 'models/speaker_profile.dart';
import 'speaker_verifier.dart';
import 'vosk_keyword_service.dart';

/// Servicio unificado de control perimetral de voz (Edge Gatekeeper).
/// Combina Sherpa-ONNX (Speaker Verification) y Vosk (Keyword & Intent Spotting)
/// para filtrar qué audios se envían al servidor y asegurar que las gafas solo respondan a su dueño.
class VoiceGatekeeperService {
  VoiceGatekeeperService({
    VoiceGateConfig? config,
    SherpaSpeakerVerifier? speakerVerifier,
    VoskKeywordService? keywordService,
  })  : _config = config ?? const VoiceGateConfig(),
        _speakerVerifier = speakerVerifier ?? SherpaSpeakerVerifier(),
        _keywordService = keywordService ?? VoskKeywordService();

  VoiceGateConfig _config;
  final SherpaSpeakerVerifier _speakerVerifier;
  final VoskKeywordService _keywordService;

  static const _kConfigKey = 'glasses_voice_gate_config';

  VoiceGateConfig get config => _config;
  SherpaSpeakerVerifier get speakerVerifier => _speakerVerifier;
  VoskKeywordService get keywordService => _keywordService;
  SpeakerProfile get speakerProfile => _speakerVerifier.currentProfile;

  Future<void> initialize() async {
    await _loadConfig();
    await _speakerVerifier.loadProfile();
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kConfigKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        _config = VoiceGateConfig.fromJson(jsonStr);
      }
    } catch (e) {
      debugPrint('Error cargando configuración VoiceGate: $e');
    }
  }

  Future<void> updateConfig(VoiceGateConfig newConfig) async {
    _config = newConfig;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kConfigKey, newConfig.toJson());
    } catch (e) {
      debugPrint('Error guardando configuración VoiceGate: $e');
    }
  }

  /// Calibra la voz del usuario registrando una muestra de audio PCM 16kHz.
  Future<SpeakerProfile> enrollTechnicianVoice(Uint8List pcmBytes) async {
    return await _speakerVerifier.enrollSample(pcmBytes);
  }

  /// Borra el perfil de voz del técnico.
  Future<void> resetTechnicianVoice() async {
    await _speakerVerifier.clearProfile();
  }

  /// Evalúa si una entrada de audio / texto debe transmitirse al servidor de IA.
  /// Ejecuta el pipeline completo: VAD -> Speaker Verification (Sherpa-ONNX) -> Intent Spotting (Vosk).
  Future<VoiceGateEvaluation> evaluateAudioQuery({
    required Uint8List pcmBytes,
    required String transcribedText,
  }) async {
    final sw = Stopwatch()..start();

    if (!_config.enabled) {
      sw.stop();
      return VoiceGateEvaluation.accepted(
        speakerSimilarity: 1.0,
        recognizedText: transcribedText,
        promptForServer: transcribedText,
        processingLatencyMs: sw.elapsedMilliseconds,
        reasonDescription: 'Filtro Edge desactivado. Consulta permitida directamente.',
      );
    }

    // 1. Filtro VAD / Energía RMS (descartar silencio y zumbidos)
    final energy = _speakerVerifier.computeRmsEnergy(pcmBytes);
    if (energy < _config.minRmsEnergy && transcribedText.trim().isEmpty) {
      sw.stop();
      return VoiceGateEvaluation.rejected(
        reason: VoiceGateRejectionReason.silenceOrNoise,
        reasonDescription: 'Descartado: silencio o energía insuficiente (${energy.toStringAsFixed(3)})',
        processingLatencyMs: sw.elapsedMilliseconds,
      );
    }

    // 2. Filtro de Identificación de Hablante (Sherpa-ONNX)
    double similarity = 1.0;
    bool speakerAuthorized = true;

    if (_config.requireSpeakerMatch && _speakerVerifier.hasEnrolledProfile) {
      final verifyResult = _speakerVerifier.verifySpeaker(
        pcmBytes,
        customThreshold: _config.similarityThreshold,
      );
      similarity = verifyResult.similarityScore;
      speakerAuthorized = verifyResult.isAuthorized;

      if (!speakerAuthorized) {
        sw.stop();
        return VoiceGateEvaluation.rejected(
          reason: VoiceGateRejectionReason.unauthorizedSpeaker,
          reasonDescription:
              'Locutor no reconocido (Similitud: ${(similarity * 100).toStringAsFixed(1)}% < ${(_config.similarityThreshold * 100).toStringAsFixed(1)}%). Protegido contra terceras personas.',
          speakerSimilarity: similarity,
          isSpeakerAuthorized: false,
          recognizedText: transcribedText,
          processingLatencyMs: sw.elapsedMilliseconds,
        );
      }
    }

    // 3. Filtro de Intención y Palabra Clave (Vosk Offline Grammar)
    final intentResult = _keywordService.evaluateTextIntent(transcribedText);

    if (_config.requireWakeKeyword && !intentResult.hasWakeWord && !intentResult.hasGrammarMatch) {
      sw.stop();
      return VoiceGateEvaluation.rejected(
        reason: VoiceGateRejectionReason.noKeywordDetected,
        reasonDescription:
            'Descartado: conversación ambiente sin palabra clave ("gafas", "asistente", etc.).',
        speakerSimilarity: similarity,
        isSpeakerAuthorized: speakerAuthorized,
        recognizedText: transcribedText,
        processingLatencyMs: sw.elapsedMilliseconds,
      );
    }

    sw.stop();
    return VoiceGateEvaluation.accepted(
      speakerSimilarity: similarity,
      detectedKeyword: intentResult.matchedWakeWord,
      recognizedText: transcribedText,
      promptForServer: intentResult.cleanPrompt,
      processingLatencyMs: sw.elapsedMilliseconds,
    );
  }
}

final voiceGatekeeperProvider = Provider<VoiceGatekeeperService>((ref) {
  final service = VoiceGatekeeperService();
  service.initialize();
  return service;
});
