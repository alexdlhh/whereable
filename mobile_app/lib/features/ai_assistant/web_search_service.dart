import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/utils/text_normalize.dart';

/// V57 - BÚSQUEDA WEB (Tavily) + decisión local.
///
/// Port de la lógica que funciona en la app Kotlin (MainActivity.kt):
///  - [webDecisionReason] decide SI buscar y por qué (sin tocar audio ni cámara).
///  - [wearableSearchQuery] construye la consulta DESDE la descripción visual de
///    la cámara, nunca desde frases literales tipo "busca por internet".
///  - [answerRequestsWebFallback] / [answerStillUncertainAfterWeb] detectan que la
///    IA admite que no sabe, para disparar el reintento automático.
///  - [refinedVisualWebQuery] construye la segunda búsqueda afinada usando SOLO
///    la descripción visual actual (sin memoria antigua).
///
/// No altera audio, escucha, TTS ni la conexión con el XIAO.
class WebSearchService {
  WebSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _endpoint = "https://api.tavily.com/search";

  /// Normaliza texto para comparar intenciones (compartido con memoria visual).
  static String normalize(String text) => normalizeWearableText(text);

  /// ¿El usuario pidió explícitamente NO buscar en internet?
  static bool declinesWebSearch(String question) {
    final q = normalize(question);
    return RegExp(
      r'\b(?:no\s+(?:(?:quiero|necesito|hace falta)\s+(?:que\s+)?)?'
      r'(?:busques|buscar|buscarlo|busca|consultes|consultar|uses|usar)'
      r'|sin\s+(?:buscar|buscarlo|consultar|usar))\s+(?:(?:en|por)\s+)?'
      r'(?:internet|la web|la red|google)\b',
    ).hasMatch(q);
  }

  /// ¿Hay una petición explícita de usar internet?
  static bool hasExplicitWebRequest(String question) {
    final q = normalize(question);
    final online = RegExp(r'\b(?:internet|web|google)\b').hasMatch(q);
    final action = RegExp(
      r'\b(?:busca\w*|busque\w*|consulta\w*|consulte\w*|mira\w*|mire\w*|comprueba\w*|verifica\w*)\b',
    ).hasMatch(q);
    final identifyAlbum = RegExp(
      r'\b(?:mira|busca|averigua|consulta)\s+(?:que|cual)\s+(?:album|disco)\s+es\b',
    ).hasMatch(q);
    final information = RegExp(
      r'\b(?:busca|buscar|buscame|consulta)\s+informacion\b',
    ).hasMatch(q);
    return !declinesWebSearch(question) &&
        ((online && action) || identifyAlbum || information);
  }

  /// Devuelve la razón de la decisión web:
  ///  - "use:<motivo>"  -> hay que buscar.
  ///  - "skip:<motivo>" -> no hay que buscar.
  static String webDecisionReason(String question) {
    if (declinesWebSearch(question)) return "skip:explicit_web_opt_out";
    final trigger = webSearchTrigger(question);
    if (trigger != null) return "use:$trigger";
    return "skip:no_web_request_or_live_topic";
  }

