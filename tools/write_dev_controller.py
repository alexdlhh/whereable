# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(__file__).resolve().parents[1] / "mobile_app" / "lib" / "features" / "developer_mode" / "dev_controller.dart"
p.write_text(r'''import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../ai_assistant/models/ai_response_model.dart';
import '../ai_assistant/ai_service.dart';
import '../connectivity/ble_service.dart';
import '../connectivity/wifi_sync_service.dart';
import '../../core/config/app_config_provider.dart';

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
  final String lastError;

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
    this.lastError = '',
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
    String? lastError,
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
      lastError: lastError ?? this.lastError,
    );
  }
}

class DevController extends StateNotifier<DevModeState> {
  DevController(this.ref) : super(DevModeState());

  final Ref ref;
  final AudioRecorder _recorder = AudioRecorder();

  String? _resolveIp() {
    final bleState = ref.read(bleServiceProvider);
    return bleState.glassesIp ??
        bleState.savedProfile.lastKnownIp ??
        (state.isSimulatorMode ? "192.168.4.1" : null);
  }

  void toggleDevMode() {
    state = state.copyWith(isDevModeEnabled: !state.isDevModeEnabled);
    log("Modo diagnóstico: ${state.isDevModeEnabled ? 'ON' : 'OFF'}");
  }

  void toggleSimulatorMode() {
    state = state.copyWith(isSimulatorMode: !state.isSimulatorMode);
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

  void clearHistory() {
    state = state.copyWith(history: const []);
    log("Historial de sesión limpiado.");
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
    log("Capturando JPEG en $ip...");
    final wifiService = ref.read(wifiSyncServiceProvider);
    final frame = await wifiService.fetchSnapshot(ip ?? "127.0.0.1");
    if (frame != null) {
      state = state.copyWith(latestFrame: frame, lastError: '');
      log("Fotograma OK (${frame.lengthInBytes ~/ 1024} KB).");
    } else {
      state = state.copyWith(lastError: 'Fallo de captura');
      log("Fallo al descargar fotograma.");
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
        log("Transcribiendo audio...");
        final text = await ref.read(aiServiceProvider).transcribeFile(File(path));
        if (text != null && text.trim().isNotEmpty) {
          await triggerAiQuery(text.trim());
        } else {
          await triggerAiQuery("Analiza lo que estoy viendo y dime el siguiente paso seguro.");
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
    state = state.copyWith(isProcessing: true, lastError: '');
    log("Pipeline IA: '$query'");

    final bleState = ref.read(bleServiceProvider);
    final aiService = ref.read(aiServiceProvider);

    try {
      final result = await aiService.processMultimodalQuery(
        userPrompt: query,
        glassesIp: state.isSimulatorMode ? null : bleState.glassesIp,
        directImageBytes: customImage ?? state.latestFrame,
        useMock: state.isSimulatorMode,
      );

      final updatedHistory = List<AiInteractionResult>.from(state.history)..insert(0, result);
      state = state.copyWith(history: updatedHistory, isProcessing: false);
      log("OK ${result.metrics.totalRoundTripMs} ms"
          "${result.metrics.audioFallbackToPhone ? ' | audio en teléfono' : ''}"
          "${result.cameraMissing ? ' | sin cámara' : ''}");
    } catch (e) {
      log("Excepción pipeline: $e");
      state = state.copyWith(isProcessing: false, lastError: e.toString());
    }
  }
}

final devControllerProvider = StateNotifierProvider<DevController, DevModeState>((ref) {
  return DevController(ref);
});
'''.replace('\r\n', '\n'), encoding='utf-8')
print('wrote dev_controller.dart')
