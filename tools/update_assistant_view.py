from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
view = ROOT / "mobile_app" / "lib" / "features" / "assistant_screen" / "assistant_view.dart"

view.write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
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
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  void _onReceiveTaskData(Object data) {
    if (data is Map<String, dynamic>) {
      if (data['type'] == 'action' && data['action'] is String) {
        ref.read(devControllerProvider.notifier).handleBackgroundAction(data['action'] as String);
      }
    }
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleServiceProvider);
    final devState = ref.watch(devControllerProvider);
    final bleCtrl = ref.read(bleServiceProvider.notifier);
    final devCtrl = ref.read(devControllerProvider.notifier);

    return WithForegroundTask(
      child: Scaffold(
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
        IconButton(
          tooltip: devState.isBackgroundModeActive
              ? "Modo Pantalla Bloqueada ACTIVO (toca para apagar)"
              : "Activar modo Pantalla Bloqueada (bolsillo/notificación)",
          icon: Icon(
            devState.isBackgroundModeActive ? Icons.screen_lock_portrait : Icons.screen_lock_portrait_outlined,
            color: devState.isBackgroundModeActive ? AppColors.accent : AppColors.muted,
          ),
          onPressed: () => devCtrl.toggleBackgroundMode(),
        ),
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
      final bgInfo = dev.isBackgroundModeActive ? " · 🔒 Bloqueo OK" : "";
      text = "Enlace OK  ·  ${ble.glassesIp ?? ble.savedProfile.lastKnownIp ?? '192.168.4.1'}$bgInfo";
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
            backgroundColor: AppColors.surfaceAlt,
            side: const BorderSide(color: AppColors.border),
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
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.engineering_outlined, size: 48, color: AppColors.accent),
            ),
            const SizedBox(height: 16),
            const Text(
              "Listo para el trabajo de campo",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text),
            ),
            const SizedBox(height: 8),
            const Text(
              "Mira un componente y pulsa un atajo superior, escribe tu consulta o activa el modo Pantalla Bloqueada para operar con el móvil en el bolsillo.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractionCard(AiInteractionResult item, Uint8List? frame, DevController devCtrl) {
    final dateStr = "${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}";
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.surface,
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
                const Icon(Icons.person_pin, size: 16, color: AppColors.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(item.userQuery,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text)),
                ),
                Text(dateStr, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              item.assistantResponse,
              style: const TextStyle(fontSize: 13, color: AppColors.text, height: 1.45),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppColors.elevated,
                  label: Text("${item.metrics.totalRoundTripMs} ms",
                      style: const TextStyle(fontSize: 10, color: AppColors.accent, fontWeight: FontWeight.w600)),
                ),
                if (item.metrics.audioFallbackToPhone) ...[
                  const SizedBox(width: 6),
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Color(0xFF1E2836),
                    label: Text("Audio móvil", style: TextStyle(fontSize: 10, color: AppColors.info)),
                  ),
                ],
                const Spacer(),
                IconButton(
                  tooltip: "Copiar respuesta",
                  icon: const Icon(Icons.copy, size: 16, color: AppColors.muted),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.assistantResponse));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Respuesta copiada")));
                  },
                ),
                IconButton(
                  tooltip: "Repetir",
                  icon: const Icon(Icons.replay, size: 16, color: AppColors.muted),
                  onPressed: () => devCtrl.triggerAiQuery(item.userQuery),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection(DevController devCtrl, DevModeState devState) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              tooltip: devState.isRecordingVoice ? "Detener dictado" : "Dictar consulta",
              icon: Icon(
                devState.isRecordingVoice ? Icons.stop_circle : Icons.mic,
                color: devState.isRecordingVoice ? AppColors.danger : AppColors.accent,
              ),
              onPressed: () => devCtrl.toggleVoiceRecording(),
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: "Escribe consulta técnica...",
                  hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    devCtrl.triggerAiQuery(val.trim());
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
                    border: Border.all(color: AppColors.accent.withOpacity(0.35)),
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
                const Divider(height: 24, color: AppColors.border),
              ],
              const Text("Aprovisionar Wi-Fi por BLE:",
                  style: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: ssidCtrl,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                decoration: const InputDecoration(labelText: "SSID Wi-Fi", isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passCtrl,
                obscureText: true,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                decoration: const InputDecoration(labelText: "Contraseña", isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          FilledButton(
            onPressed: () {
              if (ssidCtrl.text.isNotEmpty) {
                bleCtrl.sendWifiCredentials(ssidCtrl.text.trim(), passCtrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text("Enviar"),
          ),
        ],
      ),
    );
  }
}
''', encoding='utf-8')
print('assistant_view updated')
