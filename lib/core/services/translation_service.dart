import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../utils/app_logger.dart';

/// Offline Translation Service powered by Google ML Kit OnDeviceTranslator.
///
/// Handles on-device model package management (English & Japanese) and
/// ensures zero memory leaks by releasing native translator instances immediately
/// after translation.
class TranslationService {
  final OnDeviceTranslatorModelManager _modelManager;

  TranslationService({OnDeviceTranslatorModelManager? modelManager})
      : _modelManager = modelManager ?? OnDeviceTranslatorModelManager();

  /// Downloads and verifies the offline English and Japanese translation model packs.
  Future<bool> initializeModels({bool isWifiRequired = false}) async {
    try {
      AppLogger.info('TranslationService', 'Checking and downloading offline translation models via Google ML Kit...');

      // 1. English Model Pack
      final enCode = TranslateLanguage.english.bcpCode;
      final isEnReady = await _modelManager.isModelDownloaded(enCode);
      if (!isEnReady) {
        AppLogger.info('TranslationService', 'Downloading English model pack ($enCode)...');
        final enSuccess = await _modelManager.downloadModel(enCode, isWifiRequired: isWifiRequired);
        AppLogger.info('TranslationService', 'English model download result: $enSuccess');
      } else {
        AppLogger.info('TranslationService', 'English model pack is already cached on device.');
      }

      // 2. Japanese Model Pack
      final jaCode = TranslateLanguage.japanese.bcpCode;
      final isJaReady = await _modelManager.isModelDownloaded(jaCode);
      if (!isJaReady) {
        AppLogger.info('TranslationService', 'Downloading Japanese model pack ($jaCode)...');
        final jaSuccess = await _modelManager.downloadModel(jaCode, isWifiRequired: isWifiRequired);
        AppLogger.info('TranslationService', 'Japanese model download result: $jaSuccess');
      } else {
        AppLogger.info('TranslationService', 'Japanese model pack is already cached on device.');
      }

      final downloaded = await areModelsDownloaded();
      AppLogger.info('TranslationService', 'Offline translation models status: $downloaded');
      return downloaded;
    } catch (e, st) {
      AppLogger.error('TranslationService', 'Platform model download error', e, st);
      return false;
    }
  }

  /// Translates English text to Japanese using the offline Google ML Kit on-device model.
  /// Calls `close()` on the translator instance in a finally block to prevent memory leaks.
  Future<String> translateToJapanese(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return '';

    final onDeviceTranslator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: TranslateLanguage.japanese,
    );

    try {
      AppLogger.info('TranslationService', 'Google ML Kit translating [EN -> JA]: "$clean"');
      final result = await onDeviceTranslator.translateText(clean);
      AppLogger.info('TranslationService', 'Google ML Kit translated [EN -> JA]: "$clean" -> "$result"');
      return result;
    } catch (e, st) {
      AppLogger.error('TranslationService', 'Native Google ML Kit translation error', e, st);
      final isDownloaded = await areModelsDownloaded();
      if (!isDownloaded) {
        return '[Offline models not downloaded. Please tap "Download Models" to download EN/JA offline packs]';
      }
      return clean;
    } finally {
      try {
        await onDeviceTranslator.close();
      } catch (_) {}
    }
  }

  /// Translates Japanese text to English using the offline Google ML Kit on-device model.
  /// Calls `close()` on the translator instance in a finally block to prevent memory leaks.
  Future<String> translateToEnglish(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return '';

    final onDeviceTranslator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.japanese,
      targetLanguage: TranslateLanguage.english,
    );

    try {
      AppLogger.info('TranslationService', 'Google ML Kit translating [JA -> EN]: "$clean"');
      final result = await onDeviceTranslator.translateText(clean);
      AppLogger.info('TranslationService', 'Google ML Kit translated [JA -> EN]: "$clean" -> "$result"');
      return result;
    } catch (e, st) {
      AppLogger.error('TranslationService', 'Native Google ML Kit translation error', e, st);
      final isDownloaded = await areModelsDownloaded();
      if (!isDownloaded) {
        return '[Offline models not downloaded. Please tap "Download Models" to download EN/JA offline packs]';
      }
      return clean;
    } finally {
      try {
        await onDeviceTranslator.close();
      } catch (_) {}
    }
  }

  /// Checks if both English and Japanese offline models are downloaded.
  Future<bool> areModelsDownloaded() async {
    try {
      final enReady = await _modelManager.isModelDownloaded(TranslateLanguage.english.bcpCode);
      final jaReady = await _modelManager.isModelDownloaded(TranslateLanguage.japanese.bcpCode);
      return enReady && jaReady;
    } catch (e) {
      AppLogger.warning('TranslationService', 'Error checking model download status: $e');
      return false;
    }
  }
}

/// Riverpod provider exposing TranslationService instance
final translationServiceProvider = Provider<TranslationService>((ref) {
  return TranslationService();
});
