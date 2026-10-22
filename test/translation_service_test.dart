import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:edge_translator/core/services/translation_service.dart';

class FakeModelManager implements OnDeviceTranslatorModelManager {
  final Set<String> downloadedModels = {};
  final List<String> downloadedCalls = [];

  @override
  Future<bool> isModelDownloaded(String model) async {
    return downloadedModels.contains(model);
  }

  @override
  Future<bool> downloadModel(String model, {bool isWifiRequired = true}) async {
    downloadedCalls.add(model);
    downloadedModels.add(model);
    return true;
  }

  @override
  Future<bool> deleteModel(String model) async {
    downloadedModels.remove(model);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('TranslationService Tests', () {
    late FakeModelManager fakeModelManager;
    late TranslationService translationService;

    setUp(() {
      fakeModelManager = FakeModelManager();
      translationService = TranslationService(modelManager: fakeModelManager);
    });

    test('initializeModels downloads English and Japanese models when not downloaded', () async {
      expect(await translationService.areModelsDownloaded(), false);

      final result = await translationService.initializeModels();
      expect(result, true);

      // Verify that both English ('en') and Japanese ('ja') model codes were requested for download
      expect(fakeModelManager.downloadedCalls, contains(TranslateLanguage.english.bcpCode));
      expect(fakeModelManager.downloadedCalls, contains(TranslateLanguage.japanese.bcpCode));
      expect(await translationService.areModelsDownloaded(), true);
    });

    test('initializeModels skips downloading if models are already cached', () async {
      fakeModelManager.downloadedModels.add(TranslateLanguage.english.bcpCode);
      fakeModelManager.downloadedModels.add(TranslateLanguage.japanese.bcpCode);

      final result = await translationService.initializeModels();
      expect(result, true);

      // No new download calls should have been made
      expect(fakeModelManager.downloadedCalls, isEmpty);
      expect(await translationService.areModelsDownloaded(), true);
    });
  });
}
