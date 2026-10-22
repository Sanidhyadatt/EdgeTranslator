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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelLoader Extraction & Sherpa ASR Initialization Tests', () {
    test('Verifies Whisper INT8 model assets are present in rootBundle', () async {
      final encoderBytes = await rootBundle.load('assets/models/tiny-encoder.int8.onnx');
      expect(encoderBytes.lengthInBytes, greaterThan(10 * 1024 * 1024)); // ~12.9 MB

      final decoderBytes = await rootBundle.load('assets/models/tiny-decoder.int8.onnx');
      expect(decoderBytes.lengthInBytes, greaterThan(80 * 1024 * 1024)); // ~89.8 MB

      final tokensBytes = await rootBundle.load('assets/models/tiny-tokens.txt');
      expect(tokensBytes.lengthInBytes, greaterThan(500 * 1024)); // ~816 KB
    });

    test('ModelLoader extracts files and SherpaAsrServiceImpl resolves absolute paths without file-not-found errors', () async {
      const loader = ModelLoader();
      final targetDir = await loader.modelsDirectory;

      // Extract model assets
      final extractedFiles = await loader.extractModelAssets(overwrite: true);
      expect(extractedFiles, isNotEmpty);

      // Verify files exist in modelsDirectory with expected file names and non-zero sizes
      final expectedEncoder = File(p.join(targetDir.path, AppConstants.whisperEncoderFile));
      final expectedDecoder = File(p.join(targetDir.path, AppConstants.whisperDecoderFile));
      final expectedTokens = File(p.join(targetDir.path, AppConstants.whisperTokensFile));

      expect(await expectedEncoder.exists(), isTrue, reason: 'Encoder must exist at ${expectedEncoder.path}');
      expect(await expectedDecoder.exists(), isTrue, reason: 'Decoder must exist at ${expectedDecoder.path}');
      expect(await expectedTokens.exists(), isTrue, reason: 'Tokens must exist at ${expectedTokens.path}');

      expect(await expectedEncoder.length(), greaterThan(10 * 1024 * 1024));
      expect(await expectedDecoder.length(), greaterThan(80 * 1024 * 1024));
      expect(await expectedTokens.length(), greaterThan(500 * 1024));

      // Verify getAsrModelPaths resolves these exact files
      final asrPaths = await loader.getAsrModelPaths();
      expect(asrPaths.encoderPath, expectedEncoder.path);
      expect(asrPaths.decoderPath, expectedDecoder.path);
      expect(asrPaths.tokensPath, expectedTokens.path);

      // Verify SherpaAsrServiceImpl initializes without file-not-found errors
      final asrService = SherpaAsrServiceImpl(modelLoader: loader);
      // initialize() should not throw any file-not-found error
      await asrService.initialize();

      // Ensure transcribe executes gracefully
      final sampleResult = await asrService.transcribe(Float32List(16000));
      expect(sampleResult.text, isNotEmpty);
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
      expect(enResult, isNotEmpty);

      final jaResult = await nmtService.translate('こんにちは', sourceLang: 'ja', targetLang: 'en');
      expect(jaResult, isNotEmpty);

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
