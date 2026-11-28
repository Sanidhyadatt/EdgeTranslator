import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/app_logger.dart';

/// Structured error raised when preparing or extracting offline AI pack models fails.
class ModelExtractionException implements Exception {
  final String code;
  final String message;

  const ModelExtractionException(this.code, this.message);

  @override
  String toString() => 'ModelExtractionException($code): $message';
}

/// Strongly typed container holding absolute file paths for Sherpa ASR model components.
class AsrModelPaths {
  final String encoderPath;
  final String decoderPath;
  final String tokensPath;
  final String? vadPath;
  final String? senseVoiceModelPath;
  final String? senseVoiceTokensPath;

  const AsrModelPaths({
    required this.encoderPath,
    required this.decoderPath,
    required this.tokensPath,
    this.vadPath,
    this.senseVoiceModelPath,
    this.senseVoiceTokensPath,
  });

  bool get hasSenseVoice =>
      senseVoiceModelPath != null &&
      senseVoiceTokensPath != null &&
      File(senseVoiceModelPath!).existsSync() &&
      File(senseVoiceTokensPath!).existsSync();

  bool get hasWhisper =>
      encoderPath.isNotEmpty &&
      decoderPath.isNotEmpty &&
      tokensPath.isNotEmpty &&
      File(encoderPath).existsSync() &&
      File(decoderPath).existsSync() &&
      File(tokensPath).existsSync();
}

/// Strongly typed container holding absolute file paths for Sherpa TTS model components for one direction/language.
class TtsDirectionModelPaths {
  final String modelPath;
  final String tokensPath;
  final String? lexiconPath;
  final String? dataDir;

  const TtsDirectionModelPaths({
    required this.modelPath,
    required this.tokensPath,
    this.lexiconPath,
    this.dataDir,
  });

  bool get areWeightsAvailable {
    return File(modelPath).existsSync() && File(tokensPath).existsSync();
  }
}

/// Strongly typed container holding absolute file paths for multilingual Sherpa TTS model components.
class TtsModelPaths {
  final TtsDirectionModelPaths en;
  final TtsDirectionModelPaths ja;

  // Single-model backward compatibility accessors
  String get modelPath => ja.modelPath;
  String? get lexiconPath => ja.lexiconPath;
  String get tokensPath => ja.tokensPath;
  String? get dataDir => ja.dataDir;

  const TtsModelPaths({
    required this.en,
    required this.ja,
  });
}

/// Strongly typed container holding absolute file paths for MarianMT NMT model components in one direction.
class NmtDirectionModelPaths {
  final String encoderPath;
  final String decoderPath;
  final String? sourceSpmPath;
  final String? targetSpmPath;
  final String? vocabJsonPath;
  final String? tokenizerConfigJsonPath;

  const NmtDirectionModelPaths({
    required this.encoderPath,
    required this.decoderPath,
    this.sourceSpmPath,
    this.targetSpmPath,
    this.vocabJsonPath,
    this.tokenizerConfigJsonPath,
  });

  bool get areWeightsAvailable {
    return File(encoderPath).existsSync() && File(decoderPath).existsSync();
  }
}

/// Strongly typed container holding absolute file paths for bidirectional MarianMT NMT models.
class NmtModelPaths {
  final NmtDirectionModelPaths enJa;
  final NmtDirectionModelPaths jaEn;

  const NmtModelPaths({
    required this.enJa,
    required this.jaEn,
  });
}

/// Manages extraction of ONNX models, SentencePiece models (.spm), and dictionary files
/// delivered via the Android install-time AI pack (`:ai_models`) into internal storage.
///
/// Native C/FFI engines (Sherpa-ONNX & ONNX Runtime) require absolute filesystem paths
/// and cannot read directly from Play install-time AI pack split assets via [rootBundle].
class ModelLoader {
  static const MethodChannel aiModelsChannel =
      MethodChannel('com.ikho.mistyforgelabs/ai_models');

  static Future<List<File>>? _inFlightExtraction;
  static Zone? _inFlightZone;

