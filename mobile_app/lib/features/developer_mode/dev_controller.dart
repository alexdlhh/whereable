import 'dart:async';
import 'dart:io';
import 'dart:math' show sqrt;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../core/audio/phone_playback.dart';
import '../../core/utils/wav_encoder.dart';
import '../ai_assistant/models/ai_response_model.dart';
import '../ai_assistant/ai_service.dart';
import '../connectivity/ble_service.dart';
import '../connectivity/wifi_sync_service.dart';
import '../background/background_service.dart';
import '../voice_gate/voice_gatekeeper_service.dart';
import '../voice_gate/models/voice_gate_models.dart';
import '../../core/config/app_config_provider.dart';

class GlassesMicStats {
  final int sampleCount;
  final int peakAmplitude;
  final double rmsLevel;
  final double dcOffset;
  final DateTime timestamp;

  GlassesMicStats({
    required this.sampleCount,
    required this.peakAmplitude,
    required this.rmsLevel,
    required this.dcOffset,
    required this.timestamp,
  });
}

class DevModeState {
  final bool isDevModeEnabled;
  final bool isSimulatorMode;
  final int pingMs;
  final Uint8List? latestFrame;
  final List<AiInteractionResult> history;
  final bool isProcessing;
  final String consoleLog;
  final GlassesTelemetry? telemetry;
  final bool isRecordingVoice;
  final bool isCalibratingVoice;
  final String lastError;
  final bool isBackgroundModeActive;
  final VoiceGateEvaluation? lastVoiceEvaluation;
  final bool isAutoTelemetryEnabled;
  final bool isTestingMic;
  final GlassesMicStats? lastMicStats;
  /// Última muestra cruda S16LE 16kHz mono de /mic_sample (para escuchar/guardar).
  final Uint8List? lastMicSampleBytes;

  // Diagnostic Suite: Logs remotos, Crash Log y Network Inspector
  final List<Map<String, dynamic>> firmwareLogs;
  final Map<String, dynamic>? firmwareCrashLog;
  final bool isLoadingFirmwareLogs;
  final Map<String, dynamic>? networkStats;
  final int lastNetworkLatencyMs;
  final int lastAiLatencyMs;
  final String lastEndpointTested;
  final int lastResponseCode;

  DevModeState({
    this.isDevModeEnabled = false,
    this.isSimulatorMode = false,
    this.pingMs = -1,
    this.latestFrame,
    this.history = const [],
    this.isProcessing = false,
    this.consoleLog = "=== CONSOLA DE DIAGNÓSTICO ===\n",
    this.telemetry,
    this.isRecordingVoice = false,
    this.isCalibratingVoice = false,
    this.lastError = '',
    this.isBackgroundModeActive = false,
    this.lastVoiceEvaluation,
    this.isAutoTelemetryEnabled = false,
    this.isTestingMic = false,
    this.lastMicStats,
    this.lastMicSampleBytes,
    this.firmwareLogs = const [],
    this.firmwareCrashLog,
    this.isLoadingFirmwareLogs = false,
    this.networkStats,
    this.lastNetworkLatencyMs = 0,
    this.lastAiLatencyMs = 0,
    this.lastEndpointTested = '—',
    this.lastResponseCode = 0,
  });

