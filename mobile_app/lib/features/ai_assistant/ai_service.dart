import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/config/app_config_provider.dart';
import '../../core/utils/curl_builder.dart';
import '../../core/utils/audio_resample.dart';
import '../../core/audio/phone_playback.dart';
import '../../core/audio/local_tts_service.dart';
import 'models/ai_response_model.dart';
import 'mock_responses.dart';
import '../connectivity/wifi_sync_service.dart';

class AiService {
  AiService(this.ref, {http.Client? client, PhonePlayback? playback, LocalTtsService? localTts})
      : _client = client ?? http.Client(),
        _playback = playback ?? PhonePlayback(),
        _localTts = localTts ?? LocalTtsService();

  final Ref ref;
  final http.Client _client;
  final PhonePlayback _playback;
  final LocalTtsService _localTts;

  Future<AiInteractionResult> processMultimodalQuery({
    required String userPrompt,
    required String? glassesIp,
    Uint8List? directImageBytes,
    bool useMock = false,
  }) async {
    if (useMock) {
      await Future<void>.delayed(const Duration(milliseconds: 280));
      return AiInteractionResult(
        userQuery: userPrompt,
        assistantResponse: MockResponses.forQuery(userPrompt),
        metrics: AiPipelineMetrics(llmLatencyMs: 280, totalRoundTripMs: 280),
        rawRequestPayload: {"mock": true, "prompt": userPrompt},
        rawResponsePayload: {"mock": true},
        generatedCurl: "# modo simulador — no hay petición de red",
        timestamp: DateTime.now(),
        usedMock: true,
      );
    }

    final config = ref.read(appConfigProvider);
    final totalStopwatch = Stopwatch()..start();
    var metrics = AiPipelineMetrics();

    Uint8List? imageBytes = directImageBytes;
    var cameraFetchFailed = false;
    if (imageBytes == null && glassesIp != null && glassesIp.isNotEmpty) {
      final camWatch = Stopwatch()..start();
      final wifiService = ref.read(wifiSyncServiceProvider);
      // Usar preset de alta nitidez y compensación de exposición para evitar deslumbramiento por pantallas/luces
      imageBytes = await wifiService.fetchSnapshot(
        glassesIp,
        preset: "text_screen",
        aeLevel: -2,
      );
      camWatch.stop();
      metrics = metrics.copyWith(cameraCaptureMs: camWatch.elapsedMilliseconds);
      if (imageBytes == null) cameraFetchFailed = true;
    }

    final contentList = <Map<String, dynamic>>[];
    var promptToSend = userPrompt;
    final workOrder = config.workOrderId.trim();
    if (workOrder.isNotEmpty) {
      promptToSend = "Orden de trabajo: $workOrder\n$promptToSend";
    }
    if (cameraFetchFailed && glassesIp != null) {
      promptToSend +=
          "\n[Nota del sistema: la cámara no entregó fotograma; responde con lo conocido o pide repetir la captura].";
    }

    final isGeminiNative = config.apiBaseUrl.contains("generativelanguage.googleapis.com");
    final String endpointUrl;
    final Map<String, String> headers;
    final Map<String, dynamic> requestPayload;

    if (isGeminiNative) {
      // Formato Nativo de Google Gemini API (gemini-3.5-flash-lite, gemini-2.0-flash, etc.)
      final modelClean = config.modelName.trim().isNotEmpty ? config.modelName.trim() : "gemini-3.5-flash-lite";
      var base = config.apiBaseUrl.trim();
      if (base.endsWith('/')) base = base.substring(0, base.length - 1);
      
      if (base.contains(':generateContent')) {
        endpointUrl = base;
      } else if (base.contains('/models/')) {
        endpointUrl = "$base:generateContent";
      } else {
        endpointUrl = "$base/models/$modelClean:generateContent";
      }

      headers = {
        "Content-Type": "application/json",
        "X-goog-api-key": config.apiKey,
      };

      final parts = <Map<String, dynamic>>[
        {"text": promptToSend}
      ];

      if (imageBytes != null) {
        parts.add({
          "inline_data": {
            "mime_type": "image/jpeg",
            "data": base64Encode(imageBytes)
          }
        });
      }

      requestPayload = {
        "system_instruction": {
          "parts": [
            {"text": config.systemPrompt}
          ]
        },
        "contents": [
          {
            "role": "user",
            "parts": parts,
          }
        ],
        "generationConfig": {
          "temperature": 0.2,
          "maxOutputTokens": 600,
        }
      };
    } else {
      // Formato Estándar OpenAI / IAPymex vLLM / Ollama
      contentList.add({"type": "text", "text": promptToSend});

      if (imageBytes != null) {
        contentList.add({
          "type": "image_url",
          "image_url": {
            "url": "data:image/jpeg;base64,${base64Encode(imageBytes)}",
            "detail": "high"
          }
        });
      }

      requestPayload = {
        "model": config.modelName,
        "messages": [
          {"role": "system", "content": config.systemPrompt},
          {"role": "user", "content": contentList}
        ],
        "max_tokens": 400,
        "temperature": 0.2
      };

      endpointUrl = "${config.apiBaseUrl}${ApiConstants.chatCompletionsEndpoint}";
      headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${config.apiKey}"
      };
    }

