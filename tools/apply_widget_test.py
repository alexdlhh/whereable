from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
t = ROOT / "mobile_app" / "test" / "widget_app_test.dart"

t.write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses_app/main.dart';
import 'package:smart_glasses_app/features/connectivity/ble_service.dart';

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
    expect(find.byIcon(Icons.screen_lock_portrait_outlined), findsOneWidget);
  });
}
''', encoding='utf-8')
print('widget_app_test updated')