  /// Devuelve el motivo de búsqueda o null si no procede.
  static String? webSearchTrigger(String question) {
    if (declinesWebSearch(question)) return null;
    if (hasExplicitWebRequest(question)) {
      return "explicit_search_or_identification_request";
    }
    final q = question.toLowerCase();

    // Peticiones explícitas de usar Internet.
    const explicit = [
      "busca en internet",
      "busca por internet",
      "buscalo en internet",
      "buscalo por internet",
      "busca informacion",
      "busca información",
      "mira en internet",
      "mira por internet",
      "miralo en internet",
      "consulta internet",
      "consulta en internet",
      "consulta por internet",
      "comprueba en internet",
      "comprueba por internet",
      "verifica en internet",
      "verifica por internet",
      "buscame",
    ];
    for (final e in explicit) {
      if (q.contains(e)) return "explicit_phrase=$e";
    }

    // Temas que por definición necesitan información actual.
    const liveTopics = [
      "noticias",
      "ultima hora",
      "ultimas noticias",
      "actualidad",
      "que esta pasando",
      "que pasa en",
      "meteorologia",
      "pronostico",
      "prevision del tiempo",
      "el tiempo en",
      "tiempo en",
      "temperatura actual",
      "trafico",
    ];
    for (final t in liveTopics) {
      if (q.contains(t)) return "live_topic=$t";
    }

    // Palabras de frescura + consulta informativa.
    const freshness = [
      "hoy",
      "ahora",
      "actualmente",
      "actual",
      "ultimo",
      "ultima",
      "reciente",
      "recientes",
      "esta semana",
      "este mes",
      "precio actual",
      "cotizacion",
    ];
    const informational = [
      "cual",
      "como",
      "donde",
      "precio",
      "noticia",
      "tiempo",
      "meteorologia",
      "trafico",
    ];
    String? freshWord;
    for (final f in freshness) {
      if (q.contains(f)) {
        freshWord = f;
        break;
      }
    }
    String? infoWord;
    for (final i in informational) {
      if (q.contains(i)) {
        infoWord = i;
        break;
      }
    }
    if (freshWord != null && infoWord != null) {
      return "freshness=$freshWord information=$infoWord";
    }
    return null;
  }

  /// Construye la consulta web DESDE la descripción visual de la cámara.
  /// Nunca envía literalmente "busca por internet" al buscador.
  static String wearableSearchQuery(String question, String visualText) {
    final q = normalize(question);

    // Orden genérica de búsqueda ("búscalo", "busca por internet", ...).
    final genericWebCommand = RegExp(
      r'^(?:busca|buscalo|buscar|buscarlo|buscando|miralo|mira|consulta|consultalo|comprueba|verifica)'
      r'(?:\s+(?:por|en)\s+(?:internet|web|la web|google))?\$',
    ).hasMatch(q);

    final needsObject = RegExp(
      r'\b(?:buscalo|buscarlo|ese|esa|esto|eso)\b|\b(?:que|cual) (?:album|disco) es\b',
    ).hasMatch(q);

    if (visualText.trim().isEmpty) return question;

    // La descripción visual suele venir con prefijo "VISTO: ".
    var visualObject = substringAfter(visualText, "VISTO: ", missingValue: visualText).trim();
    if (visualObject.length > 600) visualObject = visualObject.substring(0, 600);

    if (genericWebCommand) {
      return "Identifica en internet este objeto usando SOLO esta descripción visual: $visualObject";
    }

    if (!needsObject) return question;

    return "$question\nObjeto descrito por la cámara (sin identificar con certeza): $visualObject";
  }

  /// ¿La respuesta de la IA admite que no sabe / necesita datos actuales?
  static bool answerRequestsWebFallback(String answer) {
    final a = normalize(answer);
    if (a.isEmpty) return false;
    const signals = [
      "no se",
      "no lo se",
      "no puedo saber",
      "no puedo confirmar",
      "no puedo determinar",
      "no puedo identificar",
      "no puedo identificarlo",
      "no puedo reconocer",
      "no estoy seguro",
      "no estoy segura",
      "no queda claro",
      "no se distingue",
      "no se ve con claridad",
      "no es posible identificar",
      "no tengo informacion",
      "no tengo datos",
      "no dispongo de informacion",
      "no dispongo de datos",
      "no tengo acceso a informacion en tiempo real",
      "no tengo acceso a internet",
      "no puedo consultar internet",
      "no puedo consultar la web",
      "no puedo verificar",
      "no puedo comprobar",
      "necesitaria informacion actual",
      "necesitaria datos actuales",
      "necesito informacion actual",
      "necesito datos actuales",
      "para saberlo tendria que consultar",
      "te recomiendo consultar",
      "consulta la prensa",
      "consulta internet",
      "consulta la web",
    ];
    return signals.any(a.contains);
  }

  /// ¿Incluso con internet la IA sigue sin saberlo? (dispara reintento afinado).
  static bool answerStillUncertainAfterWeb(String answer) {
    final a = normalize(answer);
    if (a.isEmpty) return true;
    const signals = [
      "no se",
      "no lo se",
      "no puedo identificar",
      "no puedo determinar",
      "no puedo confirmar",
      "no estoy seguro",
      "no estoy segura",
      "no hay suficiente informacion",
      "no tengo suficiente informacion",
      "no hay datos suficientes",
      "no tengo datos suficientes",
      "no se puede identificar",
      "no es posible identificar",
      "no queda claro",
      "no se distingue",
      "no puedo reconocer",
    ];
    return signals.any(a.contains);
  }

