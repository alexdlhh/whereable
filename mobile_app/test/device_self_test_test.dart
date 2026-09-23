import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses_app/core/config/app_config_provider.dart';
import 'package:smart_glasses_app/features/connectivity/wifi_sync_service.dart';
import 'package:smart_glasses_app/features/diagnostics/device_self_test_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DeviceSelfTestService ejecuta diagnóstico completo en modo simulador', () async {
    final wifiService = WifiSyncService();
    final config = AppConfigState();
    final service = DeviceSelfTestService(
      wifiService: wifiService,
      config: config,
    );

    final report = await service.runFullTest(
      ipAddress: "192.168.4.1",
      deviceName: "XIAO Gafas Test",
      isSimulator: true,
    );

    expect(report.overallStatus, SubsystemStatus.passed);
    expect(report.overallScore, 100);
    expect(report.results.length, 5);
    expect(report.capturedPhoto, isNotNull);
    expect(report.capturedPhoto!.isNotEmpty, true);
    expect(report.capturedPhoto![0], 0xFF);
    expect(report.capturedPhoto![1], 0xD8); // Valid JPEG SOI

    final waMsg = report.generateWhatsAppMessage();
    expect(waMsg.contains("REPORTE DE DIAGNÓSTICO TÉCNICO"), true);
    expect(waMsg.contains("Foto de cámara adjunta"), true);
    expect(waMsg.contains("192.168.4.1"), true);
  });
}