    final requestJson = jsonEncode(requestPayload);
    final curlCommand = CurlBuilder.chatCompletions(
      endpointUrl: endpointUrl,
      apiKey: config.apiKey,
      requestJson: requestJson,
    );

    final llmWatch = Stopwatch()..start();
    Map<String, dynamic> responseJson = {};
    var assistantText = "Sin respuesta del modelo.";

    try {
      final response = await _client.post(
        Uri.parse(endpointUrl),
        headers: headers,
        body: requestJson,
      ).timeout(const Duration(seconds: 25));
      llmWatch.stop();
      metrics = metrics.copyWith(llmLatencyMs: llmWatch.elapsedMilliseconds);

      if (response.statusCode == 200) {
        responseJson = jsonDecode(utf8.decode(response.bodyBytes));
        if (isGeminiNative) {
          final candidates = responseJson["candidates"] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]["content"];
            final partsList = content?["parts"] as List?;
            if (partsList != null && partsList.isNotEmpty) {
              assistantText = partsList[0]["text"] ?? assistantText;
            }
          }
        } else {
          assistantText = responseJson["choices"]?[0]?["message"]?["content"] ?? assistantText;
        }
      } else {
        assistantText = "Error del servidor (${response.statusCode}). Revisa endpoint y API key en Config IA.";
        responseJson = {"error": response.body, "statusCode": response.statusCode};
      }
    } catch (e) {
      llmWatch.stop();
      metrics = metrics.copyWith(llmLatencyMs: llmWatch.elapsedMilliseconds);
      assistantText = "Sin conexión con el endpoint de IA. Verifica red y URL base.";
      responseJson = {"exception": e.toString()};
    }

    // TTS compatible OpenAI + Gemini: antes exigía "choices" y con Gemini
    // (candidates) jamás sonaba. Ahora suena si el LLM respondió OK.
    final llmOk = !responseJson.containsKey("error") &&
        !responseJson.containsKey("exception") &&
        assistantText.isNotEmpty &&
        !assistantText.startsWith("Sin conexión") &&
        !assistantText.startsWith("Error del servidor") &&
        assistantText != "Sin respuesta del modelo.";
    if (config.enableTtsPlayback && llmOk && config.ttsMode != 'off') {
      if (config.ttsMode == 'system') {
        await _speakWithSystemTts(assistantText, config, glassesIp, (m) {
          metrics = metrics.copyWith(
            ttsMs: m.ttsMs,
            glassesAudioTransferMs: m.glassesAudioTransferMs,
            audioFallbackToPhone: m.audioFallbackToPhone,
          );
        });
      } else {
        final ttsWatch = Stopwatch()..start();
        final ttsAudioBytes = await _synthesizeSpeech(assistantText, config);
        ttsWatch.stop();
        metrics = metrics.copyWith(ttsMs: ttsWatch.elapsedMilliseconds);

        if (ttsAudioBytes != null) {
          final pcm16k = AudioResample.prepareGlassesPcm(ttsAudioBytes);
          var playedOnGlasses = false;
          if (glassesIp != null && glassesIp.isNotEmpty) {
            final spkWatch = Stopwatch()..start();
            final wifiService = ref.read(wifiSyncServiceProvider);
            playedOnGlasses = await wifiService.sendAudioToGlasses(glassesIp, pcm16k);
            spkWatch.stop();
            metrics = metrics.copyWith(glassesAudioTransferMs: spkWatch.elapsedMilliseconds);
          }
          if (!playedOnGlasses) {
            final ok = await _playback.playPcm16(pcm16k, sampleRate: 16000);
            metrics = metrics.copyWith(audioFallbackToPhone: ok);
          }
        }
      }
    }

    totalStopwatch.stop();
    metrics = metrics.copyWith(totalRoundTripMs: totalStopwatch.elapsedMilliseconds);

    return AiInteractionResult(
      userQuery: userPrompt,
      assistantResponse: assistantText,
      metrics: metrics,
      rawRequestPayload: requestPayload,
      rawResponsePayload: responseJson,
      generatedCurl: curlCommand,
      timestamp: DateTime.now(),
      cameraMissing: cameraFetchFailed,
    );
  }

  Future<String?> transcribeFile(File wavFile) async {
    final config = ref.read(appConfigProvider);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse("${config.apiBaseUrl}${ApiConstants.transcriptionsEndpoint}"),
      );
      request.headers['Authorization'] = 'Bearer ${config.apiKey}';
      request.fields['model'] = 'whisper-1';
      request.fields['language'] = 'es';
      request.files.add(await http.MultipartFile.fromPath('file', wavFile.path));
      final streamed = await request.send().timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['text'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// TTS en dispositivo (gratis, es-ES): sintetiza a WAV, lo convierte a
  /// PCM 16 kHz y lo envía a las gafas; si no hay gafas o falla el envío,
  /// reproduce directo en el teléfono con el motor del sistema.
  Future<void> _speakWithSystemTts(
    String text,
    AppConfigState config,
    String? glassesIp,
    void Function(AiPipelineMetrics) save,
  ) async {
    var metrics = AiPipelineMetrics();
    final ttsWatch = Stopwatch()..start();
    try {
      await _localTts.ensureReady(
        voiceName: config.ttsVoiceName,
        speechRate: config.ttsRate,
        pitch: config.ttsPitch,
        volume: config.ttsVolume,
      );
      final wav = await _localTts.synthesizeToWavFile(text);
      ttsWatch.stop();
      metrics = metrics.copyWith(ttsMs: ttsWatch.elapsedMilliseconds);
      if (wav != null && wav.length > 44) {
        final parsed = _pcm16kFromWav(wav);
        if (parsed != null && parsed.isNotEmpty) {
          var playedOnGlasses = false;
          if (glassesIp != null && glassesIp.isNotEmpty) {
            final spkWatch = Stopwatch()..start();
            final wifiService = ref.read(wifiSyncServiceProvider);
            playedOnGlasses = await wifiService.sendAudioToGlasses(glassesIp, parsed);
            spkWatch.stop();
            metrics = metrics.copyWith(glassesAudioTransferMs: spkWatch.elapsedMilliseconds);
          }
          if (!playedOnGlasses) {
            // Reproducir el WAV original en el teléfono (mejor calidad que re-sintetizar).
            await _localTts.speak(text);
            metrics = metrics.copyWith(audioFallbackToPhone: true);
          }
          save(metrics);
          return;
        }
      }
      // Sin WAV (p.ej. iOS): habla directa en el teléfono.
      await _localTts.speak(text);
      metrics = metrics.copyWith(audioFallbackToPhone: true);
      save(metrics);
    } catch (_) {
      ttsWatch.stop();
      save(metrics.copyWith(ttsMs: ttsWatch.elapsedMilliseconds));
    }
  }

  /// Extrae PCM mono y lo deja en 16 kHz s16le leyendo la cabecera WAV.
  Uint8List? _pcm16kFromWav(Uint8List wav) {
    try {
      if (wav.length < 44) return null;
      final data = ByteData.sublistView(wav);
      int dataStart = 44;
      // Buscar chunk "data" por si hay chunks extra (LIST, etc).
      for (var i = 12; i < wav.length - 8; i++) {
        if (wav[i] == 0x64 && wav[i + 1] == 0x61 && wav[i + 2] == 0x74 && wav[i + 3] == 0x61) {
          dataStart = i + 8;
          break;
        }
      }
      final sampleRate = data.getUint32(24, Endian.little);
      final bitsPerSample = data.getUint16(34, Endian.little);
      final numChannels = data.getUint16(22, Endian.little);
      var pcm = wav.sublist(dataStart);
      if (pcm.length % 2 != 0) pcm = pcm.sublist(0, pcm.length - 1);
      // 8-bit unsigned -> s16.
      if (bitsPerSample == 8) {
        final out = Int16List(pcm.length);
        for (var i = 0; i < pcm.length; i++) {
          out[i] = ((pcm[i] - 128) * 256).clamp(-32768, 32767);
        }
        pcm = AudioResample.int16ToBytes(out);
      }
      // Estéreo -> mono (promedio).
      if (numChannels > 1) {
        final s = AudioResample.asInt16(pcm);
        final mono = Int16List(s.length ~/ numChannels);
        for (var i = 0; i < mono.length; i++) {
          var acc = 0;
          for (var c = 0; c < numChannels; c++) {
            acc += s[i * numChannels + c];
          }
          mono[i] = (acc ~/ numChannels).clamp(-32768, 32767);
        }
        pcm = AudioResample.int16ToBytes(mono);
      }
      final fromRate = (sampleRate >= 8000 && sampleRate <= 96000) ? sampleRate : 22050;
      return AudioResample.prepareGlassesPcm(pcm, sourceRate: fromRate);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _synthesizeSpeech(String text, AppConfigState config) async {
    try {
      final response = await _client.post(
        Uri.parse("${config.apiBaseUrl}${ApiConstants.speechEndpoint}"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${config.apiKey}"
        },
        body: jsonEncode({
          "model": "tts-1",
          "input": text,
          "voice": "alloy",
          "response_format": "pcm"
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) return response.bodyBytes;
      return null;
    } catch (_) {
      return null;
    }
  }
}

final aiServiceProvider = Provider<AiService>((ref) {
  return AiService(ref);
});