  /// Segunda búsqueda afinada: SOLO la descripción visual actual, sin memoria.
  static String refinedVisualWebQuery(String question, String currentVisual) {
    final visual = currentVisual.trim().substring(
        0, currentVisual.trim().length > 1200 ? 1200 : currentVisual.trim().length);
    if (visual.isEmpty) return question;
    return "Identifica el objeto de la imagen actual. "
        "No uses contexto de imágenes anteriores. "
        "Usa únicamente estos rasgos visuales actuales y busca coincidencias concretas en internet. "
        "Si hay varias posibilidades, compáralas por postura, forma, material, texto visible, fondo y rasgos distintivos. "
        "Pregunta del usuario: $question\n"
        "Rasgos visuales actuales: $visual";
  }

  /// Ejecuta la búsqueda en Tavily y devuelve un texto formateado con
  /// resumen + fuentes, listo para inyectar como contexto web.
  Future<WebSearchResult> search(
    String apiKey,
    String query, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (apiKey.trim().isEmpty) {
      return WebSearchResult.fail("Falta API key de Tavily");
    }
    if (query.trim().isEmpty) {
      return WebSearchResult.fail("Consulta web vacía");
    }

    try {
      final body = jsonEncode({
        "query": query,
        "search_depth": "basic",
        "topic": "general",
        "max_results": 5,
        "include_answer": true,
        "include_raw_content": false,
        "include_images": false,
        "include_published_date": true,
        "language": "es",
      });

      final resp = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer ${apiKey.trim()}",
            },
            body: body,
          )
          .timeout(timeout);

      if (resp.statusCode < 200 || resp.statusCode > 299) {
        return WebSearchResult.fail("Tavily HTTP ${resp.statusCode}: ${resp.body.substring(0, resp.body.length > 800 ? 800 : resp.body.length)}");
      }

      final json = jsonDecode(utf8.decode(resp.bodyBytes));
      final answer = (json["answer"] ?? "").toString().trim();
      final results = json["results"];

      final buf = StringBuffer();
      if (answer.isNotEmpty) {
        buf.writeln("RESUMEN DE BÚSQUEDA:");
        buf.writeln(answer.substring(0, answer.length > 3500 ? 3500 : answer.length));
        buf.writeln();
      }
      if (results is List && results.isNotEmpty) {
        buf.writeln("FUENTES:");
        for (var i = 0; i < results.length && i < 5; i++) {
          final item = results[i];
          if (item is! Map) continue;
          final title = (item["title"] ?? "").toString().trim();
          final content = (item["content"] ?? "").toString().trim();
          final url = (item["url"] ?? "").toString().trim();
          final published = (item["published_date"] ?? "").toString().trim();
          buf.write("${i + 1}. ");
          if (title.isNotEmpty) buf.write(title);
          if (published.isNotEmpty) buf.write(" · $published");
          buf.writeln();
          if (content.isNotEmpty) {
            buf.writeln(content.substring(0, content.length > 1200 ? 1200 : content.length));
          }
          if (url.isNotEmpty) buf.writeln("URL: $url");
          buf.writeln();
        }
      }

      final formatted = buf.toString().trim();
      if (formatted.isEmpty) {
        return WebSearchResult.fail("Tavily no devolvió resultados útiles");
      }
      return WebSearchResult.ok(formatted);
    } catch (e) {
      return WebSearchResult.fail("Tavily: ${e.toString().substring(0, e.toString().length > 400 ? 400 : e.toString().length)}");
    }
  }
}

class WebSearchResult {
  final bool success;
  final String text;
  final String error;

  const WebSearchResult._(this.success, this.text, this.error);

  factory WebSearchResult.ok(String text) => WebSearchResult._(true, text, "");
  factory WebSearchResult.fail(String error) => WebSearchResult._(false, "", error);
}
