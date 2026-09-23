# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(__file__).resolve().parents[1] / "mobile_app" / "lib" / "features" / "assistant_screen" / "assistant_view.dart"
p.write_text(r'''import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../connectivity/ble_service.dart';
import '../developer_mode/dev_controller.dart';
import '../developer_mode/dev_hud_widget.dart';
import '../ai_assistant/models/ai_response_model.dart';

class AssistantView extends ConsumerStatefulWidget {
  const AssistantView({super.key});

  @override
  ConsumerState<AssistantView> createState() => _AssistantViewState();
}

class _AssistantViewState extends ConsumerState<AssistantView> {
  final TextEditingController _textController = TextEditingController();

  static const _actions = [
    (Icons.search, "Identificar", "Identifica el componente o producto que estoy viendo. Nombra marcas, códigos y función."),
    (Icons.troubleshoot, "Diagnosticar", "¿Detectas fallo, quemadura, conector suelto o desgaste? Indica riesgo y siguiente medición."),
    (Icons.format_list_numbered, "Procedimiento", "Guíame paso a paso para desmontarlo con seguridad, sin forzar flex ni clips."),
    (Icons.qr_code_2, "Nº de serie", "Lee número de serie, placa y especificaciones visibles. Si no se lee, dime cómo enfocar."),
  ];

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleServiceProvider);
    final devState = ref.watch(devControllerProvider);
    final bleCtrl = ref.read(bleServiceProvider.notifier);
    final devCtrl = ref.read(devControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(bleState, devState, bleCtrl, devCtrl),
      body: Column(
        children: [
          _buildConnectionBanner(bleState, devState),
          if (!devState.isDevModeEnabled) _buildQuickActions(devCtrl, devState.isProcessing),
          Expanded(
            child: devState.history.isEmpty
                ? _buildEmptyState(devCtrl)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    itemCount: devState.history.length,
                    itemBuilder: (context, index) {
                      final item = devState.history[index];
                      return _buildInteractionCard(item, devState.latestFrame, devCtrl);
                    },
                  ),
          ),
          if (!devState.isDevModeEnabled) _buildInputSection(devCtrl, devState),
          if (devState.isDevModeEnabled) const DevHudWidget(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BleState bleState,
    DevModeState devState,
    BleService bleCtrl,
    DevController devCtrl,
  ) {
    final linked = bleState.isBleConnected || bleState.isWifiConnected || devState.isSimulatorMode;
    return AppBar(
      titleSpacing: 12,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.visibility_outlined, color: AppColors.accent, size: 18),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("GlassesPro", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
              Text("Soporte técnico de campo", style: TextStyle(fontSize: 10, color: AppColors.muted)),
            ],
          ),
        ],
      ),
      actions: [
        if (devState.telemetry != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.surfaceAlt,
              avatar: Icon(
                Icons.battery_std,
                size: 14,
                color: devState.telemetry!.batteryPct > 20 ? AppColors.success : AppColors.danger,
              ),
              label: Text("${devState.telemetry!.batteryPct}%",
                  style: const TextStyle(fontSize: 11, color: AppColors.text)),
            ),
          ),
        IconButton(
          tooltip: "Emparejar gafas",
          icon: Icon(linked ? Icons.bluetooth_connected : Icons.bluetooth_searching,
              color: linked ? AppColors.success : AppColors.muted),
          onPressed: () => _showPairingDialog(context, bleCtrl),
        ),
        IconButton(
          tooltip: "Diagnóstico",
          icon: Icon(Icons.monitor_heart_outlined,
              color: devState.isDevModeEnabled ? AppColors.accent : AppColors.muted),
          onPressed: () => devCtrl.toggleDevMode(),
        ),
      ],
    );
  }

  Widget _buildConnectionBanner(BleState ble, DevModeState dev) {
    late Color bg;
    late Color fg;
    late IconData icon;
    late String text;

    if (dev.isSimulatorMode) {
      bg = const Color(0xFF2A2412);
      fg = AppColors.warning;
      icon = Icons.developer_mode;
      text = "Simulador activo — sin hardware ni backend";
    } else if (ble.status == SyncStatus.probingSavedIp) {
      bg = const Color(0xFF102033);
      fg = AppColors.info;
      icon = Icons.sync;
      text = "Buscando gafas (${ble.savedProfile.lastKnownIp ?? 'glasses.local'})";
    } else if (ble.status == SyncStatus.scanningBle) {
      bg = const Color(0xFF1A1230);
      fg = Colors.purpleAccent;
      icon = Icons.bluetooth_searching;
      text = "Escaneando Bluetooth...";
    } else if (ble.isWifiConnected || ble.isBleConnected) {
      bg = const Color(0xFF10241A);
      fg = AppColors.success;
      icon = Icons.check_circle_outline;
      text = "Enlace OK  ·  ${ble.glassesIp ?? ble.savedProfile.lastKnownIp ?? '192.168.4.1'}";
    } else {
      bg = const Color(0xFF2A1414);
      fg = AppColors.danger;
      icon = Icons.link_off;
      text = ble.savedProfile.deviceId != null
          ? "Desconectadas — toca para reconectar"
          : "Sin gafas — toca para emparejar";
    }

    return Material(
      color: bg,
      child: InkWell(
        onTap: () => ble.savedProfile.deviceId != null
            ? ref.read(bleServiceProvider.notifier).autoConnectGlasses()
            : _showPairingDialog(context, ref.read(bleServiceProvider.notifier)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              if (dev.isProcessing)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(DevController devCtrl, bool busy) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        scrollDirection: Axis.horizontal,
        itemCount: _actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final a = _actions[i];
          return ActionChip(
            avatar: Icon(a.$1, size: 16, color: AppColors.accent),
            label: Text(a.$2, style: const TextStyle(color: AppColors.text, fontSize: 12)),
            onPressed: busy ? null : () => devCtrl.triggerAiQuery(a.$3),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(DevController devCtrl) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(color: AppColors.accentDim, shape: BoxShape.circle),
              child: const Icon(Icons.handyman_outlined, size: 44, color: AppColors.accent),
            ),
            const SizedBox(height: 18),
            const Text("Listo para el trabajo de campo",
                style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              "Mira la pieza, pulsa un atajo o dicta la consulta.\nLa captura de las gafas se envía al modelo multimodal.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => devCtrl.triggerAiQuery(_actions.first.$3),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text("Consulta de identificación"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractionCard(AiInteractionResult item, Uint8List? frame, DevController devCtrl) {
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: AppColors.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(item.userQuery,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                Text(
                  "${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}",
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(item.assistantResponse,
                style: const TextStyle(color: Color(0xFFD5DCE4), fontSize: 13, height: 1.45)),
            const SizedBox(height: 10),
            Row(
              children: [
                _metaChip(Icons.timer_outlined, "${item.metrics.totalRoundTripMs} ms", AppColors.success),
                if (item.usedMock) ...[
                  const SizedBox(width: 6),
                  _metaChip(Icons.science_outlined, "Sim", AppColors.warning),
                ],
                if (item.metrics.audioFallbackToPhone) ...[
                  const SizedBox(width: 6),
                  _metaChip(Icons.phone_android, "Audio móvil", AppColors.info),
                ],
                if (item.cameraMissing) ...[
                  const SizedBox(width: 6),
                  _metaChip(Icons.videocam_off, "Sin foto", AppColors.danger),
                ],
                const Spacer(),
                IconButton(
                  tooltip: "Copiar respuesta",
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 16, color: AppColors.muted),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.assistantResponse));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Respuesta copiada")),
                    );
                  },
                ),
                IconButton(
                  tooltip: "Repetir",
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 16, color: AppColors.accent),
                  onPressed: () => devCtrl.triggerAiQuery(item.userQuery),
                ),
                if (frame != null)
                  GestureDetector(
                    onTap: () => _showImagePreviewModal(context, frame),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(frame, width: 28, height: 28, fit: BoxFit.cover),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildInputSection(DevController devCtrl, DevModeState devState) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => devCtrl.toggleVoiceRecording(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: devState.isRecordingVoice ? AppColors.danger : AppColors.accentDim,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  devState.isRecordingVoice ? Icons.stop : Icons.mic_none,
                  color: devState.isRecordingVoice ? Colors.white : AppColors.accent,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _textController,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: "Describe lo que ves o pide el siguiente paso",
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty && !devState.isProcessing) {
                    devCtrl.triggerAiQuery(value);
                    _textController.clear();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: devState.isProcessing
                  ? null
                  : () {
                      if (_textController.text.isNotEmpty) {
                        devCtrl.triggerAiQuery(_textController.text);
                        _textController.clear();
                      }
                    },
              icon: const Icon(Icons.arrow_upward, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePreviewModal(BuildContext context, Uint8List frame) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(frame, fit: BoxFit.contain),
            ),
            const SizedBox(height: 10),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar")),
          ],
        ),
      ),
    );
  }

  void _showPairingDialog(BuildContext context, BleService bleCtrl) {
    final bleState = ref.read(bleServiceProvider);
    final ssidCtrl = TextEditingController(text: bleState.savedProfile.savedSsid ?? "");
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Sincronizar gafas", style: TextStyle(color: AppColors.text, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bleState.savedProfile.deviceId != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bleState.savedProfile.deviceName ?? "XIAO-SmartGlasses",
                          style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                      Text("ID ${bleState.savedProfile.deviceId}",
                          style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      Text("IP ${bleState.savedProfile.lastKnownIp ?? '—'}",
                          style: const TextStyle(color: AppColors.success, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          bleCtrl.forgetDevice();
                          Navigator.pop(ctx);
                        },
                        child: const Text("Olvidar"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          bleCtrl.autoConnectGlasses();
                          Navigator.pop(ctx);
                        },
                        child: const Text("Reconectar"),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22),
              ],
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
                onPressed: () => bleCtrl.startScanAndConnect(),
                child: const Text("Buscar por Bluetooth"),
              ),
              const SizedBox(height: 12),
              const Text("Aprovisionar Wi-Fi", style: TextStyle(color: AppColors.muted, fontSize: 12)),
              TextField(controller: ssidCtrl, decoration: const InputDecoration(labelText: "SSID")),
              TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Contraseña")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar")),
          FilledButton(
            onPressed: () {
              bleCtrl.sendWifiCredentials(ssidCtrl.text, passCtrl.text);
              Navigator.pop(ctx);
            },
            child: const Text("Enviar"),
          ),
        ],
      ),
    );
  }
}
'''.replace('\r\n', '\n'), encoding='utf-8')
print('wrote assistant_view.dart')