  final Directory? customModelsDirectory;
  final bool? useAndroidChannel;

  const ModelLoader({
    this.customModelsDirectory,
    this.useAndroidChannel,
  });

  bool get _shouldUseAndroidChannel => useAndroidChannel ?? Platform.isAndroid;

  /// Gets the local directory reserved for on-device machine learning models
  /// in the device's application document directory.
  Future<Directory> get modelsDirectory async {
    if (kIsWeb) return Directory('');
    if (customModelsDirectory != null) {
      if (!await customModelsDirectory!.exists()) {
        await customModelsDirectory!.create(recursive: true);
      }
      return customModelsDirectory!;
    }
    Directory appDocDir;
    try {
      appDocDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      // Fallback for headless widget/unit test environments where platform channels are unmocked
      appDocDir = Directory.systemTemp;
    }
    final modelsDir = Directory(p.join(appDocDir.path, 'models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  /// Queries the Android install-time AI pack status when running on Android.
  Future<Map<String, Object?>?> getPackStatus() async {
    if (kIsWeb || !_shouldUseAndroidChannel) return null;
    final baseDir = await modelsDirectory;
    try {
      final status = await aiModelsChannel.invokeMapMethod<String, Object?>(
        'getPackStatus',
        {'targetDir': baseDir.path},
      );
      return status;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      AppLogger.warning('ModelLoader', 'Unable to query AI pack status: ${e.code} ${e.message}');
      return null;
    }
  }

  /// Extracts .onnx, .spm, .json, .txt, and espeak-ng-data model files from the
  /// Flutter asset bundle to local storage, serializing concurrent calls.
  Future<List<File>> extractModelAssets({bool overwrite = false}) async {
    if (kIsWeb) return [];
    final currentZone = Zone.current;
    final previous = _inFlightExtraction;
    if (previous != null && identical(_inFlightZone, currentZone)) {
      if (!overwrite) return await previous;
      try {
        await previous;
      } catch (_) {}
    }

    final extraction = _performExtractModelAssets(overwrite: overwrite);
    _inFlightExtraction = extraction;
    _inFlightZone = currentZone;
    try {
      return await extraction;
    } finally {
      if (identical(_inFlightExtraction, extraction)) {
        _inFlightExtraction = null;
        _inFlightZone = null;
      }
    }
  }

  Future<List<File>> _performExtractModelAssets({required bool overwrite}) async {
    final baseDir = await modelsDirectory;
    await _cleanupObsoleteModels(baseDir);

    final List<File> extractedFiles;
    if (_shouldUseAndroidChannel) {
      extractedFiles = await _extractFromAndroidAiPack(baseDir, overwrite: overwrite);
    } else {
      extractedFiles = await _extractFromBundleOrLocalPack(baseDir, overwrite: overwrite);
    }

    // Strict File Existence Guards for extracted ML weights/tokens
    for (final file in extractedFiles) {
      final extractedPath = p.normalize(p.absolute(file.path));
      final lower = extractedPath.toLowerCase();
      if (lower.endsWith('.onnx') || lower.endsWith('.txt')) {
        if (!File(extractedPath).existsSync()) {
          throw ModelExtractionException(
            'IO_ERROR',
            'CRITICAL FFI ERROR: Missing file at $extractedPath',
          );
        }
      }
    }

    AppLogger.info('ModelLoader', 'Prepared ${extractedFiles.length} model files in: ${baseDir.path}');
    return extractedFiles;
  }

  Future<void> _cleanupObsoleteModels(Directory baseDir) async {
    final legacyEnJaDir = Directory(p.join(baseDir.path, 'nmt_en_ja'));
    if (await legacyEnJaDir.exists()) {
      for (final entity in legacyEnJaDir.listSync()) {
        if (entity is File && p.basename(entity.path).contains('(1)')) {
          try {
            await entity.delete();
            AppLogger.info('ModelLoader', 'Removed legacy model file: ${entity.path}');
          } catch (_) {}
        }
      }
    }
    for (final obsoleteRel in const [
      'tiny-encoder.int8.onnx',
      'tiny-decoder.int8.onnx',
      'tiny-tokens.txt',
    ]) {
      final obsoleteFile = File(p.join(baseDir.path, obsoleteRel));
      if (await obsoleteFile.exists()) {
        try {
          await obsoleteFile.delete();
          AppLogger.info('ModelLoader', 'Removed obsolete ASR weight: ${obsoleteFile.path}');
        } catch (_) {}
      }
    }
  }

  Future<List<File>> _extractFromAndroidAiPack(
    Directory baseDir, {
    required bool overwrite,
  }) async {
    try {
      final paths = await aiModelsChannel.invokeListMethod<String>(
        'extractModels',
        {
          'targetDir': baseDir.path,
          'overwrite': overwrite,
        },
      );
      if (paths == null || paths.isEmpty) {
        throw const ModelExtractionException(
          'AI_PACK_MISSING',
          'Install-time AI pack returned no model files from Android AssetManager.',
        );
      }
      return paths.map((path) => File(path)).toList();
    } on PlatformException catch (e) {
      final code = e.code.isEmpty ? 'AI_PACK_ERROR' : e.code;
      final message = e.message ?? 'Failed extracting install-time AI pack models.';
      AppLogger.error('ModelLoader', 'Android AI pack extraction failed ($code): $message', e);
      throw ModelExtractionException(code, message);
    } on MissingPluginException catch (e) {
      if (!overwrite) {
        final existing = await _collectExistingModelFiles(baseDir);
        if (_hasCoreWeightsOnDisk(baseDir) && existing.isNotEmpty) {
          AppLogger.warning(
            'ModelLoader',
            'AI pack MethodChannel unavailable; reusing ${existing.length} already-extracted files on disk.',
          );
          return existing;
        }
      }
      AppLogger.error('ModelLoader', 'Android AI pack MethodChannel not registered', e);
      throw const ModelExtractionException(
        'MISSING_PLUGIN',
        'Native Android AI pack extractor channel is not available.',
      );
    }
  }

  Future<List<File>> _extractFromBundleOrLocalPack(
    Directory baseDir, {
    required bool overwrite,
  }) async {
    final List<File> extractedFiles = [];
    List<String> modelAssets = const [];

    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = manifest.listAssets();
      modelAssets = allAssets.where((assetKey) {
        final lower = assetKey.toLowerCase();
        final hasModelExtension = lower.endsWith('.onnx') ||
            lower.endsWith('.spm') ||
            lower.endsWith('.json') ||
            lower.endsWith('.txt');
        final isEspeakAsset = lower.contains('/espeak-ng-data/') && !lower.endsWith('/');
        final isInModelsDir = assetKey.startsWith('assets/models') ||
            assetKey.contains('/models/') ||
            assetKey.startsWith('models/');
        return (hasModelExtension || isEspeakAsset) && isInModelsDir;
      }).toList();
    } catch (e) {
      AppLogger.info('ModelLoader', 'AssetManifest unavailable or empty ($e); checking local AI pack directory.');
    }

    if (modelAssets.isNotEmpty) {
      AppLogger.info('ModelLoader', 'Found ${modelAssets.length} model assets in Flutter rootBundle.');
      for (final assetPath in modelAssets) {
        final file = await copyAssetToStorage(assetPath, overwrite: overwrite);
        extractedFiles.add(file);
      }
      return extractedFiles;
    }

    final localPackDir = _findLocalAiPackModelsDir();
    if (localPackDir != null) {
      AppLogger.info('ModelLoader', 'Copying model assets from local AI pack directory: ${localPackDir.path}');
      await for (final entity in localPackDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        final relPath = p.relative(entity.path, from: localPackDir.path);
        final copied = await _copyLocalFileToStorage(
          entity,
          relPath,
          baseDir: baseDir,
          overwrite: overwrite,
        );
        extractedFiles.add(copied);
      }
      if (extractedFiles.isNotEmpty) {
        return extractedFiles;
      }
    }

    final existing = await _collectExistingModelFiles(baseDir);
    if (existing.isNotEmpty) {
      return existing;
    }

    throw const ModelExtractionException(
      'AI_PACK_MISSING',
      'No model assets found in AssetManifest, local AI pack directory, or app storage.',
    );
  }

  Directory? _findLocalAiPackModelsDir() {
    var dir = Directory.current.absolute;
    for (var depth = 0; depth < 5; depth++) {
      final candidate = Directory(p.join(dir.path, 'android', 'ai_models', 'src', 'main', 'assets', 'models'));
      if (candidate.existsSync() &&
          File(p.join(candidate.path, AppConstants.senseVoiceModelFile)).existsSync()) {
        return candidate;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  Future<File> _copyLocalFileToStorage(
    File sourceFile,
    String relativePath, {
    required Directory baseDir,
    required bool overwrite,
  }) async {
    final normalizedRelative = p.normalize(relativePath);
    final targetFile = File(p.join(baseDir.path, normalizedRelative));
    final srcSize = await sourceFile.length();

    if (!overwrite && await targetFile.exists()) {
      final dstSize = await targetFile.length();
      if (dstSize == srcSize && dstSize > 0) {
        return targetFile;
      }
    }

    await targetFile.parent.create(recursive: true);
    final tempFile = File('${targetFile.path}.tmp');
    try {
      await sourceFile.copy(tempFile.path);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
      return targetFile;
    } catch (e) {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      throw ModelExtractionException(
        'IO_ERROR',
        'Failed copying model asset $relativePath: $e',
      );
    }
  }

  Future<List<File>> _collectExistingModelFiles(Directory baseDir) async {
    if (!await baseDir.exists()) return [];
    final files = <File>[];
    await for (final entity in baseDir.list(recursive: true, followLinks: false)) {
      if (entity is File && !p.basename(entity.path).startsWith('.')) {
        files.add(entity);
      }
    }
    return files;
  }

  bool _hasCoreWeightsOnDisk(Directory baseDir) {
    return File(p.join(baseDir.path, AppConstants.senseVoiceModelFile)).existsSync() &&
        File(p.join(baseDir.path, 'nmt_en_ja/encoder_model_quantized.onnx')).existsSync() &&
        File(p.join(baseDir.path, 'nmt_ja_en/encoder_model_quantized.onnx')).existsSync() &&
        File(p.join(baseDir.path, 'tts_en/en_US-lessac-medium.onnx')).existsSync() &&
        File(p.join(baseDir.path, 'tts_ja/model (1).onnx')).existsSync();
  }

  /// Explicitly extracts MarianMT NMT model assets (.onnx and .spm).
  Future<List<File>> extractNmtModels({bool overwrite = false}) async {
    return await extractModelAssets(overwrite: overwrite);
  }

  /// Explicitly extracts Sherpa TTS model assets (.onnx and .txt).
  Future<List<File>> extractTtsModels({bool overwrite = false}) async {
    return await extractModelAssets(overwrite: overwrite);
  }

  /// Copies an individual asset file to local application documents directory storage
  /// if it does not already exist (or if [overwrite] is true).
  Future<File> copyAssetToStorage(String assetPath, {bool overwrite = false}) async {
    final baseDir = await modelsDirectory;

    // Preserve relative subfolder structure (e.g. asr/, tts/, nmt_en_ja/, nmt_ja_en/)
    String relativePath = assetPath;
    if (relativePath.startsWith('assets/models/')) {
      relativePath = relativePath.substring('assets/models/'.length);
    } else if (relativePath.startsWith('models/')) {
      relativePath = relativePath.substring('models/'.length);
    } else if (relativePath.startsWith('assets/')) {
      relativePath = relativePath.substring('assets/'.length);
    }

    final normalizedRelative = p.normalize(relativePath);
    final targetFile = File(p.join(baseDir.path, normalizedRelative));

    if (!overwrite && await targetFile.exists()) {
      final stat = await targetFile.stat();
      if (stat.size > 0) {
        return targetFile;
      }
    }

    await targetFile.parent.create(recursive: true);
    final tempFile = File('${targetFile.path}.tmp');

    try {
      final byteData = await rootBundle.load(assetPath);
      final buffer = byteData.buffer;
      await tempFile.writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        flush: true,
      );
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
      AppLogger.info('ModelLoader', 'Extracted asset to: ${targetFile.path} (${byteData.lengthInBytes} bytes)');
    } catch (e) {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      AppLogger.error('ModelLoader', 'Failed extracting asset: $assetPath', e);
      rethrow;
    }

    return targetFile;
  }

  /// Resolves an absolute path inside the models directory given a relative path.
  Future<String> getAbsolutePath(String relativePath) async {
    final baseDir = await modelsDirectory;
    return p.join(baseDir.path, relativePath);
  }

  /// Generates and resolves absolute file paths for Sherpa ASR model components.
  Future<AsrModelPaths> getAsrModelPaths() async {
    final baseDir = await modelsDirectory;
    final senseVoiceModel = _resolveCandidateFile(baseDir, [
      AppConstants.senseVoiceModelFile,
      'sense-voice.int8.onnx',
      'asr/model.int8.onnx',
      'model.int8.onnx',
    ]);
    final senseVoiceTokens = _resolveCandidateFile(baseDir, [
      AppConstants.senseVoiceTokensFile,
      'sense-voice-tokens.txt',
      'asr/tokens.txt',
    ]);
    final encoder = _resolveCandidateFile(baseDir, [
      AppConstants.whisperEncoderFile,
      'whisper-tiny-encoder.onnx',
      'tiny-encoder.onnx',
      'encoder.onnx',
      'asr/encoder.onnx',
    ]);
    final decoder = _resolveCandidateFile(baseDir, [
      AppConstants.whisperDecoderFile,
      'whisper-tiny-decoder.onnx',
      'tiny-decoder.onnx',
      'decoder.onnx',
      'asr/decoder.onnx',
    ]);
    final tokens = _resolveCandidateFile(baseDir, [
      AppConstants.whisperTokensFile,
      'whisper-tiny-tokens.txt',
      'tokens.txt',
      'asr/tokens.txt',
    ]);
    final vad = _resolveCandidateFile(baseDir, [
      'silero_vad.onnx',
      'vad.onnx',
      'asr/silero_vad.onnx',
    ]);

    final senseVoiceModelPath = p.normalize(p.absolute(senseVoiceModel.path));
    final senseVoiceTokensPath = p.normalize(p.absolute(senseVoiceTokens.path));
    final encoderPath = p.normalize(p.absolute(encoder.path));
    final decoderPath = p.normalize(p.absolute(decoder.path));
    final tokensPath = p.normalize(p.absolute(tokens.path));
    final vadPath = p.normalize(p.absolute(vad.path));

    final hasSenseVoice =
        File(senseVoiceModelPath).existsSync() && File(senseVoiceTokensPath).existsSync();
    final hasWhisper =
        File(encoderPath).existsSync() &&
        File(decoderPath).existsSync() &&
        File(tokensPath).existsSync();

    if (!hasSenseVoice && !hasWhisper) {
      throw Exception(
        'CRITICAL FFI ERROR: Missing both SenseVoice ($senseVoiceModelPath) and Whisper ($encoderPath) ASR weights.',
      );
    }

    return AsrModelPaths(
      encoderPath: hasWhisper ? encoderPath : senseVoiceModelPath,
      decoderPath: hasWhisper ? decoderPath : '',
      tokensPath: hasWhisper ? tokensPath : senseVoiceTokensPath,
      vadPath: vadPath,
      senseVoiceModelPath: senseVoiceModelPath,
      senseVoiceTokensPath: senseVoiceTokensPath,
    );
  }

  /// Generates and resolves absolute file paths for MarianMT NMT model components.
  Future<NmtModelPaths> getNmtModelPaths() async {
    final baseDir = await modelsDirectory;

    final enJaEncoder = _resolveCandidateFile(baseDir, [
      'nmt_en_ja/encoder_model_quantized.onnx',
      'nmt_en_ja/encoder_model.onnx',
      'nmt_en_ja/encoder.onnx',
    ]);
    final enJaDecoder = _resolveCandidateFile(baseDir, [
      'nmt_en_ja/decoder_model_quantized.onnx',
      'nmt_en_ja/decoder_model.onnx',
      'nmt_en_ja/decoder.onnx',
    ]);
    final enJaSourceSpm = _resolveCandidateFile(baseDir, [
      'nmt_en_ja/source.spm',
    ]);
    final enJaTargetSpm = _resolveCandidateFile(baseDir, [
      'nmt_en_ja/target.spm',
    ]);
    final enJaVocab = _resolveCandidateFile(baseDir, [
      'nmt_en_ja/vocab.json',
    ]);
    final enJaTokenizerConfig = _resolveCandidateFile(baseDir, [
      'nmt_en_ja/tokenizer_config.json',
    ]);

    final jaEnEncoder = _resolveCandidateFile(baseDir, [
      'nmt_ja_en/encoder_model_quantized.onnx',
      'nmt_ja_en/encoder_model.onnx',
      'nmt_ja_en/encoder.onnx',
    ]);
    final jaEnDecoder = _resolveCandidateFile(baseDir, [
      'nmt_ja_en/decoder_model_quantized.onnx',
      'nmt_ja_en/decoder_model.onnx',
      'nmt_ja_en/decoder.onnx',
    ]);
    final jaEnSourceSpm = _resolveCandidateFile(baseDir, [
      'nmt_ja_en/source.spm',
    ]);
    final jaEnTargetSpm = _resolveCandidateFile(baseDir, [
      'nmt_ja_en/target.spm',
    ]);
    final jaEnVocab = _resolveCandidateFile(baseDir, [
      'nmt_ja_en/vocab.json',
    ]);
    final jaEnTokenizerConfig = _resolveCandidateFile(baseDir, [
      'nmt_ja_en/tokenizer_config.json',
    ]);

    final enJaEncoderPath = p.normalize(p.absolute(enJaEncoder.path));
    final enJaDecoderPath = p.normalize(p.absolute(enJaDecoder.path));
    final enJaSourceSpmPath = p.normalize(p.absolute(enJaSourceSpm.path));
    final enJaTargetSpmPath = p.normalize(p.absolute(enJaTargetSpm.path));
    final enJaVocabPath = p.normalize(p.absolute(enJaVocab.path));
    final enJaTokenizerConfigPath = p.normalize(p.absolute(enJaTokenizerConfig.path));

    final jaEnEncoderPath = p.normalize(p.absolute(jaEnEncoder.path));
    final jaEnDecoderPath = p.normalize(p.absolute(jaEnDecoder.path));
    final jaEnSourceSpmPath = p.normalize(p.absolute(jaEnSourceSpm.path));
    final jaEnTargetSpmPath = p.normalize(p.absolute(jaEnTargetSpm.path));
    final jaEnVocabPath = p.normalize(p.absolute(jaEnVocab.path));
    final jaEnTokenizerConfigPath = p.normalize(p.absolute(jaEnTokenizerConfig.path));

    for (final extractedPath in [enJaEncoderPath, enJaDecoderPath, jaEnEncoderPath, jaEnDecoderPath]) {
      if (!File(extractedPath).existsSync()) {
        throw Exception('CRITICAL FFI ERROR: Missing file at $extractedPath');
      }
    }

    return NmtModelPaths(
      enJa: NmtDirectionModelPaths(
        encoderPath: enJaEncoderPath,
        decoderPath: enJaDecoderPath,
        sourceSpmPath: enJaSourceSpmPath,
        targetSpmPath: enJaTargetSpmPath,
        vocabJsonPath: enJaVocabPath,
        tokenizerConfigJsonPath: enJaTokenizerConfigPath,
      ),
      jaEn: NmtDirectionModelPaths(
        encoderPath: jaEnEncoderPath,
        decoderPath: jaEnDecoderPath,
        sourceSpmPath: jaEnSourceSpmPath,
        targetSpmPath: jaEnTargetSpmPath,
        vocabJsonPath: jaEnVocabPath,
        tokenizerConfigJsonPath: jaEnTokenizerConfigPath,
      ),
    );
  }

  /// Generates and resolves absolute file paths for English and Japanese Sherpa TTS model components.
  Future<TtsModelPaths> getTtsModelPaths() async {
    final baseDir = await modelsDirectory;

    final enModel = _resolveCandidateFile(baseDir, [
      'tts_en/en_US-lessac-medium.onnx',
      'tts_en/model.onnx',
      'tts_en/vits-piper-en_US-lessac-medium.onnx',
      'vits-piper-en_US-lessac-medium.onnx',
      'en_US-lessac-medium.onnx',
      'tts/en_US-lessac-medium.onnx',
    ]);
    final enTokens = _resolveCandidateFile(baseDir, [
      'tts_en/tokens.txt',
      'tokens.txt',
      'tts/tokens.txt',
    ]);

    final jaModel = _resolveCandidateFile(baseDir, [
      'tts_ja/model (1).onnx',
      'tts_ja/model.onnx',
      'tts_ja/vits-melo-tts-jp.onnx',
      'vits-melo-tts-jp.onnx',
      'model.onnx',
      'tts/model.onnx',
    ]);
    final jaTokens = _resolveCandidateFile(baseDir, [
      'tts_ja/tokens (2).txt',
      'tts_ja/tokens.txt',
      'tokens.txt',
      'tts/tokens.txt',
    ]);
    final jaLexicon = _resolveCandidateFile(baseDir, [
      'tts_ja/lexicon.txt',
      'lexicon.txt',
      'tts/lexicon.txt',
    ]);

    final enLexicon = _resolveCandidateFile(baseDir, [
      'tts_en/lexicon.txt',
      'lexicon.txt',
      'tts/lexicon.txt',
    ]);
    final enDataDirCandidate = Directory(p.normalize(p.join(baseDir.path, 'tts_en', 'espeak-ng-data')));
    final enDataDir = enDataDirCandidate.existsSync() ? enDataDirCandidate.path : null;

    final enModelPath = p.normalize(p.absolute(enModel.path));
    final enTokensPath = p.normalize(p.absolute(enTokens.path));
    final enLexiconPath = enLexicon.existsSync() ? p.normalize(p.absolute(enLexicon.path)) : null;
    final jaModelPath = p.normalize(p.absolute(jaModel.path));
    final jaTokensPath = p.normalize(p.absolute(jaTokens.path));
    final jaLexiconPath = jaLexicon.existsSync() ? p.normalize(p.absolute(jaLexicon.path)) : null;

    for (final extractedPath in [enModelPath, enTokensPath, jaModelPath, jaTokensPath]) {
      if (!File(extractedPath).existsSync()) {
        throw Exception('CRITICAL FFI ERROR: Missing file at $extractedPath');
      }
    }

    return TtsModelPaths(
      en: TtsDirectionModelPaths(
        modelPath: enModelPath,
        tokensPath: enTokensPath,
        lexiconPath: enLexiconPath,
        dataDir: enDataDir,
      ),
      ja: TtsDirectionModelPaths(
        modelPath: jaModelPath,
        tokensPath: jaTokensPath,
        lexiconPath: jaLexiconPath,
      ),
    );
  }

  File _resolveCandidateFile(Directory baseDir, List<String> relativePaths) {
    for (final rel in relativePaths) {
      final cleanPath = p.normalize(p.join(baseDir.path, rel));
      final f = File(cleanPath);
      if (f.existsSync()) return f;
    }
    return File(p.normalize(p.join(baseDir.path, relativePaths.first)));
  }

  /// Ensures models directory is created and extracts all model files from asset bundle.
  Future<List<File>> ensureModelsExtracted({bool overwrite = false}) async {
    if (kIsWeb) return [];
    final base = await modelsDirectory;
    AppLogger.info('ModelLoader', 'Models local directory ready: ${base.path}');
    return await extractModelAssets(overwrite: overwrite);
  }
}
