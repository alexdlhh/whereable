import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio/phone_playback.dart';
import '../connectivity/wifi_sync_service.dart';
import 'stt_engine.dart';

/// V57 - ESCUCHA CONTINUA + FULL-DUPLEX + BARGE-IN.
///
/// Port de la arquitectura de la app Kotlin que funciona:
///  - Bucle de escucha continua: pide bloques de 100 ms a GET /mic_sample del
///    XIAO (el firmware ya los entrega frescos) y los acumula en un buffer.
///  - VAD por energía (RMS): detecta el inicio y el fin de frase (silencio).
///  - Al cerrar la frase, transcribe con el [SttEngine] activo y emite la frase
///    por [phrases] para que el controlador la mande al pipeline IA.
///  - FULL-DUPLEX: el bucle sigue escuchando mientras el asistente habla.
///  - BARGE-IN: si detecta voz del usuario mientras [isAssistantSpeaking],
///    emite [bargeIn] para que el controlador corte el TTS.
///
/// El STT es plugable: hoy [CloudSttEngine]; un motor nativo (Vosk/Sherpa)
/// se enchufa sin tocar este bucle.
class ContinuousListeningService {
  ContinuousListeningService(this.ref)
      : _wifi = ref.read(wifiSyncServiceProvider),
        _stt = ref.read(sttEngineProvider),
        _playback = ref.read(phonePlaybackProvider);

  final Ref ref;
  final WifiSyncService _wifi;
  final SttEngine _stt;
  final PhonePlayback _playback;

  /// Frases reconocidas listas para el pipeline IA.
  final StreamController<String> _phrases = StreamController<String>.broadcast();
  Stream<String> get phrases => _phrases.stream;

  /// Señal de barge-in (voz del usuario mientras el asistente habla).
  final StreamController<void> _bargeIn = StreamController<void>.broadcast();
  Stream<void> get bargeIn => _bargeIn.stream;

  /// El asistente está hablando (lo marca el controlador al reproducir TTS).
  bool isAssistantSpeaking = false;

  /// Texto que se está reproduciendo (para descartar ecos del altavoz).
  String currentAssistantSpeech = '';

  bool _running = false;
  bool _processing = false;
  final List<int> _buffer = [];
  bool _inSpeech = false;
  int _silenceFrames = 0;
  int _consecutiveFetchErrors = 0;

  // Parámetros VAD (ajustados al micrófono PDM del XIAO, 16 kHz s16le).
  static const int _frameBytes = 3200; // 100 ms
  static const double _rmsSpeechThreshold = 150.0;
  static const int _minSpeechFrames = 2; // ~200 ms de voz
  static const int _silenceFramesToClose = 6; // ~600 ms de silencio
  static const int _maxSpeechFrames = 60; // ~6 s por frase
  static const int _maxConsecutiveFetchErrors = 10;

  /// Arranca el bucle de escucha continua. [ip] es la IP del XIAO.
  Future<void> start(String ip) async {
    if (_running) return;
    _running = true;
    _buffer.clear();
    _inSpeech = false;
    _silenceFrames = 0;
    debugPrint('[V57] Escucha continua iniciada en $ip (STT: ${_stt.name})');
    _loop(ip);
  }

  Future<void> stop() async {
    _running = false;
    _buffer.clear();
    _inSpeech = false;
    debugPrint('[V57] Escucha continua detenida');
  }

  Future<void> dispose() async {
    await stop();
    await _phrases.close();
    await _bargeIn.close();
  }

  Future<void> _loop(String ip) async {
    while (_running) {
      if (_processing) {
        // Mientras transcribe/IA, no acumulamos (evita solaparse).
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }

      final sample = await _wifi.fetchMicSample(ip);
      if (sample == null || sample.isEmpty) {
        _consecutiveFetchErrors++;
        if (_consecutiveFetchErrors >= _maxConsecutiveFetchErrors) {
          debugPrint('[V57] /mic_sample sin datos $_consecutiveFetchErrors veces; pausa 2 s');
          _consecutiveFetchErrors = 0;
          await Future<void>.delayed(const Duration(seconds: 2));
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        continue;
      }
      _consecutiveFetchErrors = 0;

      final rms = _rms(sample);
      final voiced = rms > _rmsSpeechThreshold;

      if (voiced) {
        _buffer.addAll(sample);
        _silenceFrames = 0;
        if (!_inSpeech) {
          _inSpeech = true;
        }
        // BARGE-IN: voz clara mientras el asistente habla.
        if (isAssistantSpeaking && rms > _rmsSpeechThreshold * 1.4) {
          _bargeIn.add(null);
        }
      } else {
        if (_inSpeech) {
          _silenceFrames++;
          if (_silenceFrames >= _silenceFramesToClose) {
            await _closePhrase();
          }
        }
      }

      // Tope de duración de frase.
      if (_inSpeech && _buffer.length >= _maxSpeechFrames * _frameBytes) {
        await _closePhrase();
      }

      // Ritmo ~100 ms (el fetch ya tarda ~100 ms; pequeño margen).
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> _closePhrase() async {
    final pcm = Uint8List.fromList(_buffer);
    _buffer.clear();
    _inSpeech = false;
    _silenceFrames = 0;
    if (pcm.length < _frameBytes * _minSpeechFrames) return;

    _processing = true;
    try {
      final text = await _stt.transcribe(pcm);
      if (text == null || text.trim().isEmpty) return;
      final clean = text.trim();
      // Descartar ecos evidentes del propio altavoz.
      if (isAssistantSpeaking && _looksLikeEcho(clean, currentAssistantSpeech)) {
        debugPrint('[V57] Eco del altavoz ignorado: "$clean"');
        return;
      }
      debugPrint('[V57] Frase reconocida: "$clean"');
      _phrases.add(clean);
    } catch (e) {
      debugPrint('[V57] Error transcribiendo frase: $e');
    } finally {
      _processing = false;
    }
  }

  /// RMS de un trozo PCM S16LE.
  double _rms(Uint8List pcm) {
    if (pcm.length < 2) return 0;
    var sum = 0.0;
    var n = 0;
    for (var i = 0; i + 1 < pcm.length; i += 2) {
      final lo = pcm[i] & 0xFF;
      final hi = pcm[i + 1];
      final s = ((hi << 8) | lo) - (1 << 15); // s16
      sum += s * s;
      n++;
    }
    return n == 0 ? 0 : math.sqrt(sum / n);
  }

  /// ¿El texto oído parece eco de lo que el asistente está diciendo?
  bool _looksLikeEcho(String heard, String assistant) {
    if (heard.isEmpty || assistant.isEmpty) return false;
    final h = heard.toLowerCase();
    final a = assistant.toLowerCase();
    if (' $a '.contains(' $h ')) return true;
    final hWords = h.split(' ').where((w) => w.isNotEmpty).toList();
    if (hWords.length < 2) return false;
    final aSet = a.split(' ').toSet();
    final matched = hWords.where((w) => aSet.contains(w)).length;
    return matched >= 2 && matched / hWords.length >= 0.8;
  }

  /// Corta la reproducción de TTS (barge-in).
  Future<void> interruptPlayback() async {
    isAssistantSpeaking = false;
    currentAssistantSpeech = '';
    await _playback.stop();
  }
}

final continuousListeningProvider = Provider<ContinuousListeningService>((ref) {
  return ContinuousListeningService(ref);
});
