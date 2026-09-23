from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
p = ROOT / "mobile_app" / "lib" / "features" / "background" / "background_service.dart"

p.write_text(r'''import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Callback de entrada en segundo plano para el TaskHandler del sistema.
@pragma('vm:entry-point')
void startBackgroundCallback() {
  FlutterForegroundTask.setTaskHandler(GlassesTaskHandler());
}

/// Handler de tareas en segundo plano que corre incluso con el móvil bloqueado.
class GlassesTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.sendDataToMain({
      'type': 'status',
      'message': 'Servicio de segundo plano activo',
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.sendDataToMain({
      'type': 'heartbeat',
      'timestamp': timestamp.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    FlutterForegroundTask.sendDataToMain({
      'type': 'status',
      'message': 'Servicio detenido',
    });
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Al pulsar un botón de acción en la pantalla de bloqueo (lockscreen)
    FlutterForegroundTask.sendDataToMain({
      'type': 'action',
      'action': id,
    });
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}
}

/// Administrador del servicio de primer plano (Foreground Service / Notificación persistente)
/// que permite operar las gafas con el teléfono bloqueado en el bolsillo.
class BackgroundServiceManager {
  static bool _initialized = false;

  static const String actionIdentify = 'btn_action_identify';
  static const String actionDiagnose = 'btn_action_diagnose';
  static const String actionProcedure = 'btn_action_procedure';

  static const List<NotificationButton> _lockscreenButtons = [
    NotificationButton(id: actionIdentify, text: '🔍 Identificar'),
    NotificationButton(id: actionDiagnose, text: '🩺 Diagnosticar'),
    NotificationButton(id: actionProcedure, text: '📋 Procedimiento'),
  ];

  static Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) return;

    try {
      FlutterForegroundTask.initCommunicationPort();

      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'glasses_pro_bg_channel',
          channelName: 'GlassesPro Enlace Activo',
          channelDescription: 'Mantiene la conexión y control con las gafas cuando el móvil está bloqueado.',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: true,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(5000),
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('BackgroundServiceManager init error: $e');
    }
  }

  static Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid) {
        final notifGranted = await FlutterForegroundTask.checkNotificationPermission();
        if (notifGranted != NotificationPermission.granted) {
          await FlutterForegroundTask.requestNotificationPermission();
        }
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> startBackgroundService({
    String title = 'GlassesPro · Gafas Conectadas',
    String text = 'Toca una acción en la pantalla de bloqueo o habla a las gafas',
  }) async {
    if (kIsWeb) return false;
    try {
      await initialize();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.restartService();
        return true;
      }
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: title,
        notificationText: text,
        notificationButtons: _lockscreenButtons,
        callback: startBackgroundCallback,
      );
      return true;
    } catch (e) {
      debugPrint('startBackgroundService error: $e');
      return false;
    }
  }

  static Future<void> updateNotification({
    String? title,
    String? text,
  }) async {
    if (kIsWeb) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
          notificationButtons: _lockscreenButtons,
        );
      }
    } catch (_) {}
  }

  static Future<bool> stopBackgroundService() async {
    if (kIsWeb) return false;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isServiceRunning() async {
    if (kIsWeb) return false;
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }
}
''', encoding='utf-8')
print('background_service written')
