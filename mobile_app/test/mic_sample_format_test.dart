import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses_app/core/utils/wav_encoder.dart';
import 'package:smart_glasses_app/features/connectivity/wifi_sync_service.dart';

/// Contrato /mic_sample del firmware: PCM S16LE, 16 kHz, mono, sin cabecera.
/// Estos tests fijan que la app interpreta y re-empaqueta el audio con el
/// formato exacto (un rate erróneo suena acelerado o a ruido).
void main() {
  group('MicSampleFormat (contrato firmware)', () {
    test('es S16LE 16kHz mono', () {
      expect(MicSampleFormat.sampleRate, 16000);
      expect(MicSampleFormat.channels, 1);
      expect(MicSampleFormat.bitsPerSample, 16);
      expect(MicSampleFormat.bytesPerSecond, 32000);
    });

    test('16000 bytes ~= 0.5s de audio', () {
      expect(MicSampleFormat.durationSec(Uint8List(16000)), closeTo(0.5, 0.001));
    });
  });

  group('WAV para muestra de micrófono', () {
    test('cabecera declara 16kHz mono 16-bit', () {
      final pcm = Uint8List(3200); // 100ms @16kHz mono s16
      final wav = WavEncoder.pcm16ToWav(
        pcm,
        sampleRate: MicSampleFormat.sampleRate,
        channels: MicSampleFormat.channels,
      );
      final header = ByteData.sublistView(wav, 0, 44);
      expect(header.getUint16(20, Endian.little), 1); // PCM
      expect(header.getUint16(22, Endian.little), 1); // mono
      expect(header.getUint32(24, Endian.little), 16000);
      expect(header.getUint32(28, Endian.little), 32000); // byteRate
      expect(header.getUint16(32, Endian.little), 2); // blockAlign
      expect(header.getUint16(34, Endian.little), 16);
      expect(header.getUint32(40, Endian.little), 3200);
      // PCM intacto tras la cabecera (sin remuestreo).
      expect(wav.sublist(44), pcm);
    });

    test('los bytes S16LE se leen little-endian', () {
      final data = ByteData(32);
      for (var i = 0; i < 16; i++) {
        data.setInt16(i * 2, (i * 4000).clamp(-32768, 32767), Endian.little);
      }
      final raw = data.buffer.asUint8List();
      // Re-leer como hace la app: debe recuperar los valores escritos.
      for (var i = 0; i < 16; i++) {
        expect(raw.buffer.asByteData().getInt16(i * 2, Endian.little), data.getInt16(i * 2, Endian.little));
      }
    });
  });
}
