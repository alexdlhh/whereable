import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/wav_encoder.dart';

/// Reproduce PCM en el altavoz del teléfono con soporte para pantalla bloqueada.
/// Configura el AudioContext global con stayAwake y categoría Playback (similar a apps de música).
class PhonePlayback {
  PhonePlayback({AudioPlayer? player}) {
    if (player != null) {
      _player = player;
    }
  }

  AudioPlayer? _player;
  static bool _contextConfigured = false;

  AudioPlayer get player {
    _player ??= AudioPlayer();
    _configureAudioContext();
    return _player!;
  }

  static Future<void> _configureAudioContext() async {
    if (_contextConfigured || kIsWeb) return;
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.assistanceAccessibility,
            audioMode: AndroidAudioMode.normal,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.duckOthers,
              AVAudioSessionOptions.defaultToSpeaker,
            },
          ),
        ),
      );
      _contextConfigured = true;
    } catch (_) {}
  }

  Future<bool> playPcm16(
    Uint8List pcm, {
    int sampleRate = 16000,
    int channels = 1,
  }) async {
    try {
      final wav = WavEncoder.pcm16ToWav(pcm, sampleRate: sampleRate, channels: channels);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/glasses_tts_fallback.wav');
      await file.writeAsBytes(wav, flush: true);
      await player.stop();
      await player.play(DeviceFileSource(file.path));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
