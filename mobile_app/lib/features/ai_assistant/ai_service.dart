import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/api_constants.dart';
import '../../core/config/app_config_provider.dart';
import '../../core/utils/curl_builder.dart';
import '../../core/utils/audio_resample.dart';
import '../../core/audio/phone_playback.dart';
import '../../core/audio/local_tts_service.dart';
import 'models/ai_response_model.dart';
import 'mock_responses.dart';
import 'web_search_service.dart';
import 'visual_memory_service.dart';
import '../connectivity/wifi_sync_service.dart';

/// Resultado de una llamada al LLM (texto + metadatos para diagnóstico).
class _LlmCall {
  final String text;
  final bool ok;
  final Map<String, dynamic> responseJson;
  final Map<String, dynamic> payload;
  final String curl;
  final int latencyMs;
  _LlmCall({
    required this.text,
    required this.ok,
    required this.responseJson,
    required this.payload,
    required this.curl,
    required this.latencyMs,
  });
}

class AiService {
  AiService(this.ref, {http.Client? client, PhonePlayback? playback, LocalTtsService? localTts})
      : _client = client ?? http.Client(),
        // Usa la instancia compartida del provider para que TTS y barge-in
        // controlen el mismo reproductor global.
        _playback = playback ?? ref.read(phonePlaybackProvider),
        _localTts = localTts ?? LocalTtsService(),
        _webSearch = WebSearchService(client: client);

  final Ref ref;
  final http.Client _client;
  final PhonePlayback _playback;
  final LocalTtsService _localTts;
  final WebSearchService _webSearch;

  static const _kVisualMemoryKey = 'visual_timeline_memory';

