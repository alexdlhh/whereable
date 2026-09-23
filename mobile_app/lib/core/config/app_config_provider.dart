import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';

class AppConfigState {
  final String apiBaseUrl;
  final String apiKey;
  final String modelName;
  final String systemPrompt;
  final bool enableTtsPlayback;
  /// 'system' = TTS del dispositivo gratis (es-ES, default),
  /// 'cloud' = endpoint OpenAI speech, 'off' = sin voz.
  final String ttsMode;
  final String ttsVoiceName;
  final double ttsRate;
  final double ttsPitch;
  final double ttsVolume;
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
    this.ttsMode = 'system',
    this.ttsVoiceName = '',
    this.ttsRate = 0.5,
    this.ttsPitch = 1.0,
    this.ttsVolume = 1.0,
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
    String? ttsMode,
    String? ttsVoiceName,
    double? ttsRate,
    double? ttsPitch,
    double? ttsVolume,
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
      ttsMode: ttsMode ?? this.ttsMode,
      ttsVoiceName: ttsVoiceName ?? this.ttsVoiceName,
      ttsRate: ttsRate ?? this.ttsRate,
      ttsPitch: ttsPitch ?? this.ttsPitch,
      ttsVolume: ttsVolume ?? this.ttsVolume,
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
  static const _kTtsMode = 'cfg_tts_mode';
  static const _kTtsVoice = 'cfg_tts_voice';
  static const _kTtsRate = 'cfg_tts_rate';
  static const _kTtsPitch = 'cfg_tts_pitch';
  static const _kTtsVol = 'cfg_tts_vol';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = state.copyWith(
      apiBaseUrl: p.getString(_kUrl) ?? state.apiBaseUrl,
      apiKey: p.getString(_kKey) ?? state.apiKey,
      modelName: p.getString(_kModel) ?? state.modelName,
      enableTtsPlayback: p.getBool(_kTts) ?? state.enableTtsPlayback,
      workOrderId: p.getString(_kWork) ?? state.workOrderId,
      ttsMode: p.getString(_kTtsMode) ?? state.ttsMode,
      ttsVoiceName: p.getString(_kTtsVoice) ?? state.ttsVoiceName,
      ttsRate: p.getDouble(_kTtsRate) ?? state.ttsRate,
      ttsPitch: p.getDouble(_kTtsPitch) ?? state.ttsPitch,
      ttsVolume: p.getDouble(_kTtsVol) ?? state.ttsVolume,
    );
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, state.apiBaseUrl);
    await p.setString(_kKey, state.apiKey);
    await p.setString(_kModel, state.modelName);
    await p.setBool(_kTts, state.enableTtsPlayback);
    await p.setString(_kWork, state.workOrderId);
    await p.setString(_kTtsMode, state.ttsMode);
    await p.setString(_kTtsVoice, state.ttsVoiceName);
    await p.setDouble(_kTtsRate, state.ttsRate);
    await p.setDouble(_kTtsPitch, state.ttsPitch);
    await p.setDouble(_kTtsVol, state.ttsVolume);
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

  void updateTtsSettings({String? mode, String? voiceName, double? rate, double? pitch, double? volume}) {
    state = state.copyWith(
      ttsMode: mode ?? state.ttsMode,
      ttsVoiceName: voiceName ?? state.ttsVoiceName,
      ttsRate: rate ?? state.ttsRate,
      ttsPitch: pitch ?? state.ttsPitch,
      ttsVolume: volume ?? state.ttsVolume,
    );
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
