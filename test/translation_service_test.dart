import 'package:flutter_test/flutter_test.dart';
import 'package:edge_translator/core/services/translation_service.dart';
import 'package:edge_translator/core/services/offline_translation_engine.dart';
import 'package:edge_translator/features/translation/domain/services/nmt_service.dart';

class FakeNmt implements NmtService {
  final String output;
  int initCalls = 0;
  String? lastFrom;
  String? lastTo;
  FakeNmt(this.output);

  @override
  Future<void> initialize() async => initCalls++;

  @override
  Future<String> translate(String text, {required String sourceLang, required String targetLang}) async {
    lastFrom = sourceLang;
    lastTo = targetLang;
    return output;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('TranslationService Tests', () {
    test('models are bundled: always available, no download needed', () async {
      final service = TranslationService(nmtService: FakeNmt('x'));
      expect(await service.areModelsDownloaded(), true);
      expect(await service.initializeModels(), true);
    });

    test('delegates to the on-device engine in the right direction', () async {
      final nmt = FakeNmt('こんにちは');
      final service = TranslationService(nmtService: nmt);
      expect(await service.translateToJapanese('Hello'), 'こんにちは');
      expect(nmt.lastFrom, 'en');
      expect(nmt.lastTo, 'ja');
      expect(nmt.initCalls, 1);

      expect(await service.translateToEnglish('こんにちは'), 'こんにちは');
      expect(nmt.lastFrom, 'ja');
      expect(nmt.lastTo, 'en');
    });

    test('falls back to the embedded phrase engine (still offline) when ONNX yields nothing', () async {
      final service = TranslationService(nmtService: FakeNmt(''));
      expect(await service.translateToJapanese('hello'), 'こんにちは');
      expect(await service.translateToEnglish('ありがとう'), 'Thank you');
    });

    test('OfflineTranslationEngine translates English to Japanese offline', () {
      expect(OfflineTranslationEngine.translateEnToJa('hello'), 'こんにちは');
      expect(OfflineTranslationEngine.translateEnToJa('thank you'), 'ありがとうございます');
      expect(OfflineTranslationEngine.translateEnToJa('where is the station?'), '駅はどこですか？');
      expect(OfflineTranslationEngine.translateEnToJa('where is shibuya station?'), '渋谷駅はどこですか？');
      expect(OfflineTranslationEngine.translateEnToJa('where is the bathroom?'), 'トイレはどこですか？');
      expect(OfflineTranslationEngine.translateEnToJa('how much is this?'), 'これはいくらですか？');
      expect(OfflineTranslationEngine.translateEnToJa('water please'), 'お水をお願いします');
    });

    test('OfflineTranslationEngine translates Japanese to English offline', () {
      expect(OfflineTranslationEngine.translateJaToEn('こんにちは'), 'Hello');
      expect(OfflineTranslationEngine.translateJaToEn('ありがとう'), 'Thank you');
      expect(OfflineTranslationEngine.translateJaToEn('駅はどこですか？'), 'Where is the station?');
      expect(OfflineTranslationEngine.translateJaToEn('トイレはどこですか？'), 'Where is the bathroom?');
      expect(OfflineTranslationEngine.translateJaToEn('これはいくらですか？'), 'How much is this?');
      expect(OfflineTranslationEngine.translateJaToEn('お水をお願いします'), 'Water, please');
    });
  });
}
