import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:edge_translator/core/constants/app_constants.dart';
import 'package:edge_translator/features/translation/data/datasources/model_loader.dart';
import 'package:edge_translator/features/translation/data/datasources/sherpa_asr_service_impl.dart';
import 'package:edge_translator/features/translation/data/datasources/onnx_nmt_service_impl.dart';
import 'package:edge_translator/features/translation/data/datasources/sherpa_tts_service_impl.dart';

/// Ensures Windows unit tests bind ONNX Runtime 1.28.2 and Sherpa-ONNX DLLs from
/// `sherpa_onnx_windows` instead of the older `C:\Windows\System32\onnxruntime.dll` (IR v9 max).
void _preloadWindowsNativeLibraries() {
  if (!Platform.isWindows) return;

  var dir = Directory.current.absolute;
  File? pkgConfigFile;
  for (var depth = 0; depth < 5; depth++) {
    final candidate = File(p.join(dir.path, '.dart_tool', 'package_config.json'));
    if (candidate.existsSync()) {
      pkgConfigFile = candidate;
      break;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  if (pkgConfigFile == null) return;

  final decoded = jsonDecode(pkgConfigFile.readAsStringSync()) as Map<String, dynamic>;
  final packages = decoded['packages'] as List<dynamic>? ?? const [];
  String? rootUri;
  for (final entry in packages) {
    if (entry is Map && entry['name'] == 'sherpa_onnx_windows') {
      rootUri = entry['rootUri'] as String?;
      break;
    }
  }
  if (rootUri == null || rootUri.isEmpty) return;

  final resolvedRoot = pkgConfigFile.parent.uri.resolve(rootUri);
  final winBinDir = p.join(resolvedRoot.toFilePath(), 'windows');
  for (final dllName in const [
    'onnxruntime_providers_shared.dll',
    'onnxruntime.dll',
    'sherpa-onnx-c-api.dll',
    'sherpa-onnx-cxx-api.dll',
  ]) {
    final dllPath = p.join(winBinDir, dllName);
    if (File(dllPath).existsSync()) {
      ffi.DynamicLibrary.open(dllPath);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _preloadWindowsNativeLibraries();

  group('ModelLoader Extraction & Sherpa ASR Initialization Tests', () {
    test('Verifies ONNX models live in :ai_models AI pack and are NOT duplicated in rootBundle', () async {
      expect(
        () => rootBundle.load('assets/models/${AppConstants.senseVoiceModelFile}'),
        throwsFlutterError,
      );

      final packRoot = p.join(
        Directory.current.path,
        'android',
        'ai_models',
        'src',
        'main',
        'assets',
        'models',
      );
      expect(Directory(packRoot).existsSync(), isTrue, reason: 'AI pack model directory must exist at $packRoot');

      final svModel = File(p.join(packRoot, AppConstants.senseVoiceModelFile));
      final svTokens = File(p.join(packRoot, AppConstants.senseVoiceTokensFile));
      final sileroVad = File(p.join(packRoot, 'silero_vad.onnx'));
      final enJaEnc = File(p.join(packRoot, 'nmt_en_ja', 'encoder_model_quantized.onnx'));
      final enJaDec = File(p.join(packRoot, 'nmt_en_ja', 'decoder_model_quantized.onnx'));
      final jaEnEnc = File(p.join(packRoot, 'nmt_ja_en', 'encoder_model_quantized.onnx'));
      final jaEnDec = File(p.join(packRoot, 'nmt_ja_en', 'decoder_model_quantized.onnx'));
      final enTts = File(p.join(packRoot, 'tts_en', 'en_US-lessac-medium.onnx'));
      final espeakDict = File(p.join(packRoot, 'tts_en', 'espeak-ng-data', 'en_dict'));
      final jaTts = File(p.join(packRoot, 'tts_ja', 'model (1).onnx'));
      final jaTokens = File(p.join(packRoot, 'tts_ja', 'tokens (2).txt'));

      for (final file in [
        svModel,
        svTokens,
        sileroVad,
        enJaEnc,
        enJaDec,
        jaEnEnc,
        jaEnDec,
        enTts,
        espeakDict,
        jaTts,
        jaTokens,
      ]) {
        expect(file.existsSync(), isTrue, reason: 'Expected model file missing: ${file.path}');
      }
      expect(svModel.lengthSync(), greaterThan(200 * 1024 * 1024));
      expect(svTokens.lengthSync(), greaterThan(200 * 1024));
      expect(espeakDict.lengthSync(), greaterThan(100 * 1024));
    });

    test('Android MethodChannel ModelLoader delegates extraction and handles AI_PACK_MISSING / INSUFFICIENT_STORAGE', () async {
      final tempDir = await Directory.systemTemp.createTemp('ikho_ai_pack_test_');
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ModelLoader.aiModelsChannel, null);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      // 1. Missing AI pack error propagates cleanly
      messenger.setMockMethodCallHandler(ModelLoader.aiModelsChannel, (call) async {
        expect(call.method, 'extractModels');
        throw PlatformException(code: 'AI_PACK_MISSING', message: 'Pack not installed');
      });
      final loader = ModelLoader(
        customModelsDirectory: tempDir,
        useAndroidChannel: true,
      );
      await expectLater(
        loader.extractModelAssets(),
        throwsA(
          isA<ModelExtractionException>().having((e) => e.code, 'code', 'AI_PACK_MISSING'),
        ),
      );

      // 2. Insufficient storage error propagates cleanly
      messenger.setMockMethodCallHandler(ModelLoader.aiModelsChannel, (call) async {
        throw PlatformException(code: 'INSUFFICIENT_STORAGE', message: 'Disk full');
      });
      await expectLater(
        loader.extractModelAssets(),
        throwsA(
          isA<ModelExtractionException>().having((e) => e.code, 'code', 'INSUFFICIENT_STORAGE'),
        ),
      );

      // 3. Successful extraction returns concrete file list verified on disk
      final dummyOnnx = File(p.join(tempDir.path, 'asr', 'sense-voice.int8.onnx'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(const [1, 2, 3, 4]);
      final dummyTokens = File(p.join(tempDir.path, 'asr', 'sense-voice-tokens.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<s> 0\n');

      messenger.setMockMethodCallHandler(ModelLoader.aiModelsChannel, (call) async {
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        expect(args['targetDir'], tempDir.path);
        return <String>[dummyOnnx.path, dummyTokens.path];
      });

      final files = await loader.extractModelAssets();
      expect(files.length, 2);
      final asrPaths = await loader.getAsrModelPaths();
      expect(asrPaths.hasSenseVoice, isTrue);
      expect(asrPaths.senseVoiceModelPath, p.normalize(p.absolute(dummyOnnx.path)));
    });

    test('ModelLoader extracts files and SherpaAsrServiceImpl resolves SenseVoice paths without file-not-found errors', () async {
      const loader = ModelLoader();
      final targetDir = await loader.modelsDirectory;

      // Extract model assets
      final extractedFiles = await loader.extractModelAssets(overwrite: true);
      expect(extractedFiles, isNotEmpty);

      // Verify SenseVoice & English espeak-ng-data exist in modelsDirectory
      final expectedSvModel = File(p.join(targetDir.path, 'asr', 'sense-voice.int8.onnx'));
      final expectedSvTokens = File(p.join(targetDir.path, 'asr', 'sense-voice-tokens.txt'));
      final expectedEspeakDict = File(p.join(targetDir.path, 'tts_en', 'espeak-ng-data', 'en_dict'));

      expect(await expectedSvModel.exists(), isTrue, reason: 'SenseVoice model must exist at ${expectedSvModel.path}');
      expect(await expectedSvTokens.exists(), isTrue, reason: 'SenseVoice tokens must exist at ${expectedSvTokens.path}');
      expect(await expectedEspeakDict.exists(), isTrue, reason: 'English espeak-ng-data must exist at ${expectedEspeakDict.path}');

      expect(await expectedSvModel.length(), greaterThan(200 * 1024 * 1024));
      expect(await expectedSvTokens.length(), greaterThan(200 * 1024));

      // Verify getAsrModelPaths and getTtsModelPaths resolve these exact files
      final asrPaths = await loader.getAsrModelPaths();
      expect(asrPaths.hasSenseVoice, isTrue);
      expect(asrPaths.senseVoiceModelPath, expectedSvModel.path);
      expect(asrPaths.senseVoiceTokensPath, expectedSvTokens.path);

      final ttsPaths = await loader.getTtsModelPaths();
      expect(ttsPaths.en.dataDir, isNotNull);
      expect(Directory(ttsPaths.en.dataDir!).existsSync(), isTrue);

      // Verify SherpaAsrServiceImpl initializes without file-not-found errors
      final asrService = SherpaAsrServiceImpl(modelLoader: loader);
      await asrService.initialize();

      // Ensure transcribe handles silent input gracefully
      final sampleResult = await asrService.transcribe(Float32List(16000));
      expect(sampleResult, isNotNull);
      expect(sampleResult.language, 'en');

      await asrService.dispose();
    });

    test('ModelLoader extracts MarianMT NMT assets and OnnxNmtServiceImpl initializes gracefully', () async {
      const loader = ModelLoader();
      final targetDir = await loader.modelsDirectory;
      expect(targetDir.existsSync(), isTrue);

      final extractedFiles = await loader.extractModelAssets();
      expect(extractedFiles, isNotEmpty);

      // Verify NMT model paths are resolved
      final nmtPaths = await loader.getNmtModelPaths();
      expect(nmtPaths.enJa.encoderPath, contains('nmt_en_ja'));
      expect(nmtPaths.enJa.decoderPath, contains('nmt_en_ja'));
      expect(nmtPaths.jaEn.encoderPath, contains('nmt_ja_en'));
      expect(nmtPaths.jaEn.decoderPath, contains('nmt_ja_en'));

      // Verify files were extracted to targetDir
      final enJaEncFile = File(nmtPaths.enJa.encoderPath);
      final jaEnEncFile = File(nmtPaths.jaEn.encoderPath);
      expect(await enJaEncFile.exists(), isTrue);
      expect(await jaEnEncFile.exists(), isTrue);

      // Verify OnnxNmtServiceImpl initializes and translates
      final nmtService = OnnxNmtServiceImpl(modelLoader: loader);
      await nmtService.initialize();

      final enResult = await nmtService.translate('Where is Shibuya station?', sourceLang: 'en', targetLang: 'ja');
      expect(enResult, contains('渋谷'));

      final jaResult = await nmtService.translate('こんにちは', sourceLang: 'ja', targetLang: 'en');
      expect(jaResult.toLowerCase(), contains('hello'));

      await nmtService.dispose();
    });

    test('ModelLoader extracts TTS assets and SherpaTtsServiceImpl initializes gracefully', () async {
      const loader = ModelLoader();
      final targetDir = await loader.modelsDirectory;
      expect(targetDir.existsSync(), isTrue);

      final extractedFiles = await loader.extractTtsModels();
      expect(extractedFiles, isNotEmpty);

      final ttsPaths = await loader.getTtsModelPaths();
      expect(ttsPaths.en.modelPath, contains('tts_en'));
      expect(ttsPaths.en.tokensPath, contains('tts_en'));
      expect(ttsPaths.ja.modelPath, contains('tts_ja'));
      expect(ttsPaths.ja.tokensPath, contains('tts_ja'));

      final ttsService = SherpaTtsServiceImpl(modelLoader: loader);
      await ttsService.initialize();

      final jaAudioPath = await ttsService.synthesize('こんにちは', language: 'ja');
      expect(jaAudioPath, isNotEmpty);
      expect(File(jaAudioPath).existsSync(), isTrue);

      final enAudioPath = await ttsService.synthesize('Hello!', language: 'en');
      expect(enAudioPath, isNotEmpty);
      expect(File(enAudioPath).existsSync(), isTrue);

      await ttsService.dispose();
    });
  });
}


