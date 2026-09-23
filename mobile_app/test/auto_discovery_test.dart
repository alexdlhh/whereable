import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses_app/features/connectivity/ble_service.dart';
import 'package:smart_glasses_app/features/connectivity/device_discovery_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Auto-Discovery & DiscoveredGlassesDevice', () {
    test('DiscoveredGlassesDevice calcula etiquetas de señal correctamente', () {
      final devExcellent = DiscoveredGlassesDevice(
        id: '1',
        name: 'Gafas Pro',
        rssi: -50,
        medium: DeviceMedium.ble,
      );
      expect(devExcellent.signalLabel, 'Excelente');

      final devGood = DiscoveredGlassesDevice(
        id: '2',
        name: 'Gafas Pro',
        rssi: -70,
        medium: DeviceMedium.wifi,
      );
      expect(devGood.signalLabel, 'Buena');

      final devMedium = DiscoveredGlassesDevice(
        id: '3',
        name: 'Gafas Pro',
        rssi: -80,
        medium: DeviceMedium.softAp,
      );
      expect(devMedium.signalLabel, 'Media');

      final devWeak = DiscoveredGlassesDevice(
        id: '4',
        name: 'Gafas Pro',
        rssi: -90,
        medium: DeviceMedium.ble,
      );
      expect(devWeak.signalLabel, 'Débil');
    });

    test('BleState maneja lista de dispositivos encontrados y estado de búsqueda', () {
      final state = BleState(
        status: SyncStatus.disconnected,
        savedProfile: GlassesDeviceProfile(),
        isSearching: true,
        detectedPhoneWifiSsid: 'MiTaller_5G',
        discoveredDevices: [
          DiscoveredGlassesDevice(
            id: 'dev_01',
            name: 'XIAO-SmartGlasses',
            rssi: -58,
            medium: DeviceMedium.ble,
          ),
          DiscoveredGlassesDevice(
            id: 'wifi_192.168.1.50',
            name: 'XIAO-SmartGlasses (Wi-Fi)',
            rssi: -62,
            medium: DeviceMedium.wifi,
            ip: '192.168.1.50',
          ),
        ],
      );

      expect(state.isSearching, isTrue);
      expect(state.detectedPhoneWifiSsid, 'MiTaller_5G');
      expect(state.discoveredDevices.length, 2);
      expect(state.discoveredDevices.first.name, 'XIAO-SmartGlasses');
      expect(state.discoveredDevices.last.ip, '192.168.1.50');
    });

    testWidgets('DeviceDiscoverySheet renderiza radar, dispositivos y aprovisionamiento', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          bleServiceProvider.overrideWith((ref) => BleService(autoStart: false)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: DeviceDiscoverySheet(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Buscador de Gafas'), findsOneWidget);
      expect(find.text('Auto-descubrimiento Bluetooth LE y Red Local'), findsOneWidget);
      expect(find.text('DISPOSITIVOS ENCONTRADOS'), findsOneWidget);
      expect(find.text('APROVISIONAMIENTO WI-FI ASISTIDO'), findsOneWidget);
      expect(find.text('Conexión manual por IP directa'), findsOneWidget);
    });
  });
}
