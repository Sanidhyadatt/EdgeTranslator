import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/app_logger.dart';

/// Strongly typed container holding absolute file paths for Sherpa ASR model components.
class AsrModelPaths {
  final String encoderPath;
  final String decoderPath;
  final String tokensPath;
  final String? vadPath;

  const AsrModelPaths({
    required this.encoderPath,
    required this.decoderPath,
    required this.tokensPath,
    this.vadPath,
  });
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
/// from Flutter asset bundles to the device's application documents directory at runtime.
///
/// Native C/FFI engines (Sherpa-ONNX & ONNX Runtime) require absolute filesystem paths
/// and cannot read directly from compressed APK/app bundle assets.
class ModelLoader {
  const ModelLoader();

  /// Gets the local directory reserved for on-device machine learning models
  /// in the device's application document directory.
  Future<Directory> get modelsDirectory async {
    if (kIsWeb) return Directory('');
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

  /// Extracts .onnx, .spm, .json, and .txt model files from the Flutter asset bundle to
  /// the device's application documents directory at runtime.
  Future<List<File>> extractModelAssets({bool overwrite = false}) async {
    if (kIsWeb) return [];
    final baseDir = await modelsDirectory;
    final List<File> extractedFiles = [];

    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = manifest.listAssets();

      // Filter for .onnx, .spm, .json, and .txt files belonging to models
      final modelAssets = allAssets.where((assetKey) {
        final lower = assetKey.toLowerCase();
        final hasModelExtension = lower.endsWith('.onnx') ||
            lower.endsWith('.spm') ||
            lower.endsWith('.json') ||
            lower.endsWith('.txt');
        final isInModelsDir = assetKey.startsWith(AppConstants.modelsBasePath) ||
            assetKey.contains('models');
        return hasModelExtension && isInModelsDir;
      }).toList();

      AppLogger.info('ModelLoader', 'Found ${modelAssets.length} model assets (.onnx/.spm/.json/.txt) in bundle.');

      for (final assetPath in modelAssets) {
        try {
          final file = await copyAssetToStorage(assetPath, overwrite: overwrite);
          extractedFiles.add(file);
        } catch (e) {
          AppLogger.error('ModelLoader', 'Failed extracting asset: $assetPath', e);
        }
      }
    } catch (e, st) {
      AppLogger.error('ModelLoader', 'Failed reading AssetManifest from bundle', e, st);
    }

    // Step 1: Strict File Existence Guards
    for (final file in extractedFiles) {
      final extractedPath = p.normalize(p.absolute(file.path));
      final lower = extractedPath.toLowerCase();
      if (lower.endsWith('.onnx') || lower.endsWith('.txt')) {
        if (!File(extractedPath).existsSync()) {
          throw Exception('CRITICAL FFI ERROR: Missing file at $extractedPath');
        }
      }
    }

    AppLogger.info('ModelLoader', 'Extracted ${extractedFiles.length} model files to: ${baseDir.path}');
    return extractedFiles;
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
    if (relativePath.startsWith('${AppConstants.modelsBasePath}/')) {
      relativePath = relativePath.substring('${AppConstants.modelsBasePath}/'.length);
    } else if (relativePath.startsWith('assets/models/')) {
      relativePath = relativePath.substring('assets/models/'.length);
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

    try {
      final byteData = await rootBundle.load(assetPath);
      final buffer = byteData.buffer;
      await targetFile.writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        flush: true,
      );
      AppLogger.info('ModelLoader', 'Extracted asset to: ${targetFile.path} (${byteData.lengthInBytes} bytes)');
    } catch (e) {
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

    final encoderPath = p.normalize(p.absolute(encoder.path));
    final decoderPath = p.normalize(p.absolute(decoder.path));
    final tokensPath = p.normalize(p.absolute(tokens.path));
    final vadPath = p.normalize(p.absolute(vad.path));

    for (final extractedPath in [encoderPath, decoderPath, tokensPath]) {
      if (!File(extractedPath).existsSync()) {
        throw Exception('CRITICAL FFI ERROR: Missing file at $extractedPath');
      }
    }

    return AsrModelPaths(
      encoderPath: encoderPath,
      decoderPath: decoderPath,
      tokensPath: tokensPath,
      vadPath: vadPath,
    );
  }

  /// Generates and resolves absolute file paths for MarianMT NMT model components.
  Future<NmtModelPaths> getNmtModelPaths() async {
    final baseDir = await modelsDirectory;

    final enJaEncoder = _resolveCandidateFile(baseDir, [
      'nmt_en_ja/encoder_model_quantized (1).onnx',
      'nmt_en_ja/encoder_model_quantized.onnx',
      'nmt_en_ja/encoder_model.onnx',
      'nmt_en_ja/encoder.onnx',
    ]);
    final enJaDecoder = _resolveCandidateFile(baseDir, [
      'nmt_en_ja/decoder_model_quantized (1).onnx',
      'nmt_en_ja/decoder_model_quantized.onnx',
      'nmt_en_ja/decoder_model.onnx',
      'nmt_en_ja/decoder.onnx',
    ]);
    final enJaSourceSpm = _resolveCandidateFile(baseDir, [
      'nmt_en_ja/source (1).spm',
      'nmt_en_ja/source.spm',
    ]);
    final enJaTargetSpm = _resolveCandidateFile(baseDir, [
      'nmt_en_ja/target (1).spm',
      'nmt_en_ja/target.spm',
    ]);
    final enJaVocab = _resolveCandidateFile(baseDir, [
      'nmt_en_ja/vocab (1).json',
      'nmt_en_ja/vocab.json',
    ]);
    final enJaTokenizerConfig = _resolveCandidateFile(baseDir, [
      'nmt_en_ja/tokenizer_config (1).json',
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
