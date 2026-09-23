import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses_app/main.dart';
import 'package:smart_glasses_app/features/connectivity/ble_service.dart';
import 'package:smart_glasses_app/features/developer_mode/dev_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('la app profesional muestra marca y estado vacío con botón de pantalla bloqueada', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleServiceProvider.overrideWith((ref) => BleService(autoStart: false)),
        ],
        child: const SmartGlassesApp(),
      ),
    );
    await tester.pump();

    expect(find.text('GlassesPro'), findsOneWidget);
    expect(find.text('Soporte técnico de campo'), findsOneWidget);
    expect(find.text('Listo para el trabajo de campo'), findsOneWidget);
    expect(find.text('Identificar'), findsOneWidget);
    expect(find.text('Diagnosticar'), findsOneWidget);
    expect(find.text('ACCIONES RÁPIDAS (INPUT GAFAS)'), findsOneWidget);
    expect(find.byIcon(Icons.screen_lock_portrait_outlined), findsOneWidget);
  });

  testWidgets('permite eliminar tareas individuales y limpiar historial', (tester) async {
    final container = ProviderContainer(
      overrides: [
        bleServiceProvider.overrideWith((ref) => BleService(autoStart: false)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SmartGlassesApp(),
      ),
    );
    await tester.pump();

    final devCtrl = container.read(devControllerProvider.notifier);
    devCtrl.toggleSimulatorMode();
    devCtrl.triggerAiQuery('Identifica el componente');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Identifica el componente'), findsOneWidget);
    expect(find.text('Historial de tareas (1)'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    // Borrar la tarea usando el botón de eliminar
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    expect(find.text('Identifica el componente'), findsNothing);
    expect(find.text('Listo para el trabajo de campo'), findsOneWidget);
  });
}
