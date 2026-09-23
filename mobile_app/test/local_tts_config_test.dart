import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses_app/core/config/app_config_provider.dart';

void main() {
  test('TTS por defecto: sistema gratis es-ES activado', () {
    final cfg = AppConfigState();
    expect(cfg.enableTtsPlayback, isTrue);
    expect(cfg.ttsMode, 'system');
    expect(cfg.ttsRate, inInclusiveRange(0.0, 1.0));
    expect(cfg.ttsPitch, inInclusiveRange(0.5, 2.0));
    expect(cfg.ttsVolume, inInclusiveRange(0.0, 1.0));
  });

  test('copyWith conserva ajustes TTS', () {
    final cfg = AppConfigState().copyWith(ttsMode: 'cloud', ttsVoiceName: 'es-es-voice', ttsRate: 0.7);
    expect(cfg.ttsMode, 'cloud');
    expect(cfg.ttsVoiceName, 'es-es-voice');
    expect(cfg.ttsRate, 0.7);
  });
}
