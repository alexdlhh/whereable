import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../core/theme/app_theme.dart';
import '../connectivity/ble_service.dart';
import '../connectivity/device_discovery_sheet.dart';
import '../developer_mode/dev_controller.dart';
import '../developer_mode/dev_hud_widget.dart';
import '../ai_assistant/models/ai_response_model.dart';
import '../diagnostics/device_test_dialog.dart';

class AssistantView extends ConsumerStatefulWidget {
  const AssistantView({super.key});

  @override
  ConsumerState<AssistantView> createState() => _AssistantViewState();
}

class _AssistantViewState extends ConsumerState<AssistantView> {
  final TextEditingController _textController = TextEditingController();

  static const _actions = [
    (
      Icons.search,
      "Identificar",
      "Identifica el componente o producto que estoy viendo. Nombra marcas, códigos y función.",
      "Captura la imagen de las gafas e identifica componentes, marcas y conectores."
    ),
    (
      Icons.troubleshoot,
      "Diagnosticar",
      "¿Detectas fallo, quemadura, conector suelto o desgaste? Indica riesgo y siguiente medición.",
      "Analiza el fotograma de las gafas buscando averías, sobrecalentamiento o pistas rotas."
    ),
    (
      Icons.format_list_numbered,
      "Procedimiento",
      "Guíame paso a paso para desmontarlo con seguridad, sin forzar flex ni clips.",
      "Genera instrucciones paso a paso para la pieza enfocada por la cámara."
    ),
    (
      Icons.qr_code_2,
      "Nº de serie",
      "Lee número de serie, placa y especificaciones visibles. Si no se lee, dime cómo enfocar.",
      "Lectura OCR directa de etiquetas, códigos QR y serigrafías en la visión."
    ),
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
            if (devState.lastError.isNotEmpty)
              _buildErrorBanner(context, devState, devCtrl),
            if (!devState.isDevModeEnabled) _buildQuickActions(context, bleState, devState, devCtrl),
            if (devState.history.isNotEmpty && !devState.isDevModeEnabled)
              _buildHistoryHeader(context, devState.history.length, devCtrl),
            if (!devState.isDevModeEnabled)
              Expanded(
                child: devState.history.isEmpty
                    ? _buildEmptyState(devCtrl)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                        itemCount: devState.history.length,
                        itemBuilder: (context, index) {
                          final item = devState.history[index];
                          return _buildInteractionCard(item, devState.latestFrame, devCtrl, index);
                        },
                      ),
              ),
            if (!devState.isDevModeEnabled) _buildInputSection(devCtrl, devState),
            if (devState.isDevModeEnabled) const Expanded(child: DevHudWidget()),
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
            child: Tooltip(
              message: "${devState.telemetry!.batteryVoltage.toStringAsFixed(2)} V · FW ${devState.telemetry!.fwVersion}",
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
          ),
        // Canal activo + RSSI persistente: BLE / Wi-Fi / SoftAP / Offline
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: _ChannelRssiChip(bleState, devState),
        ),
        IconButton(
          tooltip: "Emparejar gafas",
          icon: Icon(linked ? Icons.bluetooth_connected : Icons.bluetooth_searching,
              color: linked ? AppColors.success : AppColors.muted),
          onPressed: () => _showPairingDialog(context, bleCtrl),
        ),
        IconButton(
          tooltip: "Test Integral (Foto, Mic, Altavoz y WhatsApp)",
          icon: const Icon(Icons.health_and_safety_outlined, color: AppColors.accent),
          onPressed: () => DeviceTestDialog.show(context),
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
    } else if (ble.isWifiConnected) {
      bg = const Color(0xFF10241A);
      fg = AppColors.success;
      icon = Icons.check_circle_outline;
      final bgInfo = dev.isBackgroundModeActive ? " · 🔒 Bloqueo OK" : "";
      text = "Enlace OK (Cámara + Audio) · ${ble.glassesIp ?? '192.168.4.1'}$bgInfo";
    } else if (ble.isBleConnected) {
      bg = const Color(0xFF1A2634);
      fg = Colors.lightBlueAccent;
      icon = Icons.bluetooth_connected;
      text = "BLE Conectado · Wi-Fi pendiente (toca para enviar Wi-Fi)";
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 8),
            Expanded(
              // Solo el texto es tappable para reconectar: evita que el botón
              // interior "Test Gafas" burbujee al handler exterior.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ble.savedProfile.deviceId != null
                    ? ref.read(bleServiceProvider.notifier).autoConnectGlasses()
                    : _showPairingDialog(context, ref.read(bleServiceProvider.notifier)),
                child: Text(text,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
            ),
            if (dev.isProcessing)
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
            else if (ble.isWifiConnected || ble.isBleConnected || dev.isSimulatorMode)
              GestureDetector(
                onTap: () => DeviceTestDialog.show(context),
                child: Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.accent.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fact_check_outlined, size: 12, color: AppColors.accent),
                      SizedBox(width: 4),
                      Text("Test Gafas",
                          style: TextStyle(
                              color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(
    BuildContext context,
    BleState bleState,
    DevModeState devState,
    DevController devCtrl,
  ) {
    final isLinked = bleState.isWifiConnected || bleState.isBleConnected || devState.isSimulatorMode;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on, size: 14, color: AppColors.accent),
              const SizedBox(width: 4),
              const Text(
                "ACCIONES RÁPIDAS (INPUT GAFAS)",
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.help_outline, size: 14, color: AppColors.muted),
                tooltip: "¿Cómo funcionan las acciones rápidas?",
                onPressed: () => _showQuickActionHelp(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView.separated(
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
                  onPressed: devState.isProcessing
                      ? null
                      : () {
                          if (!isLinked) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                    "⚠️ Conecta las gafas por Wi-Fi/Bluetooth para capturar fotograma o activa el Simulador."),
                                action: SnackBarAction(
                                  label: "Emparejar",
                                  onPressed: () => _showPairingDialog(
                                      context, ref.read(bleServiceProvider.notifier)),
                                ),
                              ),
                            );
                            return;
                          }
                          devCtrl.triggerQuickActionWithGlasses(title: a.$2, prompt: a.$3);
                        },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader(BuildContext context, int count, DevController devCtrl) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Historial de tareas ($count)",
            style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            ),
            icon: const Icon(Icons.delete_sweep_outlined, size: 14, color: AppColors.muted),
            label: const Text("Borrar todo", style: TextStyle(fontSize: 11, color: AppColors.muted)),
            onPressed: () => _confirmClearAllHistory(context, devCtrl),
          ),
        ],
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
              "Mira un componente con las gafas y pulsa una de las acciones rápidas para capturar fotograma e iniciar el diagnóstico. También puedes dictar con tu voz o escribir abajo.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractionCard(
    AiInteractionResult item,
    Uint8List? frame,
    DevController devCtrl,
    int index,
  ) {
    final dateStr =
        "${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}";
    return Dismissible(
      key: ValueKey("task_${item.timestamp.microsecondsSinceEpoch}_${item.hashCode}_$index"),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text("Eliminar", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            SizedBox(width: 8),
            Icon(Icons.delete_outline, color: Colors.white, size: 20),
          ],
        ),
      ),
      onDismissed: (_) {
        devCtrl.deleteHistoryItem(index);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Tarea eliminada")),
        );
      },
      child: Card(
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
                  if (item.usedMock) ...[
                    const SizedBox(width: 6),
                    const Chip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Color(0xFF2E2414),
                      label: Text("Simulador", style: TextStyle(fontSize: 10, color: AppColors.warning)),
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
                  IconButton(
                    tooltip: "Eliminar tarea",
                    icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
                    onPressed: () {
                      devCtrl.deleteHistoryItem(index);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Tarea eliminada")),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
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
                      final text = _textController.text.trim();
                      if (text.isNotEmpty) {
                        devCtrl.triggerAiQuery(text);
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
    DeviceDiscoverySheet.show(context);
  }

  Widget _buildErrorBanner(BuildContext context, DevModeState devState, DevController devCtrl) {
    return Material(
      color: const Color(0xFF2A1414),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 15, color: AppColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                devState.lastError,
                style: const TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => devCtrl.retryLast(),
              child: const Text("Reintentar", style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickActionHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: AppColors.accent, size: 20),
            SizedBox(width: 8),
            Text("Acciones Rápidas con Gafas", style: TextStyle(color: AppColors.text, fontSize: 16)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "¿Cómo funcionan?",
                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13),
              ),
              SizedBox(height: 6),
              Text(
                "1. Miras el objeto o componente que necesitas analizar.\n"
                "2. Pulsas la acción rápida correspondiente.\n"
                "3. La app captura el fotograma directamente de la cámara de las gafas (input visual).\n"
                "4. El modelo de IA multimodal analiza la imagen y genera el diagnóstico técnico en milisegundos.\n"
                "5. La respuesta se reproduce por el altavoz de las gafas y se muestra en pantalla.",
                style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
              ),
              SizedBox(height: 12),
              Text(
                "Acciones disponibles:",
                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13),
              ),
              SizedBox(height: 6),
              Text("• Identificar: Detecta modelo, marca, componentes y función.",
                  style: TextStyle(color: AppColors.text, fontSize: 12)),
              SizedBox(height: 4),
              Text("• Diagnosticar: Busca sobrecalentamiento, cortos y daños.",
                  style: TextStyle(color: AppColors.text, fontSize: 12)),
              SizedBox(height: 4),
              Text("• Procedimiento: Pasos seguros para desmontar y medir.",
                  style: TextStyle(color: AppColors.text, fontSize: 12)),
              SizedBox(height: 4),
              Text("• Nº de serie: Lectura de placas, códigos QR y etiquetas.",
                  style: TextStyle(color: AppColors.text, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Entendido"),
          ),
        ],
      ),
    );
  }

  void _confirmClearAllHistory(BuildContext context, DevController devCtrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("¿Borrar todo el historial?", style: TextStyle(color: AppColors.text, fontSize: 16)),
        content: const Text(
          "Se eliminarán todas las tareas y consultas registradas en esta sesión de trabajo.",
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.pop(ctx);
              devCtrl.clearHistory();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Historial de tareas borrado")),
              );
            },
            child: const Text("Borrar todo"),
          ),
        ],
      ),
    );
  }
}

