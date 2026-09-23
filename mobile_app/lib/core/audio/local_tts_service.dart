import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

/// TTS 100% en dispositivo (gratis, sin backend) usando el motor del sistema
/// (Android TextToSpeech / iOS AVSpeech). Enfocado en español peninsular.
///
/// En Android la calidad/variedad depende del paquete de voz instalado
/// (Google TTS con voz "es-ES"). La app preselecciona la primera voz es-ES
/// disponible y permite cambiarla desde el menú TTS.
class LocalTtsService {
  LocalTtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;

  static const defaultLanguage = 'es-ES';

  Future<void> ensureReady({
    String language = defaultLanguage,
    String? voiceName,
    double speechRate = 0.5,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
    try {
      await _tts.setSharedInstance(true);
      await _tts.setLanguage(language);
      await _tts.setSpeechRate(speechRate);
      await _tts.setPitch(pitch);
      await _tts.setVolume(volume);
      if (voiceName != null && voiceName.isNotEmpty) {
        final voices = await esEsVoices();
        final match = voices.firstWhere(
          (v) => (v['name'] ?? '').toString() == voiceName,
          orElse: () => <String, String>{},
        );
        if (match.isNotEmpty) {
          await _tts.setVoice({'name': match['name']!, 'locale': match['locale']!});
        }
      } else {
        // Preselección: primera voz es-ES disponible.
        final voices = await esEsVoices();
        if (voices.isNotEmpty) {
          await _tts.setVoice({'name': voices.first['name']!, 'locale': voices.first['locale']!});
        }
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Voces del sistema filtradas a español de España (es-ES).
  /// Devuelve mapas {name, locale}. Vacío si el motor no responde.
  Future<List<Map<String, String>>> esEsVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return [];
      final out = <Map<String, String>>[];
      for (final v in raw) {
        if (v is! Map) continue;
        final locale = (v['locale'] ?? v['Locale'] ?? '').toString();
        final name = (v['name'] ?? v['Name'] ?? '').toString();
        if (locale.toLowerCase().startsWith('es-es') ||
            (locale.toLowerCase().startsWith('es') && name.toLowerCase().contains('espa'))) {
          out.add({'name': name, 'locale': locale.isEmpty ? defaultLanguage : locale});
        }
      }
      // Fallback: si el filtro es-ES no matchea pero hay voces 'es', ofrecerlas.
      if (out.isEmpty) {
        for (final v in raw) {
          if (v is! Map) continue;
          final locale = (v['locale'] ?? '').toString();
          final name = (v['name'] ?? '').toString();
          if (locale.toLowerCase().startsWith('es')) {
            out.add({'name': name, 'locale': locale.isEmpty ? defaultLanguage : locale});
          }
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> esEsLanguages() async {
    try {
      final langs = await _tts.getLanguages;
      if (langs is! List) return [defaultLanguage];
      return langs.map((e) => e.toString()).where((l) => l.toLowerCase().startsWith('es')).toList();
    } catch (_) {
      return [defaultLanguage];
    }
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    if (!_ready) await ensureReady();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  /// Sintetiza a fichero WAV para poder enviar el audio a las gafas
  /// (mismo flujo que el TTS cloud). Devuelve el WAV completo o null.
  Future<Uint8List?> synthesizeToWavFile(String text) async {
    if (text.trim().isEmpty) return null;
    if (!_ready) await ensureReady();
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/local_tts_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _tts.synthesizeToFile(text, path);
      // synthesizeToFile es fire-and-forget en algunas versiones: esperar fichero.
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final f = File(path);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          if (bytes.length > 44) return bytes;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> setRate(double v) async {
    try {
      await _tts.setSpeechRate(v.clamp(0.0, 1.0));
    } catch (_) {}
  }

  Future<void> setPitch(double v) async {
    try {
      await _tts.setPitch(v.clamp(0.5, 2.0));
    } catch (_) {}
  }

  Future<void> setVolume(double v) async {
    try {
      await _tts.setVolume(v.clamp(0.0, 1.0));
    } catch (_) {}
  }

  Future<void> setVoiceName(String name, String locale) async {
    try {
      await _tts.setVoice({'name': name, 'locale': locale});
    } catch (_) {}
  }
}
