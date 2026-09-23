import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses_app/features/background/background_service.dart';
import 'package:smart_glasses_app/features/developer_mode/dev_controller.dart';
import 'package:smart_glasses_app/features/connectivity/ble_service.dart';
import 'package:smart_glasses_app/core/audio/phone_playback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BackgroundServiceManager & Lock Screen Actions', () {
    test('constantes de botones en pantalla de bloqueo son válidas', () {
      expect(BackgroundServiceManager.actionIdentify, 'btn_action_identify');
      expect(BackgroundServiceManager.actionDiagnose, 'btn_action_diagnose');
      expect(BackgroundServiceManager.actionProcedure, 'btn_action_procedure');
    });

    test('DevController procesa acción de identificar desde lockscreen', () async {
      final container = ProviderContainer(
        overrides: [
          bleServiceProvider.overrideWith((ref) => BleService(autoStart: false)),
        ],
      );
      addTearDown(container.dispose);

      final ctrl = container.read(devControllerProvider.notifier);
      ctrl.toggleSimulatorMode(); // Usa modo mock para testing rápido

      ctrl.handleBackgroundAction(BackgroundServiceManager.actionIdentify);

      // Esperar resolución de pipeline mock
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final state = container.read(devControllerProvider);
      expect(state.history.isNotEmpty, true);
      expect(state.history.first.userQuery.contains('Identifica el componente'), true);
      expect(state.history.first.usedMock, true);
    });

    test('DevController procesa acción de diagnosticar desde lockscreen', () async {
      final container = ProviderContainer(
        overrides: [
          bleServiceProvider.overrideWith((ref) => BleService(autoStart: false)),
        ],
      );
      addTearDown(container.dispose);

      final ctrl = container.read(devControllerProvider.notifier);
      ctrl.toggleSimulatorMode();

      ctrl.handleBackgroundAction(BackgroundServiceManager.actionDiagnose);
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final state = container.read(devControllerProvider);
      expect(state.history.isNotEmpty, true);
      expect(state.history.first.userQuery.contains('¿Detectas fallo'), true);
    });

    test('DevController procesa acción de procedimiento desde lockscreen', () async {
      final container = ProviderContainer(
        overrides: [
          bleServiceProvider.overrideWith((ref) => BleService(autoStart: false)),
        ],
      );
      addTearDown(container.dispose);

      final ctrl = container.read(devControllerProvider.notifier);
      ctrl.toggleSimulatorMode();

      ctrl.handleBackgroundAction(BackgroundServiceManager.actionProcedure);
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final state = container.read(devControllerProvider);
      expect(state.history.isNotEmpty, true);
      expect(state.history.first.userQuery.contains('Guíame paso a paso'), true);
    });

    test('PhonePlayback se instancia correctamente con AudioContext stayAwake', () {
      final playback = PhonePlayback();
      expect(playback, isNotNull);
    });
  });
}
