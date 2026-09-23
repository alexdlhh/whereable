# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "mobile_app" / "lib"

(LIB / "features" / "ai_assistant" / "models" / "ai_response_model.dart").write_text(r'''class AiPipelineMetrics {
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
'''.replace('\r\n', '\n'), encoding='utf-8')

(LIB / "core" / "config" / "app_config_provider.dart").write_text(r'''import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';

class AppConfigState {
  final String apiBaseUrl;
  final String apiKey;
  final String modelName;
  final String systemPrompt;
  final bool enableTtsPlayback;
  final int cameraJpegQuality;
  final int cameraBrightness;
  final int cameraContrast;
  final String workOrderId;

  AppConfigState({
    this.apiBaseUrl = ApiConstants.defaultAiBaseUrl,
    this.apiKey = ApiConstants.defaultApiKey,
    this.modelName = ApiConstants.defaultModel,
    this.systemPrompt = ApiConstants.systemInstruction,
    this.enableTtsPlayback = true,
    this.cameraJpegQuality = 12,
    this.cameraBrightness = 1,
    this.cameraContrast = 1,
    this.workOrderId = '',
  });

  AppConfigState copyWith({
    String? apiBaseUrl,
    String? apiKey,
    String? modelName,
    String? systemPrompt,
    bool? enableTtsPlayback,
    int? cameraJpegQuality,
    int? cameraBrightness,
    int? cameraContrast,
    String? workOrderId,
  }) {
    return AppConfigState(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      apiKey: apiKey ?? this.apiKey,
      modelName: modelName ?? this.modelName,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      enableTtsPlayback: enableTtsPlayback ?? this.enableTtsPlayback,
      cameraJpegQuality: cameraJpegQuality ?? this.cameraJpegQuality,
      cameraBrightness: cameraBrightness ?? this.cameraBrightness,
      cameraContrast: cameraContrast ?? this.cameraContrast,
      workOrderId: workOrderId ?? this.workOrderId,
    );
  }
}

class AppConfigNotifier extends StateNotifier<AppConfigState> {
  AppConfigNotifier() : super(AppConfigState()) {
    _load();
  }

  static const _kUrl = 'cfg_api_url';
  static const _kKey = 'cfg_api_key';
  static const _kModel = 'cfg_model';
  static const _kTts = 'cfg_tts';
  static const _kWork = 'cfg_work_order';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = state.copyWith(
      apiBaseUrl: p.getString(_kUrl) ?? state.apiBaseUrl,
      apiKey: p.getString(_kKey) ?? state.apiKey,
      modelName: p.getString(_kModel) ?? state.modelName,
      enableTtsPlayback: p.getBool(_kTts) ?? state.enableTtsPlayback,
      workOrderId: p.getString(_kWork) ?? state.workOrderId,
    );
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, state.apiBaseUrl);
    await p.setString(_kKey, state.apiKey);
    await p.setString(_kModel, state.modelName);
    await p.setBool(_kTts, state.enableTtsPlayback);
    await p.setString(_kWork, state.workOrderId);
  }

  void updateApiSettings({
    String? baseUrl,
    String? apiKey,
    String? model,
    String? systemPrompt,
  }) {
    state = state.copyWith(
      apiBaseUrl: baseUrl ?? state.apiBaseUrl,
      apiKey: apiKey ?? state.apiKey,
      modelName: model ?? state.modelName,
      systemPrompt: systemPrompt ?? state.systemPrompt,
    );
    _persist();
  }

  void toggleTtsPlayback(bool enabled) {
    state = state.copyWith(enableTtsPlayback: enabled);
    _persist();
  }

  void updateWorkOrder(String id) {
    state = state.copyWith(workOrderId: id);
    _persist();
  }

  void updateCameraParams({int? quality, int? brightness, int? contrast}) {
    state = state.copyWith(
      cameraJpegQuality: quality ?? state.cameraJpegQuality,
      cameraBrightness: brightness ?? state.cameraBrightness,
      cameraContrast: contrast ?? state.cameraContrast,
    );
  }
}

final appConfigProvider = StateNotifierProvider<AppConfigNotifier, AppConfigState>((ref) {
  return AppConfigNotifier();
});
'''.replace('\r\n', '\n'), encoding='utf-8')

print('wrote models and config')
