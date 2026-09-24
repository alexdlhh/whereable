import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config_provider.dart';

/// V57 - Motor de STT (reconocimiento de voz) desacoplado.
///
/// La app Kotlin que funciona usa Vosk (local, en el teléfono) para la escucha
/// continua. En Flutter no hay un paquete Vosk estable, así que este motor es
/// PLUGGABLE:
///   - [CloudSttEngine] (implementado): agrupa el audio y lo envía al endpoint
///     de transcripción configurado (Whisper / OpenAI / IAPymex).
///   - PUNTO DE EXTENSIÓN: para escucha continua 100% local (Vosk/Sherpa nativo)
///     basta con implementar [SttEngine] con el motor nativo y cambiar el
///     provider [sttEngineProvider]. El bucle de escucha continua
///     ([ContinuousListeningService]) no cambia.
abstract class SttEngine {
  /// Transcribe un trozo de PCM S16LE 16 kHz mono. Devuelve el texto o null.
  Future<String?> transcribe(Uint8List pcm16kMono);

  /// Nombre corto para diagnóstico.
  String get name;
}

/// Motor STT por la nube (endpoint /audio/transcriptions del backend configurado).
class CloudSttEngine implements SttEngine {
  CloudSttEngine(this.ref);

  final Ref ref;

  @override
  String get name => 'cloud-stt';

  @override
  Future<String?> transcribe(Uint8List pcm16kMono) async {
    if (pcm16kMono.isEmpty) return null;
    final config = ref.read(appConfigProvider);
    final url = "${config.apiBaseUrl}${_transcriptionsEndpoint(config.apiBaseUrl)}";
    try {
      // El endpoint OpenAI espera un WAV; envolvemos el PCM en cabecera RIFF.
      final wav = _wrapPcm16kMonoInWav(pcm16kMono);
      final req = http.MultipartRequest('POST', Uri.parse(url));
      req.headers['Authorization'] = 'Bearer ${config.apiKey}';
      req.fields['model'] = 'whisper-1';
      req.fields['language'] = 'es';
      req.files.add(http.MultipartFile.fromBytes('file', wav, filename: 'audio.wav'));
      final streamed = await req.send().timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['text'] as String?)?.trim();
      }
    } catch (_) {}
    return null;
  }

  String _transcriptionsEndpoint(String baseUrl) {
    // Gemini nativo no usa /audio/transcriptions; se deja vacío para que falle
    // de forma controlada (la escucha continua requiere un backend OpenAI-compat).
    if (baseUrl.contains('generativelanguage.googleapis.com')) return '';
    return '/audio/transcriptions';
  }

  /// Envuelve PCM S16LE 16 kHz mono en un WAV RIFF mínimo.
  Uint8List _wrapPcm16kMonoInWav(Uint8List pcm) {
    const sampleRate = 16000;
    final dataLen = pcm.length;
    final out = BytesBuilder();
    void le16(int v) {
      out.addByte(v & 0xFF);
      out.addByte((v >> 8) & 0xFF);
    }

    void le32(int v) {
      out.addByte(v & 0xFF);
      out.addByte((v >> 8) & 0xFF);
      out.addByte((v >> 16) & 0xFF);
      out.addByte((v >> 24) & 0xFF);
    }

    out.add('RIFF'.codeUnits);
    le32(36 + dataLen);
    out.add('WAVE'.codeUnits);
    out.add('fmt '.codeUnits);
    le32(16);
    le16(1); // PCM
    le16(1); // mono
    le32(sampleRate);
    le32(sampleRate * 2); // byte rate
    le16(2); // block align
    le16(16); // bits
    out.add('data'.codeUnits);
    le32(dataLen);
    out.add(pcm);
    return out.toBytes();
  }
}

/// Provider del motor STT activo. Sustituir por un motor nativo (Vosk/Sherpa)
/// para escucha continua 100% local sin tocar el bucle de escucha.
final sttEngineProvider = Provider<SttEngine>((ref) {
  return CloudSttEngine(ref);
});
