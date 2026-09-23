import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../connectivity/ble_service.dart';
import '../developer_mode/dev_controller.dart';
import 'device_self_test_service.dart';

class DeviceTestDialog extends ConsumerStatefulWidget {
  final String? ipAddress;
  final String? deviceName;
  final bool autoRun;

  const DeviceTestDialog({
    super.key,
    this.ipAddress,
    this.deviceName,
    this.autoRun = true,
  });

  static Future<DeviceSelfTestReport?> show(
    BuildContext context, {
    String? ipAddress,
    String? deviceName,
    bool autoRun = true,
  }) {
    return showModalBottomSheet<DeviceSelfTestReport>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DeviceTestDialog(
        ipAddress: ipAddress,
        deviceName: deviceName,
        autoRun: autoRun,
      ),
    );
  }

  @override
  ConsumerState<DeviceTestDialog> createState() => _DeviceTestDialogState();
}

class _DeviceTestDialogState extends ConsumerState<DeviceTestDialog> {
  bool _isRunning = false;
  String _currentStep = "Listo para iniciar diagnóstico";
  double _progress = 0.0;
  DeviceSelfTestReport? _report;
  bool _showRawLogs = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoRun) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _executeTest();
      });
    }
  }

  Future<void> _executeTest() async {
    if (_isRunning) return;

    final bleState = ref.read(bleServiceProvider);
    final devState = ref.read(devControllerProvider);

    final targetIp = widget.ipAddress ??
        bleState.glassesIp ??
        bleState.savedProfile.lastKnownIp ??
        (devState.isSimulatorMode ? "192.168.4.1" : null);

    if (targetIp == null && !devState.isSimulatorMode) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No hay IP de gafas vinculada. Conecta el dispositivo primero."),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }

    setState(() {
      _isRunning = true;
      _progress = 0.05;
      _currentStep = "Iniciando...";
      _report = null;
    });

    final testService = ref.read(deviceSelfTestServiceProvider);
    final report = await testService.runFullTest(
      ipAddress: targetIp ?? "127.0.0.1",
      deviceName: widget.deviceName ?? bleState.connectedDevice?.platformName ?? "XIAO Gafas",
      isSimulator: devState.isSimulatorMode,
      onProgress: (step, progress) {
        if (mounted) {
          setState(() {
            _currentStep = step;
            _progress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isRunning = false;
        _report = report;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          _buildDragHandle(),
          _buildHeader(),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: _isRunning
                ? _buildProgressView()
                : (_report == null ? _buildIdleView() : _buildReportView(_report!)),
          ),
          if (_report != null && !_isRunning) _buildBottomActionBar(_report!),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.muted.withOpacity(0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.health_and_safety_rounded, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Test Integral de Dispositivo",
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  "Cámara real, Micrófono, Altavoz, Telemetría e IA",
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (!_isRunning)
            IconButton(
              tooltip: "Repetir diagnóstico",
              icon: const Icon(Icons.refresh, color: AppColors.accent),
              onPressed: _executeTest,
            ),
          IconButton(
            tooltip: "Cerrar",
            icon: const Icon(Icons.close, color: AppColors.muted),
            onPressed: () => Navigator.of(context).pop(_report),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    strokeWidth: 5,
                    color: AppColors.accent,
                    backgroundColor: AppColors.surfaceAlt,
                  ),
                ),
                Text(
                  "${(_progress * 100).toInt()}%",
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              _currentStep,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Capturando fotograma real y probando periféricos...",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.checklist_rtl_rounded, color: AppColors.accent, size: 48),
            const SizedBox(height: 16),
            const Text(
              "Listo para probar el sistema",
              style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              "Se verificará la conexión, se tomará una foto real con la cámara de las gafas, se medirá el micrófono y se probará el altavoz.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _executeTest,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text("Iniciar Test Integral"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportView(DeviceSelfTestReport report) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOverallScoreCard(report),
        const SizedBox(height: 14),
        _buildCameraPhotoCard(report),
        const SizedBox(height: 14),
        _buildSubsystemsGrid(report),
        const SizedBox(height: 14),
        _buildSubsystemDetailsList(report),
        const SizedBox(height: 14),
        _buildLogsToggle(report),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildOverallScoreCard(DeviceSelfTestReport report) {
    final isSuccess = report.overallStatus == SubsystemStatus.passed;
    final isWarning = report.overallStatus == SubsystemStatus.warning;
    final statusColor = isSuccess
        ? AppColors.success
        : (isWarning ? AppColors.warning : AppColors.danger);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor.withOpacity(0.2),
            ),
            child: Icon(
              isSuccess
                  ? Icons.check_circle_rounded
                  : (isWarning ? Icons.warning_amber_rounded : Icons.error_outline_rounded),
              color: statusColor,
              size: 32,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        report.overallStatusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${report.overallScore}/100",
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "Dispositivo: ${report.targetIp} · Duración: ${report.totalDurationMs}ms · ${report.formattedDate}",
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPhotoCard(DeviceSelfTestReport report) {
    final photo = report.capturedPhoto;
    final hasPhoto = photo != null && photo.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasPhoto ? AppColors.accent.withOpacity(0.5) : AppColors.danger.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.camera_alt_outlined, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              const Text(
                "FOTO REAL CAPTURADA DE LA CÁMARA",
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (hasPhoto)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${(photo.lengthInBytes / 1024).toStringAsFixed(1)} KB (JPEG)",
                    style: const TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasPhoto)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  GestureDetector(
                    onTap: () => _showFullImagePreview(context, photo),
                    child: Container(
                      width: double.infinity,
                      height: 190,
                      color: Colors.black,
                      child: Image.memory(
                        photo,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Text("Error al renderizar JPEG", style: TextStyle(color: Colors.red)),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.7),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _showFullImagePreview(context, photo),
                      icon: const Icon(Icons.zoom_in, size: 14, color: Colors.white),
                      label: const Text("Ampliar", style: TextStyle(fontSize: 11, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Column(
                children: [
                  Icon(Icons.broken_image_outlined, color: AppColors.danger, size: 36),
                  SizedBox(height: 8),
                  Text(
                    "No se pudo capturar imagen del sensor",
                    style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Verifica que la cámara esté firmemente encajada en el socket FPC.",
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showFullImagePreview(BuildContext context, Uint8List photo) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Center(
                child: Image.memory(photo, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubsystemsGrid(DeviceSelfTestReport report) {
    final tele = report.telemetry;
    final mic = report.micStats;

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.4,
      children: [
        _buildMetricTile(
          icon: Icons.battery_charging_full_rounded,
          title: "Batería",
          value: tele != null ? "${tele.batteryPct}%" : "N/A",
          subtitle: tele != null ? "${tele.batteryVoltage.toStringAsFixed(2)}V" : "",
          color: (tele?.batteryPct ?? 0) > 20 ? AppColors.success : AppColors.danger,
        ),
        _buildMetricTile(
          icon: Icons.wifi,
          title: "Señal Wi-Fi",
          value: tele != null ? "${tele.rssi} dBm" : "N/A",
          subtitle: tele != null ? (tele.rssi > -70 ? "Excelente" : "Débil") : "",
          color: (tele?.rssi ?? -100) > -75 ? AppColors.success : AppColors.warning,
        ),
        _buildMetricTile(
          icon: Icons.mic_rounded,
          title: "Micrófono PDM",
          value: mic != null ? "Pico: ${mic.peakAmplitude}" : "Sin datos",
          subtitle: mic != null ? "RMS: ${mic.rmsLevel.toStringAsFixed(0)}" : "",
          color: (mic?.peakAmplitude ?? 0) > 0 ? AppColors.accent : AppColors.warning,
        ),
        _buildMetricTile(
          icon: Icons.memory_rounded,
          title: "Memoria Libre",
          value: tele != null ? tele.freeHeapKb : "N/A",
          subtitle: tele != null ? "PSRAM: ${tele.freePsramKb}" : "",
          color: AppColors.accent,
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.muted, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildSubsystemDetailsList(DeviceSelfTestReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "DETALLE DE PRUEBAS POR SUBSISTEMA",
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: report.results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final r = report.results[index];
            final color = r.status == SubsystemStatus.passed
                ? AppColors.success
                : (r.status == SubsystemStatus.warning ? AppColors.warning : AppColors.danger);

            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    r.status == SubsystemStatus.passed
                        ? Icons.check_circle
                        : (r.status == SubsystemStatus.warning
                            ? Icons.warning_rounded
                            : Icons.cancel_rounded),
                    color: color,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.title,
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              "${r.latencyMs}ms",
                              style: const TextStyle(color: AppColors.muted, fontSize: 10),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(r.summary, style: TextStyle(color: color, fontSize: 11)),
                        if (r.details.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            r.details,
                            style: const TextStyle(color: AppColors.muted, fontSize: 10),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLogsToggle(DeviceSelfTestReport report) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: const Text(
              "Log de ejecución de diagnóstico",
              style: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            trailing: Icon(
              _showRawLogs ? Icons.expand_less : Icons.expand_more,
              color: AppColors.muted,
            ),
            onTap: () => setState(() => _showRawLogs = !_showRawLogs),
          ),
          if (_showRawLogs)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              width: double.infinity,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  report.logEntries.join('\n'),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(DeviceSelfTestReport report) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton.outlined(
            tooltip: "Copiar log al portapapeles",
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report.generateWhatsAppMessage()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Informe de diagnóstico copiado al portapapeles")),
              );
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366), // Color WhatsApp
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => report.shareReport(includeImage: true),
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text(
                "Compartir en WhatsApp (Foto + Log)",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