  Future<String> _loadVisualMemory() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(_kVisualMemoryKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _saveVisualMemory(String memory) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kVisualMemoryKey, memory);
    } catch (_) {}
  }

  String _nowStamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

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

    // =====================================================
    // V57 PIPELINE: visión → descripción → consulta web → reintento
    // No toca audio, escucha, TTS ni la conexión con el XIAO.
    // =====================================================

    // 1) Fotograma (se captura bajo demanda; si ya viene, se reutiliza).
    Uint8List? imageBytes = directImageBytes;
    var cameraFetchFailed = false;
    if (imageBytes == null && glassesIp != null && glassesIp.isNotEmpty) {
      final camWatch = Stopwatch()..start();
      final wifiService = ref.read(wifiSyncServiceProvider);
      imageBytes = await wifiService.fetchSnapshot(
        glassesIp,
        preset: "text_screen",
        aeLevel: -2,
      );
      camWatch.stop();
      metrics = metrics.copyWith(cameraCaptureMs: camWatch.elapsedMilliseconds);
      if (imageBytes == null) cameraFetchFailed = true;
    }

    // 2) Decisión visual: ¿depende de la escena actual, de la memoria, o no requiere imagen?
    final visualMemory = await _loadVisualMemory();
    final visualReason = VisualMemoryService.decisionReason(userPrompt, visualMemory);
    final needsCurrentFrame = visualReason.startsWith("current:");
    final useVisualMemory = visualReason.startsWith("memory:");
    final detailedVisualQuestion =
        needsCurrentFrame && VisualMemoryService.isDetailedCurrentVisualQuestion(userPrompt);
    final rememberedVisual =
        VisualMemoryService.select(userPrompt, visualMemory);

    // 3) Descripción visual del frame ACTUAL (anti-alucinación), solo si hace falta.
    var currentFrameDescription = "";
    if (needsCurrentFrame && imageBytes != null && imageBytes.isNotEmpty) {
      final vision = await _describeVision(
        config,
        imageBytes,
        detailed: detailedVisualQuestion,
        userQuestion: userPrompt,
      );
      if (vision.ok && vision.text.trim().isNotEmpty && vision.text.trim() != "NO_CHANGE") {
        currentFrameDescription = VisualMemoryService.compact(vision.text);
        // Actualizar la memoria cronológica (deduplicada, con tope).
        final updated = VisualMemoryService.append(
          visualMemory,
          currentFrameDescription,
          _nowStamp(),
        );
        if (updated != visualMemory) {
          await _saveVisualMemory(updated);
        }
      }
    }

    // 4) Decisión de búsqueda web + consulta construida DESDE la descripción visual.
    var webContext = "";
    var webRequested = false;
    var webQuery = "";
    if (config.enableWebSearch) {
      final webReason = WebSearchService.webDecisionReason(userPrompt);
      webRequested = webReason.startsWith("use:");
      webQuery = WebSearchService.wearableSearchQuery(
        userPrompt,
        needsCurrentFrame ? currentFrameDescription : rememberedVisual,
      );
      if (webRequested) {
        if (config.tavilyApiKey.trim().isEmpty) {
          webContext =
              "BÚSQUEDA WEB NO DISPONIBLE: falta configurar la API key de Tavily. No se han consultado fuentes.";
        } else {
          final web = await _webSearch.search(config.tavilyApiKey, webQuery);
          webContext = web.success
              ? web.text
              : "BÚSQUEDA WEB NO DISPONIBLE: ${web.error}";
        }
      }
    }

    // 5) Contexto de memoria (conversación + visual) para la pregunta actual.
    final memoryBlock = _buildMemoryBlock(
      question: userPrompt,
      visualMemory: visualMemory,
      visualReason: visualReason,
      detailedVisualQuestion: detailedVisualQuestion,
      currentFrameDescription: currentFrameDescription,
      useVisualMemory: useVisualMemory,
      needsCurrentFrame: needsCurrentFrame,
    );

    // 6) Pregunta al LLM (respuesta principal).
    var answer = await _askAnswer(
      config: config,
      userText: userPrompt,
      visualContext: currentFrameDescription,
      webContext: webContext,
      memory: memoryBlock,
      imageBytes: (needsCurrentFrame && imageBytes != null) ? imageBytes : null,
    );

    // 7) REINTENTO AUTOMÁTICO: si la IA admite que no sabe y aún no se buscó,
    //    buscamos en internet y repetimos la MISMA pregunta.
    if (answer.ok &&
        !webRequested &&
        config.enableWebSearch &&
        !WebSearchService.declinesWebSearch(userPrompt) &&
        WebSearchService.answerRequestsWebFallback(answer.text)) {
      if (config.tavilyApiKey.trim().isNotEmpty) {
        final fallbackWeb = await _webSearch.search(config.tavilyApiKey, webQuery);
        if (fallbackWeb.success && fallbackWeb.text.trim().isNotEmpty) {
          webContext = fallbackWeb.text;
          final webAnswer = await _askAnswer(
            config: config,
            userText: userPrompt,
            visualContext: currentFrameDescription,
            webContext: webContext,
            memory: memoryBlock,
            imageBytes: (needsCurrentFrame && imageBytes != null) ? imageBytes : null,
          );
          if (webAnswer.ok && webAnswer.text.trim().isNotEmpty) {
            answer = webAnswer;

            // 8) REINTENTO AFINADO: si incluso con internet sigue sin saberlo,
            //    segunda búsqueda usando SOLO la descripción visual actual.
            if (WebSearchService.answerStillUncertainAfterWeb(answer.text)) {
              final refinedQuery =
                  WebSearchService.refinedVisualWebQuery(userPrompt, currentFrameDescription);
              final refinedWeb = await _webSearch.search(config.tavilyApiKey, refinedQuery);
              if (refinedWeb.success && refinedWeb.text.trim().isNotEmpty) {
                final refinedAnswer = await _askAnswer(
                  config: config,
                  userText: userPrompt,
                  visualContext: currentFrameDescription,
                  webContext: refinedWeb.text,
                  memory: "", // sin memoria antigua para no mezclar escenas
                  imageBytes: (needsCurrentFrame && imageBytes != null) ? imageBytes : null,
                );
                if (refinedAnswer.ok && refinedAnswer.text.trim().isNotEmpty) {
                  answer = refinedAnswer;
                }
              }
            }
          }
        }
      }
    }

    // Resultado final (payload/curl de la última llamada = la respuesta).
    final assistantText = answer.ok && answer.text.trim().isNotEmpty
        ? answer.text
        : (answer.responseJson.containsKey("error")
            ? "Error del servidor. Revisa endpoint y API key en Config IA."
            : "Sin conexión con el endpoint de IA. Verifica red y URL base.");
    final responseJson = answer.responseJson;
    final requestPayload = answer.payload;
    final curlCommand = answer.curl;
    metrics = metrics.copyWith(llmLatencyMs: answer.latencyMs);

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

  // =====================================================
  // V57 - PROMPTS Y LLAMADAS AL LLM (visión + respuesta)
  // =====================================================

  /// Prompt de descripción de fondo (memoria visual silenciosa).
  String _backgroundVisionPrompt() =>
      "Eres la memoria visual silenciosa de un wearable. Describe de forma breve QUÉ ESTÁ VIENDO AHORA MISMO la cámara: objetos, aparatos, pantallas, personas sin identificar y el entorno visible.\n"
      "REGLA ANTI-ALUCINACIÓN:\n"
      "- Describe solo lo que realmente sea visible.\n"
      "- No inventes ni completes texto, títulos, marcas, nombres, artistas, discos, edificios, estatuas o modelos.\n"
      "- Si una identificación no es clara, usa una descripción genérica y marca la incertidumbre.\n"
      "- Si el texto está borroso o parcial, di que no es legible.\n"
      "- No arrastres una identificación antigua si la imagen actual no la confirma.\n"
      "Devuelve un contexto de la escena actual, máximo 1200 caracteres.";

  /// Prompt de inspección visual fina para una pregunta concreta.
  String _detailedVisionPrompt(String question) =>
      "Estás analizando la imagen ACTUAL de la cámara de un wearable para contestar esta pregunta concreta: \"$question\".\n"
      "Haz una inspección visual cuidadosa. Prioriza aquello a lo que parece referirse la pregunta.\n"
      "Lee únicamente el texto REALMENTE legible: nombres, títulos, carteles, etiquetas, portadas, matrículas.\n"
      "REGLA ESTRICTA ANTI-ALUCINACIÓN:\n"
      "- No completes letras, títulos, marcas, nombres, artistas, discos, edificios, estatuas ni modelos a partir de una impresión parcial.\n"
      "- No conviertas una semejanza visual en una identificación.\n"
      "- No inventes texto que no pueda leerse con claridad.\n"
      "- Si el texto está borroso, cortado o ambiguo, indica \"texto no legible\".\n"
      "- Solo da un nombre concreto cuando haya evidencia visual clara y suficiente.\n"
      "- Si no puedes estar razonablemente seguro, responde que no puedes identificarlo con seguridad y describe solo los rasgos que sí ves.\n"
      "Máximo 1600 caracteres.";

  /// Describe el frame actual (anti-alucinación). Devuelve texto + ok.
  Future<_LlmCall> _describeVision(
    AppConfigState config,
    Uint8List jpeg, {
    bool detailed = false,
    String userQuestion = "",
  }) async {
    final isGeminiNative = config.backend != 'cerebras' &&
        config.apiBaseUrl.contains("generativelanguage.googleapis.com");
    final isCerebras = config.backend == 'cerebras';
    final instruction =
        detailed ? _detailedVisionPrompt(userQuestion) : _backgroundVisionPrompt();

    final String endpointUrl;
    final Map<String, String> headers;
    final Map<String, dynamic> requestPayload;

    if (isGeminiNative) {
      final modelClean =
          config.modelName.trim().isNotEmpty ? config.modelName.trim() : "gemini-3.5-flash-lite";
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
      requestPayload = {
        "contents": [
          {
            "role": "user",
            "parts": [
              {"text": instruction},
              {
                "inline_data": {
                  "mime_type": "image/jpeg",
                  "data": base64Encode(jpeg),
                }
              },
            ],
          },
        ],
        "generationConfig": {
          "temperature": 0.1,
          "maxOutputTokens": detailed ? 900 : 500,
        },
      };
    } else {
      final contentList = <Map<String, dynamic>>[
        {
          "type": "image_url",
          "image_url": {
            "url": "data:image/jpeg;base64,${base64Encode(jpeg)}",
            "detail": "high",
          },
        },
        {"type": "text", "text": instruction},
      ];
      final body = <String, dynamic>{
        "model": config.modelName,
        "messages": [
          {"role": "user", "content": contentList},
        ],
        "temperature": 0.1,
      };
      if (isCerebras) {
        body["reasoning_effort"] = "none";
        body["max_completion_tokens"] = detailed ? 900 : 500;
      } else {
        body["max_tokens"] = detailed ? 900 : 500;
      }
      requestPayload = body;
      endpointUrl = "${config.apiBaseUrl}${ApiConstants.chatCompletionsEndpoint}";
      headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${config.apiKey}",
      };
    }

    final requestJson = jsonEncode(requestPayload);
    final curl = CurlBuilder.chatCompletions(
      endpointUrl: endpointUrl,
      apiKey: config.apiKey,
      requestJson: requestJson,
    );

    final watch = Stopwatch()..start();
    try {
      final response = await _client
          .post(Uri.parse(endpointUrl), headers: headers, body: requestJson)
          .timeout(const Duration(seconds: 25));
      watch.stop();
      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        String text = "";
        if (isGeminiNative) {
          final candidates = json["candidates"] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]["content"];
            final partsList = content?["parts"] as List?;
            if (partsList != null && partsList.isNotEmpty) {
              text = (partsList[0]["text"] ?? "").toString();
            }
          }
        } else {
          final choices = json["choices"] as List?;
          if (choices != null && choices.isNotEmpty) {
            text = ((choices[0]["message"] ?? {})["content"] ?? "").toString();
          }
        }
        return _LlmCall(
          text: text.trim(),
          ok: text.trim().isNotEmpty,
          responseJson: json,
          payload: requestPayload,
          curl: curl,
          latencyMs: watch.elapsedMilliseconds,
        );
      }
      watch.stop();
      return _LlmCall(
        text: "",
        ok: false,
        responseJson: {"error": response.body, "statusCode": response.statusCode},
        payload: requestPayload,
        curl: curl,
        latencyMs: watch.elapsedMilliseconds,
      );
    } catch (e) {
      watch.stop();
      return _LlmCall(
        text: "",
        ok: false,
        responseJson: {"exception": e.toString()},
        payload: requestPayload,
        curl: curl,
        latencyMs: watch.elapsedMilliseconds,
      );
    }
  }

  /// Bloque de memoria (visual + decisión) para inyectar en la pregunta.
  String _buildMemoryBlock({
    required String question,
    required String visualMemory,
    required String visualReason,
    required bool detailedVisualQuestion,
    required String currentFrameDescription,
    required bool useVisualMemory,
    required bool needsCurrentFrame,
  }) {
    final buf = StringBuffer();
    final selectedVisual = VisualMemoryService.select(question, visualMemory);
    if (selectedVisual.trim().isNotEmpty) {
      buf.writeln("MEMORIA VISUAL RECIENTE:");
      buf.writeln(selectedVisual);
      buf.writeln();
    }
    buf.writeln("DECISIÓN VISUAL PARA ESTA PREGUNTA: $visualReason.");
    if (detailedVisualQuestion && currentFrameDescription.trim().isNotEmpty) {
      buf.writeln(
          "La descripción de cámara acaba de obtenerse con análisis visual detallado para esta pregunta. Usa nombres y texto legible del análisis para contestar de forma concreta, sin pedir aclaración sobre 'eso' o 'ahí' salvo que siga siendo realmente ambiguo.");
    }
    if (useVisualMemory) {
      buf.writeln("Responde usando lo recordado, no la escena actual.");
    }
    if (needsCurrentFrame && currentFrameDescription.trim().isEmpty) {
      buf.writeln(
          "No se ha podido analizar la imagen actual. No presentes recuerdos como una observación actual.");
    }
    return buf.toString().trim();
  }

  /// Prompt de usuario para la respuesta (pregunta + contexto).
  String _buildAnswerPrompt({
    required String userText,
    String visualContext = "",
    String webContext = "",
    String memory = "",
    String workOrder = "",
    bool cameraMissing = false,
  }) {
    final buf = StringBuffer();
    if (workOrder.trim().isNotEmpty) {
      buf.writeln("Orden de trabajo: ${workOrder.trim()}");
    }
    buf.writeln("PREGUNTA ACTUAL DEL USUARIO — PRIORIDAD MÁXIMA:");
    buf.writeln(userText);
    buf.writeln();
    if (memory.trim().isNotEmpty) {
      buf.writeln("CONTEXTO DE MEMORIA (conversación y visual) — SOLO COMO APOYO:");
      buf.writeln(memory);
      buf.writeln();
    }
    if (visualContext.trim().isNotEmpty) {
      buf.writeln(
          "DESCRIPCIÓN ACTUAL DE LA CÁMARA (uso interno; no la narres salvo que pregunten qué ves):");
      buf.writeln(visualContext);
      buf.writeln();
    }
    if (webContext.trim().isNotEmpty) {
      buf.writeln("RESULTADOS DE BÚSQUEDA WEB — úsalos solo si son relevantes:");
      buf.writeln(webContext);
      buf.writeln();
    }
    if (cameraMissing) {
      buf.writeln(
          "[Nota del sistema: la cámara no entregó fotograma; responde con lo conocido o pide repetir la captura.]");
    }
    buf.writeln(
        "INSTRUCCIÓN: contesta exactamente a la pregunta actual. No inventes detalles que no estén en la pregunta o en el contexto disponible.");
    return buf.toString().trim();
  }

  /// Llamada de respuesta al LLM (texto + imagen opcional + contexto).
  Future<_LlmCall> _askAnswer({
    required AppConfigState config,
    required String userText,
    String visualContext = "",
    String webContext = "",
    String memory = "",
    Uint8List? imageBytes,
    bool cameraMissing = false,
  }) async {
    final isGeminiNative = config.backend != 'cerebras' &&
        config.apiBaseUrl.contains("generativelanguage.googleapis.com");
    final isCerebras = config.backend == 'cerebras';

    final userPrompt = _buildAnswerPrompt(
      userText: userText,
      visualContext: visualContext,
      webContext: webContext,
      memory: memory,
      workOrder: config.workOrderId,
      cameraMissing: cameraMissing,
    );

    final String endpointUrl;
    final Map<String, String> headers;
    final Map<String, dynamic> requestPayload;

    if (isGeminiNative) {
      final modelClean =
          config.modelName.trim().isNotEmpty ? config.modelName.trim() : "gemini-3.5-flash-lite";
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
        {"text": userPrompt},
      ];
      if (imageBytes != null) {
        parts.add({
          "inline_data": {
            "mime_type": "image/jpeg",
            "data": base64Encode(imageBytes),
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
        },
      };
    } else {
      final contentList = <Map<String, dynamic>>[
        {"type": "text", "text": userPrompt},
      ];
      if (imageBytes != null) {
        contentList.add({
          "type": "image_url",
          "image_url": {
            "url": "data:image/jpeg;base64,${base64Encode(imageBytes)}",
            "detail": "high",
          }
        });
      }
      final body = <String, dynamic>{
        "model": config.modelName,
        "messages": [
          {"role": "system", "content": config.systemPrompt},
          {"role": "user", "content": contentList},
        ],
        "temperature": 0.2,
      };
      if (isCerebras) {
        body["reasoning_effort"] = "none";
        body["max_completion_tokens"] = 500;
      } else {
        body["max_tokens"] = 400;
      }
      requestPayload = body;
      endpointUrl = "${config.apiBaseUrl}${ApiConstants.chatCompletionsEndpoint}";
      headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${config.apiKey}",
      };
    }

    final requestJson = jsonEncode(requestPayload);
    final curl = CurlBuilder.chatCompletions(
      endpointUrl: endpointUrl,
      apiKey: config.apiKey,
      requestJson: requestJson,
    );

    final watch = Stopwatch()..start();
    try {
      final response = await _client
          .post(Uri.parse(endpointUrl), headers: headers, body: requestJson)
          .timeout(const Duration(seconds: 25));
      watch.stop();
      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        String text = "";
        if (isGeminiNative) {
          final candidates = json["candidates"] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]["content"];
            final partsList = content?["parts"] as List?;
            if (partsList != null && partsList.isNotEmpty) {
              text = (partsList[0]["text"] ?? "").toString();
            }
          }
        } else {
          final choices = json["choices"] as List?;
          if (choices != null && choices.isNotEmpty) {
            text = ((choices[0]["message"] ?? {})["content"] ?? "").toString();
          }
        }
        return _LlmCall(
          text: text.trim(),
          ok: text.trim().isNotEmpty,
          responseJson: json,
          payload: requestPayload,
          curl: curl,
          latencyMs: watch.elapsedMilliseconds,
        );
      }
      watch.stop();
      return _LlmCall(
        text: "",
        ok: false,
        responseJson: {"error": response.body, "statusCode": response.statusCode},
        payload: requestPayload,
        curl: curl,
        latencyMs: watch.elapsedMilliseconds,
      );
    } catch (e) {
      watch.stop();
      return _LlmCall(
        text: "",
        ok: false,
        responseJson: {"exception": e.toString()},
        payload: requestPayload,
        curl: curl,
        latencyMs: watch.elapsedMilliseconds,
      );
    }
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