/// Chip persistente de canal activo + RSSI en el AppBar.
/// Muestra BLE / Wi-Fi / SoftAP / Offline con color semántico.
class _ChannelRssiChip extends StatelessWidget {
  final BleState ble;
  final DevModeState dev;
  const _ChannelRssiChip(this.ble, this.dev);

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    IconData icon;
    String tooltip;
    if (dev.isSimulatorMode) {
      label = "SIM";
      color = AppColors.warning;
      icon = Icons.developer_mode;
      tooltip = "Modo simulador (sin hardware)";
    } else if (ble.isWifiConnected) {
      final rssi = dev.telemetry?.rssi ?? ble.rssi ?? 0;
      final ip = ble.glassesIp ?? '';
      final isAp = ip.startsWith('192.168.4.') || ip == '192.168.4.1';
      label = "${isAp ? 'AP' : 'Wi-Fi'} ${rssi != 0 ? '$rssi dBm' : ''}".trim();
      color = rssi == 0 || rssi > -70 ? AppColors.success : AppColors.warning;
      icon = Icons.wifi;
      tooltip = "Canal: ${isAp ? 'SoftAP' : 'Wi-Fi STA'} · IP ${ble.glassesIp ?? '—'}";
    } else if (ble.isBleConnected) {
      label = "BLE";
      color = Colors.lightBlueAccent;
      icon = Icons.bluetooth_connected;
      tooltip = "Solo BLE: Wi-Fi pendiente de aprovisionar";
    } else {
      label = "Offline";
      color = AppColors.danger;
      icon = Icons.link_off;
      tooltip = "Sin enlace: toca para emparejar";
    }
    return Tooltip(
      message: tooltip,
      child: Chip(
        visualDensity: VisualDensity.compact,
        backgroundColor: AppColors.surfaceAlt,
        avatar: Icon(icon, size: 13, color: color),
        label: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
        side: BorderSide(color: color.withOpacity(0.35)),
      ),
    );
  }
}
