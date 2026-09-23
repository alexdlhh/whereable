# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "mobile_app"

(APP / "pubspec.yaml").write_text(r'''name: smart_glasses_app
description: "Herramienta profesional de apoyo técnico con gafas inteligentes, IA multimodal y capa de diagnóstico."
publish_to: "none"
version: 1.2.0+12

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  flutter_blue_plus: ^1.33.0
  http: ^1.2.1
  web_socket_channel: ^3.0.0
  network_info_plus: ^6.0.0
  permission_handler: ^11.3.1
  shared_preferences: ^2.2.3
  record: ^5.1.2
  audioplayers: ^6.0.0
  path_provider: ^2.1.3
  file_picker: ^8.0.0
  cupertino_icons: ^1.0.8
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
'''.replace('\r\n', '\n'), encoding='utf-8')

(APP / "lib" / "main.dart").write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/assistant_screen/assistant_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
'''.replace('\r\n', '\n'), encoding='utf-8')

print('wrote pubspec and main.dart')
