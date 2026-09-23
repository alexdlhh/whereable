/// Respuestas locales para modo simulador / demos de campo sin backend.
class MockResponses {
  static String forQuery(String query) {
    final q = query.toLowerCase();
    if (q.contains('serie') || q.contains('placa')) {
      return 'No leo un número de serie nítido en esta toma. Inclina la cabeza 10° hacia la luz, acerca 15 cm y vuelve a capturar la zona de la etiqueta o serigrafía.';
    }
    if (q.contains('fallo') || q.contains('quemadura') || q.contains('diagn')) {
      return 'Revisión visual sugerida: 1) Confirma alimentación desconectada. 2) Busca caps abombados, soldaduras frías y decoloración en pistas. 3) Si hay olor a quemado, no reenergices hasta aislar la etapa de potencia. ¿Quieres el procedimiento de desmontaje de esa zona?';
    }
    if (q.contains('desmont') || q.contains('paso')) {
      return 'Procedimiento seguro: 1) Corta tensión y espera condensadores. 2) Fotografía el cableado antes de desconectar. 3) Extrae tornillos exteriores en cruz. 4) Libera clips plásticos con púa, no con destornillador metálico. 5) No fuerces flex de cámara. Dime cuando tengas la siguiente vista.';
    }
    if (q.contains('componente') || q.contains('producto') || q.contains('viendo')) {
      return 'Simulador: identifico un conjunto electrónico compacto. En campo, nombra primero la placa o el módulo más grande, luego conectores y marcas. Captura perpendicular al texto para OCR de códigos.';
    }
    return 'Simulador activo: no hay backend. En producción analizaría la captura y te daría pasos cortos y seguros. Reformula o desactiva Mock en el HUD para usar tu endpoint real.';
  }
}
