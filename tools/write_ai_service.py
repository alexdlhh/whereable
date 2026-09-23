# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(__file__).resolve().parents[1] / "mobile_app" / "lib" / "features" / "ai_assistant" / "ai_service.dart"
p.write_text(r'''import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/config/app_config_provider.dart';
import '../../core/utils/curl_builder.dart';
import '../../core/utils/audio_resample.dart';
import '../../core/audio/phone_playback.dart';
import 'models/ai_response_model.dart';
import 'mock_responses.dart';
import '../connectivity/wifi_sync_service.dart';

class AiService {
  AiService(this.ref, {http.Client? client, PhonePlayback? playback})
      : _client = client ?? http.Client(),
        _playback = playback ?? PhonePlayback();

  final Ref ref;
  final http.Client _client;
  final PhonePlayback _playback;

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
      imageBytes = await wifiService.fetchSnapshot(glassesIp);
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

    final requestPayload = {
      "model": config.modelName,
      "messages": [
        {"role": "system", "content": config.systemPrompt},
        {"role": "user", "content": contentList}
      ],
      "max_tokens": 400,
      "temperature": 0.2
    };

    final requestJson = jsonEncode(requestPayload);
    final endpointUrl = "${config.apiBaseUrl}${ApiConstants.chatCompletionsEndpoint}";
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
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${config.apiKey}"
        },
        body: requestJson,
      ).timeout(const Duration(seconds: 25));
      llmWatch.stop();
      metrics = metrics.copyWith(llmLatencyMs: llmWatch.elapsedMilliseconds);

      if (response.statusCode == 200) {
        responseJson = jsonDecode(utf8.decode(response.bodyBytes));
        assistantText = responseJson["choices"]?[0]?["message"]?["content"] ?? assistantText;
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

    if (config.enableTtsPlayback && responseJson.containsKey("choices")) {
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
'''.replace('\r\n', '\n'), encoding='utf-8')
print('wrote ai_service.dart')
