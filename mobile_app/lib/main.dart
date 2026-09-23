import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/assistant_screen/assistant_view.dart';
import 'features/background/background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundServiceManager.initialize();
  runApp(const ProviderScope(child: SmartGlassesApp()));
}

class SmartGlassesApp extends StatelessWidget {
  const SmartGlassesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GlassesPro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AssistantView(),
    );
  }
}