  DevModeState copyWith({
    bool? isDevModeEnabled,
    bool? isSimulatorMode,
    int? pingMs,
    Uint8List? latestFrame,
    List<AiInteractionResult>? history,
    bool? isProcessing,
    String? consoleLog,
    GlassesTelemetry? telemetry,
    bool? isRecordingVoice,
    bool? isCalibratingVoice,
    String? lastError,
    bool? isBackgroundModeActive,
    VoiceGateEvaluation? lastVoiceEvaluation,
    bool? isAutoTelemetryEnabled,
    bool? isTestingMic,
    GlassesMicStats? lastMicStats,
    Uint8List? lastMicSampleBytes,
    List<Map<String, dynamic>>? firmwareLogs,
    Map<String, dynamic>? firmwareCrashLog,
    bool? isLoadingFirmwareLogs,
    Map<String, dynamic>? networkStats,
    int? lastNetworkLatencyMs,
    int? lastAiLatencyMs,
    String? lastEndpointTested,
    int? lastResponseCode,
  }) {
    return DevModeState(
      isDevModeEnabled: isDevModeEnabled ?? this.isDevModeEnabled,
      isSimulatorMode: isSimulatorMode ?? this.isSimulatorMode,
      pingMs: pingMs ?? this.pingMs,
      latestFrame: latestFrame ?? this.latestFrame,
      history: history ?? this.history,
      isProcessing: isProcessing ?? this.isProcessing,
      consoleLog: consoleLog ?? this.consoleLog,
      telemetry: telemetry ?? this.telemetry,
      isRecordingVoice: isRecordingVoice ?? this.isRecordingVoice,
      isCalibratingVoice: isCalibratingVoice ?? this.isCalibratingVoice,
      lastError: lastError ?? this.lastError,
      isBackgroundModeActive: isBackgroundModeActive ?? this.isBackgroundModeActive,
      lastVoiceEvaluation: lastVoiceEvaluation ?? this.lastVoiceEvaluation,
      isAutoTelemetryEnabled: isAutoTelemetryEnabled ?? this.isAutoTelemetryEnabled,
      isTestingMic: isTestingMic ?? this.isTestingMic,
      lastMicStats: lastMicStats ?? this.lastMicStats,
      lastMicSampleBytes: lastMicSampleBytes ?? this.lastMicSampleBytes,
      firmwareLogs: firmwareLogs ?? this.firmwareLogs,
      firmwareCrashLog: firmwareCrashLog ?? this.firmwareCrashLog,
      isLoadingFirmwareLogs: isLoadingFirmwareLogs ?? this.isLoadingFirmwareLogs,
      networkStats: networkStats ?? this.networkStats,
      lastNetworkLatencyMs: lastNetworkLatencyMs ?? this.lastNetworkLatencyMs,
      lastAiLatencyMs: lastAiLatencyMs ?? this.lastAiLatencyMs,
      lastEndpointTested: lastEndpointTested ?? this.lastEndpointTested,
      lastResponseCode: lastResponseCode ?? this.lastResponseCode,
    );
  }
}

class DevController extends StateNotifier<DevModeState> {
  DevController(this.ref) : super(DevModeState()) {
    _checkInitialBackgroundState();
  }

  final Ref ref;
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _telemetryTimer;

  Future<void> _checkInitialBackgroundState() async {
    final running = await BackgroundServiceManager.isServiceRunning();
    if (running != state.isBackgroundModeActive) {
      state = state.copyWith(isBackgroundModeActive: running);
    }
  }

  String? _resolveIp() {
    final bleState = ref.read(bleServiceProvider);
    return bleState.glassesIp ??
        bleState.savedProfile.lastKnownIp ??
        (state.isSimulatorMode ? "192.168.4.1" : null);
  }

  Future<void> toggleBackgroundMode() async {
    if (state.isBackgroundModeActive) {
      await BackgroundServiceManager.stopBackgroundService();
      state = state.copyWith(isBackgroundModeActive: false);
      log("Modo pantalla bloqueada / segundo plano: DESACTIVADO");
    } else {
      final permOk = await BackgroundServiceManager.requestPermissions();
      if (!permOk) {
        log("Aviso: Permisos de notificación / batería para segundo plano requeridos.");
      }
      final ip = _resolveIp() ?? 'Sin IP';
      final bat = state.telemetry != null ? '${state.telemetry!.batteryPct}%' : '—';
      final started = await BackgroundServiceManager.startBackgroundService(
        title: 'GlassesPro · Enlace Activo',
        text: 'IP: $ip · Bat: $bat · Toca una acción para consultar',
      );
      state = state.copyWith(isBackgroundModeActive: started);
      log("Modo pantalla bloqueada / segundo plano: ${started ? 'ACTIVADO' : 'ERROR AL INICIAR'}");
    }
  }

