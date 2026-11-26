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
  Future<void>? _initFuture;
  String? _lastInitError;

  bool get isInitialized => _isInitialized;
  String? get lastInitError => _lastInitError;

  TranslationRepository({
    required this.asrService,
    required this.nmtService,
    required this.ttsService,
    required this.modelLoader,
  });

  /// Prepares model files from the AI pack into local storage and initializes engines.
  Future<void> initializeModels() async {
    if (_isInitialized) return;
    return _initFuture ??= _doInitializeModels().whenComplete(() {
      _initFuture = null;
    });
  }

  Future<void> _doInitializeModels() async {
    try {
      _lastInitError = null;
      await modelLoader.ensureModelsExtracted();
      await asrService.initialize();
      await nmtService.initialize();
      await ttsService.initialize();
      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      _lastInitError = e.toString();
      rethrow;
    }
  }

  Future<void> dispose() async {
    _initFuture = null;
    await asrService.dispose();
    await nmtService.dispose();
    await ttsService.dispose();
    _isInitialized = false;
  }
}
