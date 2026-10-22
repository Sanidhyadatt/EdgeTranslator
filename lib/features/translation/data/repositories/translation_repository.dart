import '../datasources/model_loader.dart';
import '../../domain/services/asr_service.dart';
import '../../domain/services/nmt_service.dart';
import '../../domain/services/tts_service.dart';

/// Repository coordinating the lifecycle of the edge ML models.
class TranslationRepository {
  final AsrService asrService;
  final NmtService nmtService;
  final TtsService ttsService;
  final ModelLoader modelLoader;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  TranslationRepository({
    required this.asrService,
    required this.nmtService,
    required this.ttsService,
    required this.modelLoader,
  });

  /// Prepares model files from Flutter assets to local device cache and initializes engines.
  Future<void> initializeModels() async {
    if (_isInitialized) return;
    await modelLoader.ensureModelsExtracted();
    await asrService.initialize();
    await nmtService.initialize();
    await ttsService.initialize();
    _isInitialized = true;
  }

  Future<void> dispose() async {
    await asrService.dispose();
    await nmtService.dispose();
    await ttsService.dispose();
    _isInitialized = false;
  }
}
