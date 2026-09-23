import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses_app/features/voice_gate/models/speaker_profile.dart';
import 'package:smart_glasses_app/features/voice_gate/models/voice_gate_models.dart';
import 'package:smart_glasses_app/features/voice_gate/speaker_verifier.dart';
import 'package:smart_glasses_app/features/voice_gate/vosk_keyword_service.dart';
import 'package:smart_glasses_app/features/voice_gate/voice_gatekeeper_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SpeakerProfile & Biometrics Tests', () {
    test('Cosine similarity: identical vectors return 1.0', () {
      final profile = SpeakerProfile(
        id: 'tech_01',
        name: 'Técnico Principal',
        enrolledAt: DateTime.now(),
        embeddingVector: [0.6, 0.8, 0.0],
      );
      final sim = profile.computeCosineSimilarity([0.6, 0.8, 0.0]);
      expect(sim, closeTo(1.0, 0.001));
    });

    test('Cosine similarity: orthogonal vectors return 0.0', () {
      final profile = SpeakerProfile(
        id: 'tech_01',
        name: 'Técnico Principal',
        enrolledAt: DateTime.now(),
        embeddingVector: [1.0, 0.0, 0.0],
      );
      final sim = profile.computeCosineSimilarity([0.0, 1.0, 0.0]);
      expect(sim, closeTo(0.0, 0.001));
    });

    test('Multi-sample enrollment updates embedding with fusion', () {
      final initialProfile = SpeakerProfile(
        id: 'tech_01',
        name: 'Técnico',
        enrolledAt: DateTime.now(),
        embeddingVector: const [],
      );
      expect(initialProfile.isEnrolled, isFalse);

      final sample1 = List.generate(192, (i) => i.isEven ? 1.0 : 0.0);
      final profile1 = initialProfile.withAddedSample(sample1);
      expect(profile1.isEnrolled, isTrue);
      expect(profile1.sampleCount, equals(1));

      final sample2 = List.generate(192, (i) => i.isEven ? 0.8 : 0.2);
      final profile2 = profile1.withAddedSample(sample2);
      expect(profile2.sampleCount, equals(2));
      expect(profile2.embeddingVector.length, equals(192));
    });

    test('Serialization and deserialization preserve profile state', () {
      final profile = SpeakerProfile(
        id: 'tech_01',
        name: 'Técnico Enrolado',
        sampleCount: 3,
        embeddingVector: [0.1, 0.2, 0.3],
        enrolledAt: DateTime(2025, 1, 1, 12, 0, 0),
      );
      final json = profile.toJson();
      final restored = SpeakerProfile.fromJson(json);

      expect(restored.id, equals(profile.id));
      expect(restored.name, equals(profile.name));
      expect(restored.sampleCount, equals(profile.sampleCount));
      expect(restored.embeddingVector, equals(profile.embeddingVector));
    });
  });

  group('SherpaSpeakerVerifier Tests', () {
    late SherpaSpeakerVerifier verifier;

    setUp(() {
      verifier = SherpaSpeakerVerifier();
    });

    test('Extracts normalized 192D embedding from PCM bytes', () {
      final dummyPcm = Uint8List.fromList(List.generate(16000, (i) => (i % 256)));
      final embedding = verifier.extractEmbedding(dummyPcm);

      expect(embedding.length, equals(192));
      double norm = 0.0;
      for (final val in embedding) {
        norm += val * val;
      }
      expect(norm, closeTo(1.0, 0.01));
    });

    test('Calculates RMS audio energy correctly', () {
      final silence = Uint8List(1000);
      expect(verifier.computeRmsEnergy(silence), closeTo(0.0, 0.001));

      final active = Uint8List.fromList(List.generate(1000, (i) => 100));
      expect(verifier.computeRmsEnergy(active), greaterThan(0.0));
    });

    test('Speaker verification approves authorized speaker', () async {
      final techPcm = Uint8List.fromList(List.generate(16000, (i) => (i * 3) % 256));
      await verifier.enrollSample(techPcm);

      expect(verifier.hasEnrolledProfile, isTrue);

      final resultSelf = verifier.verifySpeaker(techPcm, customThreshold: 0.68);
      expect(resultSelf.isAuthorized, isTrue);
      expect(resultSelf.similarityScore, greaterThanOrEqualTo(0.68));
    });
  });

  group('VoskKeywordService Tests', () {
    late VoskKeywordService voskService;

    setUp(() {
      voskService = VoskKeywordService();
    });

    test('Identifies technician intent when wake word is used', () {
      final res = voskService.evaluateTextIntent('gafas identifica este integrado quemado');
      expect(res.hasWakeWord, isTrue);
      expect(res.matchedWakeWord, equals('gafas'));
      expect(res.hasGrammarMatch, isTrue);
      expect(res.cleanPrompt, equals('identifica este integrado quemado'));
    });

    test('Identifies technician intent with command prefix without wake word', () {
      final res = voskService.evaluateTextIntent('diagnostica el fallo en esta placa');
      expect(res.hasGrammarMatch, isTrue);
      expect(res.matchedIntent, equals('diagnostica'));
      expect(res.cleanPrompt, equals('diagnostica el fallo en esta placa'));
    });

    test('Detects local device commands like bateria, beep or ping', () {
      final res = voskService.evaluateTextIntent('gafas bateria');
      expect(res.hasWakeWord, isTrue);
      expect(res.isLocalOnlyAction, isTrue);
      expect(res.matchedIntent, equals('bateria'));
    });

    test('Rejects unrelated conversational noise', () {
      final res = voskService.evaluateTextIntent('oye pasame la llave inglesa de la mesa');
      expect(res.hasWakeWord, isFalse);
      expect(res.hasGrammarMatch, isFalse);
    });
  });

  group('VoiceGatekeeperService Integrated Tests', () {
    late VoiceGatekeeperService gatekeeper;

    setUp(() {
      gatekeeper = VoiceGatekeeperService();
    });

    test('Bypasses check when gatekeeper is disabled', () async {
      await gatekeeper.updateConfig(gatekeeper.config.copyWith(enabled: false));
      final dummyPcm = Uint8List(100);

      final eval = await gatekeeper.evaluateAudioQuery(
        pcmBytes: dummyPcm,
        transcribedText: 'cualquier cosa',
      );

      expect(eval.shouldForwardToServer, isTrue);
      expect(eval.reasonDescription, contains('desactivado'));
    });

    test('Rejects silence / ambient noise without technician query', () async {
      await gatekeeper.updateConfig(gatekeeper.config.copyWith(
        enabled: true,
        minRmsEnergy: 0.10,
      ));
      final silentPcm = Uint8List(1000);

      final eval = await gatekeeper.evaluateAudioQuery(
        pcmBytes: silentPcm,
        transcribedText: '',
      );

      expect(eval.shouldForwardToServer, isFalse);
      expect(eval.rejectionReason, equals(VoiceGateRejectionReason.silenceOrNoise));
    });

    test('Allows valid query with wake keyword and voice match', () async {
      final activePcm = Uint8List.fromList(List.generate(16000, (i) => 120 + (i % 30)));
      await gatekeeper.enrollTechnicianVoice(activePcm);

      await gatekeeper.updateConfig(gatekeeper.config.copyWith(
        enabled: true,
        requireSpeakerMatch: true,
        requireWakeKeyword: true,
        similarityThreshold: 0.60,
      ));

      final eval = await gatekeeper.evaluateAudioQuery(
        pcmBytes: activePcm,
        transcribedText: 'gafas identifica este componente',
      );

      expect(eval.shouldForwardToServer, isTrue);
      expect(eval.promptForServer, equals('identifica este componente'));
      expect(eval.rejectionReason, equals(VoiceGateRejectionReason.none));
    });
  });
}
