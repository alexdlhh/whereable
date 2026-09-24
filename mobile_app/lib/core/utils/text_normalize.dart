/// V57 - Normalización de texto para comparar intenciones.
/// Minúsculas, sin acentos, sin puntuación, espacios colapsados.
/// Se usa en la decisión de búsqueda web y en la memoria visual para que
/// ambas compartan exactamente la misma normalización.
String normalizeWearableText(String text) {
  var t = text.toLowerCase();
  t = t
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
  t = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

/// Equivalente en Dart de `substringAfter` (Kotlin): devuelve el texto tras la
/// primera aparición de [delimiter], o [missingValue] si no aparece.
String substringAfter(String source, String delimiter, {String missingValue = ''}) {
  final idx = source.indexOf(delimiter);
  if (idx < 0) return missingValue;
  return source.substring(idx + delimiter.length);
}
