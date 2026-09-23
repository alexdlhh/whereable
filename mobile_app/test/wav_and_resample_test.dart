import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses_app/core/utils/audio_resample.dart';
import 'package:smart_glasses_app/core/utils/wav_encoder.dart';

void main() {
  group('WavEncoder', () {
    test('escribe cabecera RIFF/WAVE de 44 bytes', () {
      final pcm = Uint8List.fromList([0x00, 0x00, 0x01, 0x00]);
      final wav = WavEncoder.pcm16ToWav(pcm, sampleRate: 16000, channels: 1);
      expect(wav.length, 48);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      expect(wav.sublist(44), pcm);
    });
  });

  group('AudioResample', () {
    test('identidad si las tasas coinciden', () {
      final samples = Int16List.fromList([0, 1000, -1000, 32767]);
      final out = AudioResample.resampleLinear(samples, 16000, 16000);
      expect(out, samples);
    });

    test('24 kHz a 16 kHz reduce longitud ~2/3', () {
      final samples = Int16List.fromList(List<int>.generate(240, (i) => i));
      final out = AudioResample.resampleLinear(samples, 24000, 16000);
      expect(out.length, 160);
    });

    test('prepareGlassesPcm mantiene bytes pares', () {
      final pcm = Uint8List(480);
      final out = AudioResample.prepareGlassesPcm(pcm, sourceRate: 24000, targetRate: 16000);
      expect(out.length % 2, 0);
      expect(out.length, 320);
    });
  });
}
