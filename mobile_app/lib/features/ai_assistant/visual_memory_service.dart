import '../../core/utils/text_normalize.dart';

/// V57 - MEMORIA VISUAL (timeline de observaciones).
///
/// Port de la lógica de la app Kotlin que funciona. Corrige el fallo de
/// "memoria visual mezclada" (disco/estatua, escenas distintas) separando
/// claramente:
///   - la descripción del frame ACTUAL (prioridad máxima), y
///   - la memoria cronológica de lo visto antes (solo como apoyo).
///
/// Es solo texto (sin imágenes), con tope de longitud y deduplicación por
/// contenido, para no arrastrar objetos antiguos como si fueran actuales.
class VisualMemoryService {
  /// Entrada de memoria: "[HH:MM:SS] VISTO: <descripción>".
  static final RegExp _entrySplit = RegExp(r'\n(?=\[\d{2}:\d{2}:\d{2}\] VISTO:)');

  static String normalize(String text) => normalizeWearableText(text);

  /// ¿La observación merece conservarse? Descarta paredes vacías y oclusión.
  static bool worthKeeping(String text) {
    final q = normalize(text);
    if (q.isEmpty || q == 'no change') return false;
    // Oclusión explícita: no desplazar recuerdos por una cámara tapada.
    if (RegExp(
      r'(?:camara|objetivo|vision).{0,35}(?:bloquead|tapad)'
      r'|(?:hombro|espalda).{0,45}(?:bloquea|ocupa casi)'
      r'|vista.{0,35}dominada.{0,60}(?:silueta|hombro|espalda)',
    ).hasMatch(q.substring(0, q.length > 250 ? 250 : q.length))) {
      return false;
    }
    // Pared blanca/lisa/vacía sola no aporta.
    if (RegExp(
      r'^(?:solo (?:se ve|veo|hay) |(?:se ve|veo|hay) )?(?:una )?pared(?: blanca| lisa| vacia)?\$',
    ).hasMatch(q)) {
      return false;
    }
    return true;
  }

