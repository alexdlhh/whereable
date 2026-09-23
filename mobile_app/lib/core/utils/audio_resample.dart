import 'dart:typed_data';

/// Utilidades PCM s16le para alinear TTS (típicamente 24 kHz mono) con I2S 16 kHz.
class AudioResample {
  static Int16List asInt16(Uint8List bytes) {
    final evenLen = bytes.length - (bytes.length % 2);
    final data = ByteData.sublistView(bytes, 0, evenLen);
    final samples = Int16List(evenLen ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little);
    }
    return samples;
  }

  static Uint8List int16ToBytes(Int16List samples) {
    final out = ByteData(samples.length * 2);
    for (var i = 0; i < samples.length; i++) {
      out.setInt16(i * 2, samples[i], Endian.little);
    }
    return out.buffer.asUint8List();
  }

  /// Remuestreo lineal. [fromRate]/[toRate] p.ej. 24000 → 16000.
  static Int16List resampleLinear(Int16List input, int fromRate, int toRate) {
    if (fromRate <= 0 || toRate <= 0 || input.isEmpty) return input;
    if (fromRate == toRate) return Int16List.fromList(input);
    final outLen = (input.length * toRate / fromRate).floor();
    if (outLen <= 0) return Int16List(0);
    final out = Int16List(outLen);
    for (var i = 0; i < outLen; i++) {
      final srcPos = i * fromRate / toRate;
      final idx = srcPos.floor();
      final frac = srcPos - idx;
      final a = input[idx.clamp(0, input.length - 1)];
      final b = input[(idx + 1).clamp(0, input.length - 1)];
      out[i] = (a + (b - a) * frac).round().clamp(-32768, 32767);
    }
    return out;
  }

  static Uint8List prepareGlassesPcm(
    Uint8List pcm, {
    int sourceRate = 24000,
    int targetRate = 16000,
  }) {
    final samples = asInt16(pcm);
    final resampled = resampleLinear(samples, sourceRate, targetRate);
    return int16ToBytes(resampled);
  }
}
