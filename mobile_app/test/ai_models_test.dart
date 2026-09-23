import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses_app/features/ai_assistant/models/ai_response_model.dart';
import 'package:smart_glasses_app/features/ai_assistant/mock_responses.dart';
import 'package:smart_glasses_app/core/constants/api_constants.dart';

void main() {
  group('AiPipelineMetrics', () {
    test('copyWith no muta el original', () {
      final base = AiPipelineMetrics(cameraCaptureMs: 10, llmLatencyMs: 20);
      final next = base.copyWith(ttsMs: 5, totalRoundTripMs: 35);
      expect(base.ttsMs, 0);
      expect(next.cameraCaptureMs, 10);
      expect(next.llmLatencyMs, 20);
      expect(next.ttsMs, 5);
      expect(next.totalRoundTripMs, 35);
    });
  });

  group('MockResponses', () {
    test('ofrece procedimiento ante desmontaje', () {
      expect(MockResponses.forQuery('Guíame para desmontarlo'), contains('Corta tensión'));
    });

    test('pide mejor ángulo si piden número de serie', () {
      expect(MockResponses.forQuery('Lee el número de serie'), contains('número de serie'));
    });
  });

  group('ApiConstants', () {
    test('UUIDs BLE estables y endpoints OpenAI-like', () {
      expect(ApiConstants.bleServiceUuid, contains('4fafc201'));
      expect(ApiConstants.chatCompletionsEndpoint, '/chat/completions');
      expect(ApiConstants.speechEndpoint, '/audio/speech');
      expect(ApiConstants.glassesBleName, 'XIAO-SmartGlasses');
    });
  });
}