  /// Compacta a un máximo de [maxChars] cortando en palabra.
  static String compact(String text, {int maxChars = 1200}) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= maxChars) return clean;
    var cut = clean.substring(0, maxChars);
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace > 0) cut = cut.substring(0, lastSpace);
    return '$cut…';
  }

  /// Lista de entradas de la memoria.
  static List<String> entries(String memory) => memory
      .split(_entrySplit)
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// Añade una observación con marca de tiempo, deduplicando por contenido.
  static String append(String memory, String observation, String stamp) {
    if (!worthKeeping(observation)) return memory;
    final compacted = compact(observation);
    final key = normalize(compacted);
    final existing = entries(memory)
        .where((e) => normalize(substringAfter(e, 'VISTO: ', missingValue: e)) != key)
        .toList();
    existing.add('[$stamp] VISTO: $compacted');
    // Tope de longitud: eliminar entradas completas al superar el límite.
    while (existing.length > 1 &&
        existing.fold<int>(0, (s, e) => s + e.length + 1) > 16000) {
      existing.removeAt(0);
    }
    return existing.join('\n');
  }

  /// Selecciona las entradas más relevantes para la pregunta (por solapamiento
  /// de palabras), con tope de caracteres.
  static String select(String question, String memory, {int maxChars = 9000}) {
    const ignored = {
      'antes', 'viste', 'hablame', 'sobre', 'quiero', 'puedes', 'ensene',
      'posterior', 'ahora', 'aquel', 'aquella', 'otra', 'hace', 'falta', 'mires',
    };
    final words = normalize(question)
        .split(' ')
        .where((w) => w.length >= 4 && !ignored.contains(w))
        .toList();
    final entriesList = entries(memory);

    // (índice, entrada, nº de palabras de la pregunta presentes)
    final ranked = [
      for (var i = 0; i < entriesList.length; i++)
        (i, entriesList[i],
            words.where((w) => normalize(entriesList[i]).contains(w)).length),
    ]..sort((a, b) {
      if (b.$3 != a.$3) return b.$3.compareTo(a.$3);
      return b.$1.compareTo(a.$1); // más reciente primero en empate
    });

    final selected = <String>[];
    var chars = 0;
    for (final (_, entry, _) in ranked) {
      if (chars + entry.length + 1 > maxChars) continue;
      selected.add(entry);
      chars += entry.length + 1;
    }
    return selected.join('\n');
  }

  /// ¿La pregunta depende de la escena visible AHORA (necesita frame nuevo)?
  static bool needsCurrentFrame(String question) {
    final q = normalize(question);
    return RegExp(
      r'\b(?:que (?:ves|estas viendo|pone|dice aqui|color|objeto|tengo delante)'
      r'|que (?:es|son) (?:esto|eso|este|esta|ese|esa)'
      r'|de que color|lee (?:esto|eso|aqui)|describe (?:esto|lo que ves)'
      r'|mira (?:esto|aqui|ahora)|identifica (?:esto|este|esta)'
      r'|(?:que|cual) (?:album|disco) es)\b',
    ).hasMatch(q);
  }

  /// ¿La pregunta pide una inspección visual FINA del frame actual?
  static bool isDetailedCurrentVisualQuestion(String question) {
    final q = normalize(question);
    return RegExp(
      r'\b(?:que (?:ves|estas viendo|hay ahi|hay aqui|pone|dice ahi|dice aqui)'
      r'|que (?:es|son) (?:esto|eso|este|esta|ese|esa|aquello)'
      r'|cual es (?:esto|eso|este|esta)'
      r'|lee (?:esto|eso|aqui|ahi)|identifica (?:esto|eso|este|esta)'
      r'|mira (?:esto|eso|aqui|ahi)'
      r'|(?:que|cual) (?:album|disco|monumento|estatua|edificio|cuadro|objeto) (?:es|ves))\b',
    ).hasMatch(q);
  }

  /// ¿La pregunta se refiere a algo visto ANTES (usar memoria, no frame nuevo)?
  static bool shouldUseVisualMemory(String question) {
    final q = normalize(question);
    final currentView = RegExp(
      r'\b(?:mira(?:lo)?|enfoca(?:lo)?|observa(?:lo)?|ves|viendo)\s+(?:ahora|de nuevo|otra vez)\b',
    ).hasMatch(q);
    final noNewLook = RegExp(
      r'\b(?:no hace falta que (?:lo |la )?mires|sin (?:volver a )?mirar|no (?:lo |la )?mires)\b',
    ).hasMatch(q);
    if (currentView && !noNewLook) return false;
    return noNewLook ||
        RegExp(
          r'\b(?:viste|vimos|vimos antes|habias visto|has visto antes|te ensene|te mostre|recuerdas|recuerda|lo anterior|de antes|que viste antes)\b',
        ).hasMatch(q);
  }

  /// Razón de la decisión visual (para diagnóstico y prompt):
  ///  - "current:..." -> depende de la escena visible ahora.
  ///  - "memory:..."  -> usar memoria visual.
  ///  - "skip:..."    -> no requiere imagen.
  static String decisionReason(String question, String memory) {
    if (shouldUseVisualMemory(question)) return "memory:explicit_past_reference";
    final explicitNow =
        RegExp(r'\b(?:ahora|delante|aqui|en esta imagen|en esta foto)\b').hasMatch(normalize(question));
    final rememberedObject = RegExp(
      r'\b(?:ese|esa|aquel|aquella)\s+\w+|\b(?:disco|poster|objeto) que te ensene\b',
    ).hasMatch(normalize(question));
    if (rememberedObject && !explicitNow && memory.trim().isNotEmpty) {
      return "memory:previous_object_reference";
    }
    if (needsCurrentFrame(question)) {
      return "current:question_depends_on_visible_scene";
    }
    return "skip:conversation_does_not_require_current_image";
  }
}
