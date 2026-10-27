import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/translation/data/datasources/onnx_nmt_service_impl.dart';
import '../../features/translation/domain/services/nmt_service.dart';
import 'offline_translation_engine.dart';
import '../utils/app_logger.dart';

/// 100% offline translation service.
///
/// Translation runs entirely on-device with the MarianMT ONNX models that ship
/// pre-installed inside the app (`assets/models/nmt_en_ja`, `nmt_ja_en`).
/// There is no network access, no model download and no online fallback.
/// If the native ONNX engine cannot run (e.g. Flutter web), the embedded
/// phrase engine is used instead.
class TranslationService {
  final NmtService? _nmt;
  Future<void>? _initFuture;

  TranslationService({NmtService? nmtService})
      : _nmt = nmtService ?? (kIsWeb ? null : OnnxNmtServiceImpl());

  /// Prepares the bundled on-device models. No download is ever performed.
  Future<bool> initializeModels({bool isWifiRequired = false}) async {
    final nmt = _nmt;
    if (nmt == null) return true;
    try {
      await (_initFuture ??= nmt.initialize());
    } catch (e, st) {
      AppLogger.error('TranslationService', 'Offline engine init failed', e, st);
    }
    return true;
  }

  /// Translates English text to Japanese, fully offline.
  Future<String> translateToJapanese(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return '';
    final neural = await _neural(clean, 'en', 'ja');
    if (neural.isNotEmpty) return neural;

    final phrase = OfflineTranslationEngine.translateEnToJa(clean);
    return phrase.isNotEmpty ? phrase : clean;
  }

  /// Translates Japanese text to English, fully offline.
  Future<String> translateToEnglish(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return '';
    final neural = await _neural(clean, 'ja', 'en');
    if (neural.isNotEmpty) return neural;

    final phrase = OfflineTranslationEngine.translateJaToEn(clean);
    return phrase.isNotEmpty ? phrase : clean;
  }

  Future<String> _neural(String text, String from, String to) async {
    final nmt = _nmt;
    if (nmt == null) return '';
    try {
      await initializeModels();
      return (await nmt.translate(text, sourceLang: from, targetLang: to)).trim();
    } catch (e) {
      AppLogger.warning('TranslationService', 'On-device translation error: $e');
      return '';
    }
  }

  /// Models are pre-installed with the app, so they are always available.
  Future<bool> areModelsDownloaded() async => true;

  Future<void> dispose() async {
    try {
      await _nmt?.dispose();
    } catch (_) {}
    _initFuture = null;
  }
}

/// Riverpod provider exposing TranslationService instance
final translationServiceProvider = Provider<TranslationService>((ref) {
  final service = TranslationService();
  ref.onDispose(() => service.dispose());
  return service;
});