  void handleBackgroundAction(String action) {
    log("Acción desde pantalla de bloqueo: $action");
    switch (action) {
      case BackgroundServiceManager.actionIdentify:
        triggerAiQuery("Identifica el componente o producto que estoy viendo. Nombra marcas, códigos y función.");
        break;
      case BackgroundServiceManager.actionDiagnose:
        triggerAiQuery("¿Detectas fallo, quemadura, conector suelto o desgaste? Indica riesgo y siguiente medición.");
        break;
      case BackgroundServiceManager.actionProcedure:
        triggerAiQuery("Guíame paso a paso para desmontarlo con seguridad, sin forzar flex ni clips.");
        break;
      default:
        triggerAiQuery("Analiza lo que veo y dame soporte técnico inmediato.");
        break;
    }
  }

  void toggleDevMode() {
    state = state.copyWith(isDevModeEnabled: !state.isDevModeEnabled);
    log("Modo diagnóstico: ${state.isDevModeEnabled ? 'ON' : 'OFF'}");
  }

  void toggleSimulatorMode() {
    state = state.copyWith(isSimulatorMode: !state.isSimulatorMode);
    try {
      ref.read(bleServiceProvider.notifier).setSimulatorMode(state.isSimulatorMode);
    } catch (_) {}
    log("Simulador: ${state.isSimulatorMode ? 'ON (sin hardware)' : 'OFF'}");
  }

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    var next = "${state.consoleLog}[$timestamp] $message\n";
    if (next.length > 12000) {
      next = next.substring(next.length - 10000);
    }
    state = state.copyWith(consoleLog: next);
  }

  void clearLogs() {
    state = state.copyWith(consoleLog: "=== LOGS REINICIADOS ===\n");
  }

  Future<void> fetchFirmwareLogs({String? level}) async {
    final ip = _resolveIp();
    if (ip == null) {
      log("Sin IP para consultar logs del firmware.");
      return;
    }
    state = state.copyWith(isLoadingFirmwareLogs: true);
    final stopwatch = Stopwatch()..start();
    try {
      final wifiService = ref.read(wifiSyncServiceProvider);
      final logs = await wifiService.fetchFirmwareLogs(ip, limit: 60, level: level);
      stopwatch.stop();
      if (logs != null) {
        state = state.copyWith(
          firmwareLogs: logs,
          isLoadingFirmwareLogs: false,
          lastNetworkLatencyMs: stopwatch.elapsedMilliseconds,
          lastEndpointTested: '/logs',
          lastResponseCode: 200,
        );
        log("Obtenidos ${logs.length} logs remotos del firmware (${stopwatch.elapsedMilliseconds}ms).");
      } else {
        state = state.copyWith(
          isLoadingFirmwareLogs: false,
          lastEndpointTested: '/logs',
          lastResponseCode: 500,
        );
        log("Fallo al descargar logs del firmware en $ip.");
      }
    } catch (e) {
      state = state.copyWith(isLoadingFirmwareLogs: false);
      log("Error consultando logs: $e");
    }
  }

  Future<void> clearFirmwareLogs() async {
    final ip = _resolveIp();
    if (ip == null) return;
    try {
      final wifiService = ref.read(wifiSyncServiceProvider);
      final ok = await wifiService.clearFirmwareLogs(ip);
      if (ok) {
        state = state.copyWith(firmwareLogs: const []);
        log("Logs del firmware eliminados con éxito.");
      }
    } catch (_) {}
  }

  Future<void> fetchCrashLog() async {
    final ip = _resolveIp();
    if (ip == null) {
      log("Sin IP para consultar crash log.");
      return;
    }
    try {
      final wifiService = ref.read(wifiSyncServiceProvider);
      final crash = await wifiService.fetchCrashLog(ip);
      if (crash != null) {
        state = state.copyWith(
          firmwareCrashLog: crash,
          lastEndpointTested: '/crash_log',
          lastResponseCode: 200,
        );
        log("Crash log NVS obtenido: Causa=${crash['last_reason']} · Caídas=${crash['crash_count']}");
      }
    } catch (e) {
      log("Error consultando crash log: $e");
    }
  }

  Future<void> clearCrashLog() async {
    final ip = _resolveIp();
    if (ip == null) return;
    try {
      final wifiService = ref.read(wifiSyncServiceProvider);
      final ok = await wifiService.clearCrashLog(ip);
      if (ok) {
        state = state.copyWith(firmwareCrashLog: null);
        log("Registro de caídas NVS limpiado en el dispositivo.");
      }
    } catch (_) {}
  }

  Future<void> fetchNetworkStats() async {
    final ip = _resolveIp();
    if (ip == null) return;
    try {
      final wifiService = ref.read(wifiSyncServiceProvider);
      final stats = await wifiService.fetchNetworkStats(ip);
      if (stats != null) {
        state = state.copyWith(
          networkStats: stats,
          lastEndpointTested: '/network_stats',
          lastResponseCode: 200,
        );
      }
    } catch (_) {}
  }

  void deleteHistoryItem(int index) {
    if (index >= 0 && index < state.history.length) {
      final updated = List<AiInteractionResult>.from(state.history)..removeAt(index);
      state = state.copyWith(history: updated);
      log("Tarea eliminada (índice $index).");
    }
  }

  void clearHistory() {
    state = state.copyWith(history: const []);
    log("Todas las tareas del historial han sido eliminadas.");
  }

  void toggleAutoTelemetry() {
    final next = !state.isAutoTelemetryEnabled;
    state = state.copyWith(isAutoTelemetryEnabled: next);
    _telemetryTimer?.cancel();
    if (next) {
      log("Auto-refresco de telemetría: ACTIVADO (cada 2s)");
      refreshTelemetry();
      _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) => refreshTelemetry());
    } else {
      log("Auto-refresco de telemetría: DESACTIVADO");
    }
  }

  Future<void> testGlassesMicSample() async {
    final ip = _resolveIp();
    if (ip == null) {
      log("Sin IP para prueba de micrófono de gafas.");
      return;
    }
    state = state.copyWith(isTestingMic: true);
    log("Capturando muestra de audio desde micrófono PDM de las gafas (/mic_sample, S16LE 16kHz mono)...");
    try {
      final wifiService = ref.read(wifiSyncServiceProvider);
      final bytes = await wifiService.fetchMicSample(ip);
      if (bytes == null || bytes.length < 2) {
        log("No se pudo obtener muestra de micrófono de las gafas.");
        state = state.copyWith(isTestingMic: false);
        return;
      }

      // Interpretación exacta del contrato firmware: int16 little-endian,
      // 16 kHz, mono. Sin remuestreo ni reinterpretación.
      final sampleCount = bytes.length ~/ 2;
      int peak = 0;
      double sumSquares = 0;
      double sum = 0;

      for (int i = 0; i < bytes.length - 1; i += 2) {
        final sample = bytes.buffer.asByteData().getInt16(i, Endian.little);
        final absVal = sample.abs();
        if (absVal > peak) peak = absVal;
        sum += sample;
        sumSquares += sample * sample;
      }

      final meanSquare = sampleCount > 0 ? (sumSquares / sampleCount) : 0.0;
      final rms = meanSquare > 0 ? sqrt(meanSquare) : 0.0;
      final dc = sampleCount > 0 ? (sum / sampleCount) : 0.0;

      final stats = GlassesMicStats(
        sampleCount: sampleCount,
        peakAmplitude: peak,
        rmsLevel: rms,
        dcOffset: dc,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        isTestingMic: false,
        lastMicStats: stats,
        lastMicSampleBytes: bytes,
      );
      final secs = (sampleCount / 16000).toStringAsFixed(2);
      log("🎤 Micrófono Gafas: $sampleCount muestras (~${secs}s @16kHz) | Pico=$peak | RMS=${rms.toStringAsFixed(1)} | Offset DC=${dc.toStringAsFixed(1)}");
    } catch (e) {
      state = state.copyWith(isTestingMic: false);
      log("Error al probar micrófono de gafas: $e");
    }
  }

  /// Reproduce la última muestra de /mic_sample en el altavoz del teléfono.
  /// Envuelve el PCM crudo (S16LE 16 kHz mono) en WAV con cabecera correcta.
  Future<void> playLastMicSample() async {
    final bytes = state.lastMicSampleBytes;
    if (bytes == null || bytes.isEmpty) {
      log("Sin muestra de micrófono para reproducir. Pulsa 'Probar Mic' primero.");
      return;
    }
    final ok = await PhonePlayback().playPcm16(bytes, sampleRate: 16000, channels: 1);
    log(ok ? "🔊 Reproduciendo muestra de micrófono (S16LE 16kHz mono)..." : "Fallo al reproducir la muestra.");
  }

  /// Guarda la última muestra como .wav válido (cabecera 16 kHz mono) y
  /// devuelve la ruta, para depurar con un reproductor externo.
  Future<String?> saveLastMicSampleWav() async {
    final bytes = state.lastMicSampleBytes;
    if (bytes == null || bytes.isEmpty) {
      log("Sin muestra de micrófono para guardar.");
      return null;
    }
    try {
      final wav = WavEncoder.pcm16ToWav(bytes, sampleRate: 16000, channels: 1);
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/mic_gafas_${DateTime.now().millisecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(wav, flush: true);
      log("💾 Muestra guardada: $path (${wav.length} bytes WAV 16kHz mono).");
      return path;
    } catch (e) {
      log("Error guardando WAV: $e");
      return null;
    }
  }

  Future<void> triggerQuickActionWithGlasses({
    required String title,
    required String prompt,
  }) async {
    final ip = _resolveIp();
    final bleState = ref.read(bleServiceProvider);
    final isLinked = bleState.isWifiConnected ||
        bleState.isBleConnected ||
        state.isSimulatorMode;

    log("🚀 Acción Rápida: '$title'");
    if (!isLinked && ip == null) {
      log("⚠️ Gafas no conectadas para capturar fotograma. Conecta las gafas o activa modo Simulador.");
      state = state.copyWith(lastError: "Gafas no conectadas para capturar fotograma.");
      return;
    }

    Uint8List? frame;
    if (ip != null && !state.isSimulatorMode) {
      log("📸 Capturando fotograma de cámara de gafas...");
      final wifiService = ref.read(wifiSyncServiceProvider);
      frame = await wifiService.fetchSnapshot(
        ip,
        preset: "text_screen",
        aeLevel: -2,
      );
      if (frame != null) {
        state = state.copyWith(latestFrame: frame);
        log("✅ Fotograma capturado (${frame.lengthInBytes ~/ 1024} KB). Enviando a IA multimodal...");
      } else {
        log("⚠️ Cámara de gafas no respondió; ejecutando consulta con contexto...");
      }
    }

    await triggerAiQuery(prompt, customImage: frame);
  }

  Future<void> refreshTelemetry() async {
    final ip = _resolveIp();
    if (ip == null) {
      log("Sin IP para telemetría.");
      return;
    }
    final wifiService = ref.read(wifiSyncServiceProvider);
    final tele = await wifiService.fetchTelemetry(ip);
    final ping = await wifiService.checkPingLatency(ip);
    state = state.copyWith(telemetry: tele, pingMs: ping);
    if (tele != null) {
      log("FW ${tele.fwVersion} | Bat=${tele.batteryPct}% | Heap=${tele.freeHeap} | Cam=${tele.cameraOk} | Ping=${ping}ms");
      if (state.isBackgroundModeActive) {
        await BackgroundServiceManager.updateNotification(
          title: 'GlassesPro · Gafas OK (${tele.batteryPct}%)',
          text: 'IP: $ip · FW ${tele.fwVersion} · Listo para consultar',
        );
      }
    } else {
      log("Telemetría no disponible en $ip");
    }
  }

  Future<void> runManualSnapshot() async {
    final ip = _resolveIp();
    if (ip == null && !state.isSimulatorMode) {
      log("Error: las gafas no tienen IP.");
      return;
    }
    log("Capturando JPEG (alta resolución / anti-reflejo) en $ip...");
    final wifiService = ref.read(wifiSyncServiceProvider);
    final frame = await wifiService.fetchSnapshot(
      ip ?? "127.0.0.1",
      preset: "text_screen",
      aeLevel: -2,
    );
    if (frame != null) {
      state = state.copyWith(latestFrame: frame, lastError: '');
      log("Fotograma OK (${frame.lengthInBytes ~/ 1024} KB).");
    } else {
      state = state.copyWith(lastError: 'Fallo de captura');
      log("Fallo al descargar fotograma.");
    }
  }

  Future<void> setCameraPreset(String preset, int aeLevel) async {
    final ip = _resolveIp();
    if (ip == null) {
      log("Conecta las gafas para aplicar ajustes de cámara.");
      return;
    }
    log("Aplicando preset de cámara: $preset (AE=$aeLevel)...");
    final ok = await ref.read(wifiSyncServiceProvider).updateCameraSettings(
      ip,
      preset: preset,
      aeLevel: aeLevel,
    );
    if (ok) {
      log("Preset $preset aplicado correctamente en sensor.");
    } else {
      log("Fallo al aplicar preset de cámara.");
    }
  }

  Future<void> testSpeakerBeep() async {
    final ip = _resolveIp();
    if (ip == null) {
      log("Conecta las gafas antes del autotest.");
      return;
    }
    final ok = await ref.read(wifiSyncServiceProvider).triggerHardwareBeep(ip);
    log(ok ? "Beep I2S enviado." : "Fallo beep.");
  }

  Future<void> runSelfTest() async {
    final ip = _resolveIp();
    if (ip == null) {
      log("Sin IP para self-test.");
      return;
    }
    final data = await ref.read(wifiSyncServiceProvider).runSelfTest(ip);
    log(data == null ? "Self-test falló." : "Self-test: $data");
  }

  Future<void> triggerReboot() async {
    final ip = _resolveIp();
    if (ip == null) return;
    final ok = await ref.read(wifiSyncServiceProvider).rebootDevice(ip);
    log(ok ? "Reinicio enviado." : "No se pudo reiniciar.");
  }

  Future<void> triggerFactoryReset() async {
    final ip = _resolveIp();
    if (ip == null) return;
    final ok = await ref.read(wifiSyncServiceProvider).factoryResetDevice(ip);
    if (ok) {
      log("Factory reset OK. Conéctate a XIAO-Glasses-AP.");
      await ref.read(bleServiceProvider.notifier).forgetDevice();
    } else {
      log("Fallo Factory Reset.");
    }
  }

  Future<void> uploadOtaFirmware() async {
    final ip = _resolveIp();
    if (ip == null) {
      log("Sin IP para OTA.");
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['bin'],
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) {
        log("OTA cancelada.");
        return;
      }
      final bytes = result.files.single.bytes!;
      log("Subiendo firmware (${bytes.lengthInBytes ~/ 1024} KB) a $ip ...");
      final ok = await ref.read(wifiSyncServiceProvider).uploadOtaFirmware(ip, bytes);
      log(ok ? "OTA OK. Las gafas reinician." : "OTA falló. No desconectes; reintenta.");
    } catch (e) {
      log("OTA excepción: $e");
    }
  }

  Future<void> applyCameraSettings({
    required int quality,
    required int brightness,
    required int contrast,
  }) async {
    final ip = _resolveIp();
    ref.read(appConfigProvider.notifier).updateCameraParams(
          quality: quality,
          brightness: brightness,
          contrast: contrast,
        );
    if (ip != null) {
      final success = await ref.read(wifiSyncServiceProvider).updateCameraConfig(
            ip,
            quality: quality,
            brightness: brightness,
            contrast: contrast,
          );
      log(success ? "Cámara Q=$quality B=$brightness C=$contrast" : "No se actualizó la cámara.");
    }
  }

  // --- Calibración y Gestión Biométrica de Voz (Sherpa-ONNX) ---

  Future<void> calibrateTechnicianVoiceSample() async {
    try {
      if (!state.isCalibratingVoice) {
        if (!await _recorder.hasPermission()) {
          log("Permiso de micrófono denegado para calibración.");
          return;
        }
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/voice_calibration_sample.wav';
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
          path: path,
        );
        state = state.copyWith(isCalibratingVoice: true);
        log("🎙️ Calibrando voz: Di 'Gafas activa soporte técnico' durante 3-5 segundos...");
      } else {
        final path = await _recorder.stop();
        state = state.copyWith(isCalibratingVoice: false);
        if (path == null) {
          log("Grabación de calibración vacía.");
          return;
        }
        final file = File(path);
        final bytes = await file.readAsBytes();
        final pcmBytes = bytes.length > 44 ? bytes.sublist(44) : bytes;

        final gatekeeper = ref.read(voiceGatekeeperProvider);
        final updatedProfile = await gatekeeper.enrollTechnicianVoice(pcmBytes);
        log("✅ Perfil biométrico actualizado: ${updatedProfile.sampleCount} muestra(s) enroladas.");
      }
    } catch (e) {
      state = state.copyWith(isCalibratingVoice: false);
      log("Error en calibración de voz: $e");
    }
  }

  Future<void> resetVoiceProfile() async {
    await ref.read(voiceGatekeeperProvider).resetTechnicianVoice();
    log("🗑️ Perfil biométrico de voz reseteado.");
  }

  Future<void> updateVoiceGateConfig(VoiceGateConfig newConfig) async {
    await ref.read(voiceGatekeeperProvider).updateConfig(newConfig);
    log("⚙️ Configuración VoiceGate actualizada.");
  }

  // --- Flujo de dictado de voz con Filtro Edge (Vosk + Sherpa-ONNX) ---

  Future<void> toggleVoiceRecording() async {
    try {
      if (!state.isRecordingVoice) {
        if (!await _recorder.hasPermission()) {
          log("Permiso de micrófono denegado.");
          return;
        }
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/glasses_query.wav';
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
          path: path,
        );
        state = state.copyWith(isRecordingVoice: true);
        log("Grabando consulta de voz...");
      } else {
        final path = await _recorder.stop();
        state = state.copyWith(isRecordingVoice: false);
        if (path == null) {
          log("Grabación vacía.");
          return;
        }

        final file = File(path);
        final bytes = await file.readAsBytes();
        final pcmBytes = bytes.length > 44 ? bytes.sublist(44) : bytes;

        log("Transcribiendo audio...");
        final text = await ref.read(aiServiceProvider).transcribeFile(file);
        final transcribed = text?.trim() ?? '';

        // Evaluación Edge: Sherpa-ONNX Speaker Verification + Vosk Keyword Filter
        final gatekeeper = ref.read(voiceGatekeeperProvider);
        final evaluation = await gatekeeper.evaluateAudioQuery(
          pcmBytes: pcmBytes,
          transcribedText: transcribed,
        );
        state = state.copyWith(lastVoiceEvaluation: evaluation);

        if (evaluation.shouldForwardToServer) {
          log("🛡️ Filtro Edge: ACEPTADO (Similitud Locutor: ${(evaluation.speakerSimilarity * 100).toStringAsFixed(1)}%) -> '${evaluation.promptForServer}'");
          await triggerAiQuery(evaluation.promptForServer);
        } else {
          log("🛡️ Filtro Edge DESCARTÓ el audio: ${evaluation.reasonDescription}");
          if (state.isBackgroundModeActive) {
            await BackgroundServiceManager.updateNotification(
              title: 'GlassesPro · Audio Filtrado',
              text: evaluation.reasonDescription,
            );
          }
        }
      }
    } catch (e) {
      state = state.copyWith(isRecordingVoice: false);
      log("Error de voz: $e");
    }
  }

  Future<void> retryLast() async {
    if (state.history.isEmpty) return;
    await triggerAiQuery(state.history.first.userQuery);
  }

  Future<void> triggerAiQuery(String query, {Uint8List? customImage}) async {
    if (query.trim().isEmpty) return;
    // Guardia anti-reentrada: mic, retry y acciones de lockscreen pueden solaparse.
    if (state.isProcessing) {
      log("Pipeline ocupado: consulta en curso, se ignora re-entrada.");
      return;
    }
    state = state.copyWith(isProcessing: true, lastError: '');
    log("Pipeline IA: '$query'");

    if (state.isBackgroundModeActive) {
      await BackgroundServiceManager.updateNotification(
        title: 'GlassesPro · Procesando...',
        text: 'Analizando fotograma y ejecutando IA...',
      );
    }

    final resolvedIp = _resolveIp();
    final aiService = ref.read(aiServiceProvider);

    Uint8List? imageToSend = customImage;
    if (imageToSend == null && resolvedIp != null && !state.isSimulatorMode) {
      log("📸 Obteniendo fotograma fresco de cámara en $resolvedIp...");
      try {
        final wifiService = ref.read(wifiSyncServiceProvider);
        final freshFrame = await wifiService.fetchSnapshot(resolvedIp);
        if (freshFrame != null && freshFrame.isNotEmpty) {
          imageToSend = freshFrame;
          state = state.copyWith(latestFrame: freshFrame);
          log("✅ Fotograma capturado (${freshFrame.lengthInBytes ~/ 1024} KB).");
        } else {
          log("⚠️ Cámara de gafas no respondió en $resolvedIp (verifica Wi-Fi).");
        }
      } catch (e) {
        log("⚠️ Error en captura de cámara: $e");
      }
    }

    try {
      final llmWatch = Stopwatch()..start();
      final result = await aiService.processMultimodalQuery(
        userPrompt: query,
        glassesIp: state.isSimulatorMode ? null : resolvedIp,
        directImageBytes: imageToSend ?? state.latestFrame,
        useMock: state.isSimulatorMode,
      );
      llmWatch.stop();

      final updatedHistory = List<AiInteractionResult>.from(state.history)..insert(0, result);
      state = state.copyWith(
        history: updatedHistory,
        isProcessing: false,
        lastAiLatencyMs: result.metrics.llmLatencyMs > 0
            ? result.metrics.llmLatencyMs
            : llmWatch.elapsedMilliseconds,
        lastEndpointTested: 'ai/chat',
        lastResponseCode: result.cameraMissing ? 206 : 200,
      );
      log("OK ${result.metrics.totalRoundTripMs} ms"
          "${result.metrics.audioFallbackToPhone ? ' | audio en teléfono' : ''}"
          "${result.cameraMissing ? ' | sin cámara' : ''}");

      if (state.isBackgroundModeActive) {
        final cleanText = result.assistantResponse.replaceAll('\n', ' ').trim();
        final preview = cleanText.length > 70 ? '${cleanText.substring(0, 67)}...' : cleanText;
        await BackgroundServiceManager.updateNotification(
          title: 'GlassesPro · Respuesta IA',
          text: preview.isNotEmpty ? preview : 'Respuesta reproducida por audio',
        );
      }
    } catch (e) {
      log("Excepción pipeline: $e");
      state = state.copyWith(isProcessing: false, lastError: e.toString());
      if (state.isBackgroundModeActive) {
        await BackgroundServiceManager.updateNotification(
          title: 'GlassesPro · Error',
          text: 'Error en pipeline: $e',
        );
      }
    }
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}

final devControllerProvider = StateNotifierProvider<DevController, DevModeState>((ref) {
  return DevController(ref);
});
