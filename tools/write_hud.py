# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(__file__).resolve().parents[1] / "mobile_app" / "lib" / "features" / "developer_mode" / "dev_hud_widget.dart"
p.write_text(r'''import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/config/app_config_provider.dart';
import '../connectivity/ble_service.dart';
import 'dev_controller.dart';

class DevHudWidget extends ConsumerStatefulWidget {
  const DevHudWidget({super.key});

  @override
  ConsumerState<DevHudWidget> createState() => _DevHudWidgetState();
}

class _DevHudWidgetState extends ConsumerState<DevHudWidget> {
  int _quality = 12;
  int _brightness = 1;
  int _contrast = 1;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _workCtrl;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(appConfigProvider);
    _urlCtrl = TextEditingController(text: cfg.apiBaseUrl);
    _keyCtrl = TextEditingController(text: cfg.apiKey);
    _modelCtrl = TextEditingController(text: cfg.modelName);
    _workCtrl = TextEditingController(text: cfg.workOrderId);
    _quality = cfg.cameraJpegQuality;
    _brightness = cfg.cameraBrightness;
    _contrast = cfg.cameraContrast;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _workCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devState = ref.watch(devControllerProvider);
    final bleState = ref.watch(bleServiceProvider);
    final configState = ref.watch(appConfigProvider);
    final devCtrl = ref.read(devControllerProvider.notifier);
    final configCtrl = ref.read(appConfigProvider.notifier);

    return Material(
      color: AppColors.surface,
      elevation: 16,
      child: DefaultTabController(
        length: 6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: AppColors.elevated,
              child: Row(
                children: [
                  const Icon(Icons.monitor_heart_outlined, color: AppColors.accent, size: 18),
                  const SizedBox(width: 8),
                  const Text("DIAGNÓSTICO",
                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.6)),
                  const Spacer(),
                  const Text("Mock", style: TextStyle(color: AppColors.muted, fontSize: 11)),
                  Switch(
                    value: devState.isSimulatorMode,
                    activeColor: AppColors.accent,
                    onChanged: (_) => devCtrl.toggleSimulatorMode(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: AppColors.accent, size: 18),
                    onPressed: () => devCtrl.refreshTelemetry(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.muted, size: 18),
                    onPressed: () => devCtrl.toggleDevMode(),
                  ),
                ],
              ),
            ),
            const TabBar(
              isScrollable: true,
              indicatorColor: AppColors.accent,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.muted,
              labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              tabs: [
                Tab(text: "Latencias"),
                Tab(text: "Cámara"),
                Tab(text: "cURL"),
                Tab(text: "Hardware"),
                Tab(text: "IA"),
                Tab(text: "Logs"),
              ],
            ),
            SizedBox(
              height: 300,
              child: TabBarView(
                children: [
                  _latencies(devState, bleState),
                  _camera(devState, devCtrl),
                  _curl(devState),
                  _hardware(devState, bleState, devCtrl),
                  _config(configState, configCtrl),
                  _logs(devState, devCtrl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _latencies(DevModeState dev, BleState ble) {
    final tele = dev.telemetry;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _badge("Sync", ble.status.name, ble.isWifiConnected ? AppColors.success : AppColors.warning),
            _badge("IP", ble.glassesIp ?? ble.savedProfile.lastKnownIp ?? "—", AppColors.success),
            _badge("Bat", tele != null ? "${tele.batteryPct}%" : "—", AppColors.warning),
            _badge("FW", tele?.fwVersion ?? "—", AppColors.info),
            _badge("Ping", "${dev.pingMs >= 0 ? dev.pingMs : '—'} ms", AppColors.accent),
          ],
        ),
        const SizedBox(height: 12),
        const Text("WATERFALL", style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (dev.history.isNotEmpty) _waterfall(dev.history.first.metrics) else
          const Text("Ejecuta una consulta para ver tiempos.", style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    );
  }

  Widget _waterfall(dynamic metrics) {
    final total = metrics.totalRoundTripMs > 0 ? metrics.totalRoundTripMs : 1;
    return Column(
      children: [
        _bar("Captura JPEG", metrics.cameraCaptureMs, total, AppColors.warning),
        _bar("LLM multimodal", metrics.llmLatencyMs, total, Colors.blueAccent),
        _bar("TTS", metrics.ttsMs, total, Colors.purpleAccent),
        _bar("I2S gafas", metrics.glassesAudioTransferMs, total, AppColors.accent),
        const Divider(color: AppColors.border),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("TOTAL", style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 12)),
            Text("${metrics.totalRoundTripMs} ms",
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
          ],
        ),
        if (metrics.audioFallbackToPhone)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text("Audio reproducido en el teléfono (fallback)", style: TextStyle(color: AppColors.info, fontSize: 11)),
          ),
      ],
    );
  }

  Widget _bar(String label, int ms, int total, Color color) {
    final fraction = (ms / total).clamp(0.04, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              Text("$ms ms", style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.toDouble(),
              minHeight: 6,
              backgroundColor: Colors.white10,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _camera(DevModeState dev, DevController ctrl) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: dev.latestFrame != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(dev.latestFrame!, fit: BoxFit.cover),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Center(
                      child: Text("Sin fotograma", style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ListView(
              children: [
                FilledButton.icon(
                  onPressed: () => ctrl.runManualSnapshot(),
                  icon: const Icon(Icons.camera, size: 16),
                  label: const Text("Capturar"),
                ),
                _slider("JPEG $_quality", _quality.toDouble(), 5, 40, (v) {
                  setState(() => _quality = v.round());
                }, () => ctrl.applyCameraSettings(quality: _quality, brightness: _brightness, contrast: _contrast)),
                _slider("Brillo $_brightness", _brightness.toDouble(), -2, 2, (v) {
                  setState(() => _brightness = v.round());
                }, () => ctrl.applyCameraSettings(quality: _quality, brightness: _brightness, contrast: _contrast)),
                _slider("Contraste $_contrast", _contrast.toDouble(), -2, 2, (v) {
                  setState(() => _contrast = v.round());
                }, () => ctrl.applyCameraSettings(quality: _quality, brightness: _brightness, contrast: _contrast)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged, VoidCallback onCommit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).round() == 0 ? null : (max - min).round(),
          activeColor: AppColors.accent,
          onChanged: onChanged,
          onChangeEnd: (_) => onCommit(),
        ),
      ],
    );
  }

  Widget _curl(DevModeState dev) {
    if (dev.history.isEmpty) {
      return const Center(child: Text("Sin peticiones.", style: TextStyle(color: AppColors.muted)));
    }
    final latest = dev.history.first;
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Row(
          children: [
            const Text("cURL", style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, color: AppColors.accent, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: latest.generatedCurl));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("cURL copiado")));
              },
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.black,
          child: Text(latest.generatedCurl,
              style: const TextStyle(color: AppColors.success, fontFamily: 'monospace', fontSize: 10)),
        ),
        const SizedBox(height: 8),
        const Text("JSON", style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.black,
          child: Text(
            const JsonEncoder.withIndent('  ').convert(latest.rawResponsePayload),
            style: const TextStyle(color: AppColors.warning, fontFamily: 'monospace', fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _hardware(DevModeState dev, BleState ble, DevController ctrl) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilledButton.tonal(onPressed: ctrl.testSpeakerBeep, child: const Text("Beep")),
            FilledButton.tonal(onPressed: ctrl.runSelfTest, child: const Text("Self-test")),
            FilledButton.tonal(onPressed: ctrl.triggerReboot, child: const Text("Reboot")),
            FilledButton.tonal(onPressed: ctrl.uploadOtaFirmware, child: const Text("OTA .bin")),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => _confirmReset(ctrl),
              child: const Text("Reset NVS"),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _row("Watchdog", "10 s auto-recovery"),
        _row("Red", ble.isWifiConnected ? "STA + SoftAP" : "SoftAP 192.168.4.1"),
        _row("Cámara", dev.telemetry?.cameraOk == false ? "Fallo" : "Mutex + retry"),
        _row("Dispositivo", ble.savedProfile.deviceName ?? "—"),
        _row("SSID", ble.savedProfile.savedSsid ?? "—"),
        const Divider(color: AppColors.border),
        _row("CAM FPC", "OV2640/OV3660"),
        _row("MIC PDM", "GPIO 41 / 42"),
        _row("I2S MAX98357A", "BCLK7 LRCK8 DIN9"),
        _row("BAT ADC", "GPIO 1 (A0)"),
      ],
    );
  }

  void _confirmReset(DevController ctrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("¿Factory reset?", style: TextStyle(color: AppColors.text)),
        content: const Text("Borra el Wi-Fi de NVS y vuelve al SoftAP 192.168.4.1.",
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.pop(ctx);
              ctrl.triggerFactoryReset();
            },
            child: const Text("Confirmar"),
          ),
        ],
      ),
    );
  }

  Widget _config(AppConfigState config, AppConfigNotifier notifier) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(controller: _urlCtrl, decoration: const InputDecoration(labelText: "Base URL"), onSubmitted: (v) => notifier.updateApiSettings(baseUrl: v)),
        TextField(controller: _keyCtrl, obscureText: true, decoration: const InputDecoration(labelText: "API Key"), onSubmitted: (v) => notifier.updateApiSettings(apiKey: v)),
        TextField(controller: _modelCtrl, decoration: const InputDecoration(labelText: "Modelo"), onSubmitted: (v) => notifier.updateApiSettings(model: v)),
        TextField(controller: _workCtrl, decoration: const InputDecoration(labelText: "Orden de trabajo"), onSubmitted: notifier.updateWorkOrder),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => notifier.updateApiSettings(
            baseUrl: _urlCtrl.text,
            apiKey: _keyCtrl.text,
            model: _modelCtrl.text,
          ),
          child: const Text("Guardar endpoint"),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text("TTS", style: TextStyle(color: AppColors.text, fontSize: 13)),
          value: config.enableTtsPlayback,
          onChanged: notifier.toggleTtsPlayback,
        ),
      ],
    );
  }

  Widget _logs(DevModeState dev, DevController ctrl) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: ctrl.clearLogs, child: const Text("Limpiar")),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            color: Colors.black,
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              reverse: true,
              child: Text(dev.consoleLog,
                  style: const TextStyle(color: AppColors.success, fontFamily: 'monospace', fontSize: 10)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _badge(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 9)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          Flexible(
            child: Text(v,
                textAlign: TextAlign.end,
                style: const TextStyle(color: AppColors.text, fontFamily: 'monospace', fontSize: 10)),
          ),
        ],
      ),
    );
  }
}
'''.replace('\r\n', '\n'), encoding='utf-8')
print('wrote dev_hud_widget.dart')
