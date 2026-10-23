import '../../../../core/services/translation_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/services/nmt_service.dart';

/// Neural Machine Translation implementation powered by Google ML Kit OnDeviceTranslator.
class MlKitNmtServiceImpl implements NmtService {
  final TranslationService translationService;

  MlKitNmtServiceImpl({required this.translationService});

  @override
  Future<void> initialize() async {
    AppLogger.info('MlKitNmtService', 'Initializing Google ML Kit translation models (EN & JA)...');
    await translationService.initializeModels(isWifiRequired: false);
  }

  @override
  Future<String> translate(
    String text, {
    required String sourceLang,
    required String targetLang,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return '';

    final isEnToJa = sourceLang.toLowerCase() == 'en' || targetLang.toLowerCase() == 'ja';
    if (isEnToJa) {
      return await translationService.translateToJapanese(clean);
    } else {
      return await translationService.translateToEnglish(clean);
    }
  }

  @override
  Future<void> dispose() async {
    AppLogger.info('MlKitNmtService', 'MlKitNmtService disposed.');
  }
}
