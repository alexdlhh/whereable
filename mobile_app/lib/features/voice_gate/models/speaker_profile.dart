import 'dart:convert';
import 'dart:math';

/// Perfil biométrico de voz del usuario (técnico) autorizado.
/// Almacena el vector de embedding acústico generado por Sherpa-ONNX.
class SpeakerProfile {
  final String id;
  final String name;
  final DateTime enrolledAt;
  final List<double> embeddingVector;
  final int sampleCount;
  final double similarityThreshold;

  const SpeakerProfile({
    required this.id,
    required this.name,
    required this.enrolledAt,
    required this.embeddingVector,
    this.sampleCount = 1,
    this.similarityThreshold = 0.68,
  });

  bool get isEnrolled => embeddingVector.isNotEmpty;

  /// Calcula la similitud de coseno entre el embedding del usuario y un embedding nuevo.
  double computeCosineSimilarity(List<double> targetEmbedding) {
    if (embeddingVector.isEmpty || targetEmbedding.isEmpty) return 0.0;
    if (embeddingVector.length != targetEmbedding.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < embeddingVector.length; i++) {
      final a = embeddingVector[i];
      final b = targetEmbedding[i];
      dotProduct += a * b;
      normA += a * a;
      normB += b * b;
    }

    if (normA == 0.0 || normB == 0.0) return 0.0;
    final similarity = dotProduct / (sqrt(normA) * sqrt(normB));
    return similarity.clamp(0.0, 1.0);
  }

  /// Fusiona un nuevo embedding con el actual ponderando el número de muestras.
  SpeakerProfile withAddedSample(List<double> newEmbedding) {
    if (newEmbedding.isEmpty) return this;
    if (embeddingVector.isEmpty) {
      return copyWith(
        embeddingVector: List<double>.from(newEmbedding),
        sampleCount: 1,
        enrolledAt: DateTime.now(),
      );
    }

    final newCount = sampleCount + 1;
    final updatedVector = List<double>.generate(embeddingVector.length, (i) {
      final currentWeight = sampleCount.toDouble();
      final target = i < newEmbedding.length ? newEmbedding[i] : 0.0;
      return (embeddingVector[i] * currentWeight + target) / newCount;
    });

    return copyWith(
      embeddingVector: updatedVector,
      sampleCount: newCount,
    );
  }

  SpeakerProfile copyWith({
    String? id,
    String? name,
    DateTime? enrolledAt,
    List<double>? embeddingVector,
    int? sampleCount,
    double? similarityThreshold,
  }) {
    return SpeakerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      enrolledAt: enrolledAt ?? this.enrolledAt,
      embeddingVector: embeddingVector ?? this.embeddingVector,
      sampleCount: sampleCount ?? this.sampleCount,
      similarityThreshold: similarityThreshold ?? this.similarityThreshold,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'enrolledAt': enrolledAt.toIso8601String(),
      'embeddingVector': embeddingVector,
      'sampleCount': sampleCount,
      'similarityThreshold': similarityThreshold,
    };
  }

  factory SpeakerProfile.fromMap(Map<String, dynamic> map) {
    return SpeakerProfile(
      id: map['id'] ?? 'tech_owner',
      name: map['name'] ?? 'Técnico Propietario',
      enrolledAt: map['enrolledAt'] != null
          ? DateTime.tryParse(map['enrolledAt']) ?? DateTime.now()
          : DateTime.now(),
      embeddingVector: (map['embeddingVector'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      sampleCount: (map['sampleCount'] as num?)?.toInt() ?? 1,
      similarityThreshold:
          (map['similarityThreshold'] as num?)?.toDouble() ?? 0.68,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory SpeakerProfile.fromJson(String source) =>
      SpeakerProfile.fromMap(jsonDecode(source));
}
