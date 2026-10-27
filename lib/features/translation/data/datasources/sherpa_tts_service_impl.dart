// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../../core/utils/app_logger.dart';
import '../../domain/services/tts_service.dart';
import 'model_loader.dart';

/// Sherpa-ONNX Text-to-Speech (TTS) engine foundation supporting Japanese and English synthesis.
class SherpaTtsServiceImpl implements TtsService {
  final String? modelPath;
  final String? lexiconPath;
  final String? tokensPath;
  final String? dataDir;
  final ModelLoader _modelLoader;

  sherpa.OfflineTts? _enTts;
  sherpa.OfflineTts? _jaTts;

  bool _isEnNativeActive = false;
  bool _isJaNativeActive = false;
  bool _initialized = false;

  SherpaTtsServiceImpl({
    this.modelPath,
    this.lexiconPath,
    this.tokensPath,
    this.dataDir,
    ModelLoader? modelLoader,
  }) : _modelLoader = modelLoader ?? const ModelLoader();

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    try {
      try {
        sherpa.initBindings();
      } catch (e) {
        AppLogger.warning('SherpaTtsService', 'sherpa_onnx dynamic bindings not available: $e');
      }

      // Extract model assets if needed
      try {
        await _modelLoader.extractTtsModels();
      } catch (e) {
        AppLogger.warning('SherpaTtsService', 'TTS asset extraction notice: $e');
      }

      final ttsPaths = await _modelLoader.getTtsModelPaths();

      // Resolve English TTS files
      final enModelFile = File(ttsPaths.en.modelPath);
      final enTokensFile = File(ttsPaths.en.tokensPath);
      final enLexiconPath = ttsPaths.en.lexiconPath ?? p.join(enModelFile.parent.path, 'lexicon.txt');
      final enLexiconFile = File(enLexiconPath);
      final enDataDir = ttsPaths.en.dataDir ?? '';
      final hasEnLexicon = enLexiconFile.existsSync();
      final hasEnDataDir = enDataDir.isNotEmpty && Directory(enDataDir).existsSync();

      // Resolve Japanese TTS files
      final jaModelPath = modelPath ?? ttsPaths.ja.modelPath;
      final jaTokensPath = tokensPath ?? ttsPaths.ja.tokensPath;
      final jaLexiconPath = lexiconPath ?? ttsPaths.ja.lexiconPath ?? '';
      final jaModelFile = File(jaModelPath);
      final jaTokensFile = File(jaTokensPath);

      print('=== [SherpaTtsServiceImpl] Initializing Sherpa-ONNX TTS Engines ===');
      print('  [EN] Model:   ${enModelFile.path} (exists: ${enModelFile.existsSync()})');
      print('  [EN] Tokens:  ${enTokensFile.path} (exists: ${enTokensFile.existsSync()})');
      print('  [JA] Model:   ${jaModelFile.path} (exists: ${jaModelFile.existsSync()})');
      print('  [JA] Tokens:  ${jaTokensFile.path} (exists: ${jaTokensFile.existsSync()})');
      print('  [JA] Lexicon: $jaLexiconPath (exists: ${File(jaLexiconPath).existsSync()})');

      // 1. Initialize English TTS (Piper VITS: en_US-lessac-medium.onnx + tokens.txt)
      if (enModelFile.existsSync() && enTokensFile.existsSync()) {
        if (!hasEnLexicon && !hasEnDataDir) {
          print('[FFI GUARD][TTS] WARNING: English Piper TTS model requires lexicon.txt or espeak-ng-data directory to prevent native C++ exit(-1). Skipping native initialization until lexicon/dataDir is provided.');
          AppLogger.warning('SherpaTtsService', 'English Piper TTS requires lexicon or dataDir. Skipping native C++ initialization to prevent crash.');
        } else {
          try {
            print('[FFI DEBUG][TTS] Instantiating native English OfflineTts:');
            print('  Model:   ${enModelFile.path}');
            print('  Tokens:  ${enTokensFile.path}');
            print('  Lexicon: ${hasEnLexicon ? enLexiconFile.path : ""}');
            print('  DataDir: $enDataDir');

            final enConfig = sherpa.OfflineTtsConfig(
              model: sherpa.OfflineTtsModelConfig(
                vits: sherpa.OfflineTtsVitsModelConfig(
                  model: enModelFile.path,
                  tokens: enTokensFile.path,
                  lexicon: hasEnLexicon ? enLexiconFile.path : '',
                  dataDir: enDataDir,
                ),
                numThreads: 2,
                debug: false,
                provider: 'cpu',
              ),
            );
            _enTts = sherpa.OfflineTts(enConfig);
            _isEnNativeActive = true;
            print('[FFI DEBUG][TTS] Successfully initialized native English OfflineTts.');
            AppLogger.info('SherpaTtsService', 'Initialized English (Piper VITS) TTS from: ${enModelFile.path}');
          } catch (e, st) {
            _isEnNativeActive = false;
            print('[FFI DEBUG][TTS] Failed initializing native English OfflineTts: $e');
            AppLogger.error('SherpaTtsService', 'Failed initializing English TTS engine', e, st);
          }
        }
      } else {
        print('[FFI DEBUG][TTS] English TTS weights missing on disk: ${enModelFile.path}');
        AppLogger.warning('SherpaTtsService', 'English TTS weights missing: ${enModelFile.path}');
      }

      // 2. Initialize Japanese TTS (Melo-VITS: model (1).onnx + tokens (2).txt + lexicon.txt)
      if (jaModelFile.existsSync() && jaTokensFile.existsSync()) {
        try {
          print('[FFI DEBUG][TTS] Instantiating native Japanese OfflineTts:');
          print('  Model:   ${jaModelFile.path}');
          print('  Tokens:  ${jaTokensFile.path}');
          print('  Lexicon: $jaLexiconPath');

          final jaConfig = sherpa.OfflineTtsConfig(
            model: sherpa.OfflineTtsModelConfig(
              vits: sherpa.OfflineTtsVitsModelConfig(
                model: jaModelFile.path,
                tokens: jaTokensFile.path,
                lexicon: jaLexiconPath,
                dataDir: dataDir ?? ttsPaths.ja.dataDir ?? '',
              ),
              numThreads: 2,
              debug: false,
              provider: 'cpu',
            ),
          );
          _jaTts = sherpa.OfflineTts(jaConfig);
          _isJaNativeActive = true;
          print('[FFI DEBUG][TTS] Successfully initialized native Japanese OfflineTts.');
          AppLogger.info('SherpaTtsService', 'Initialized Japanese (Melo-VITS) TTS from: ${jaModelFile.path}');
        } catch (e, st) {
          _isJaNativeActive = false;
          print('[FFI DEBUG][TTS] Failed initializing native Japanese OfflineTts: $e');
          AppLogger.error('SherpaTtsService', 'Failed initializing Japanese TTS engine', e, st);
        }
      } else {
        print('[FFI DEBUG][TTS] Japanese TTS weights missing on disk: ${jaModelFile.path}');
        AppLogger.warning('SherpaTtsService', 'Japanese TTS weights missing: ${jaModelFile.path}');
      }
    } catch (e, st) {
      AppLogger.error('SherpaTtsService', 'Initialization error in Sherpa TTS', e, st);
    }

    _initialized = true;
  }

  @override
  Future<String> synthesize(
    String text, {
    String language = 'ja',
    double speed = 1.0,
  }) async {
    if (kIsWeb) return '';
    if (!_initialized) {
      await initialize();
    }

    final cleanText = text.trim();
    if (cleanText.isEmpty) return '';

    final isJapanese = language.toLowerCase() == 'ja';
    final targetLangLabel = isJapanese ? 'Japanese (VITS)' : 'English (VITS)';

    AppLogger.info(
      'SherpaTtsService',
      'Synthesizing $targetLangLabel speech: "$cleanText" (speed: $speed)',
    );

    // 1. Attempt Japanese Native Synthesis
    if (isJapanese && _isJaNativeActive && _jaTts != null) {
      try {
        final audio = _jaTts!.generate(text: cleanText, speed: speed);
        if (audio.samples.isNotEmpty) {
          final wavPath = await _saveToWavFile(audio.samples, audio.sampleRate, 'tts_ja');
          AppLogger.info('SherpaTtsService', 'Synthesized ${audio.samples.length} Japanese audio samples to: $wavPath');
          return wavPath;
        }
      } catch (err, st) {
        AppLogger.error('SherpaTtsService', 'Native Japanese TTS generation error', err, st);
      }
    }

    // 2. Attempt English Native Synthesis
    if (!isJapanese && _isEnNativeActive && _enTts != null) {
      try {
        final audio = _enTts!.generate(text: cleanText, speed: speed);
        if (audio.samples.isNotEmpty) {
          final wavPath = await _saveToWavFile(audio.samples, audio.sampleRate, 'tts_en');
          AppLogger.info('SherpaTtsService', 'Synthesized ${audio.samples.length} English audio samples to: $wavPath');
          return wavPath;
        }
      } catch (err, st) {
        AppLogger.error('SherpaTtsService', 'Native English TTS generation error', err, st);
      }
    }

    // 3. Fallback: generate a dummy silent WAV file for UI testing and headless environments
    return await _generateFallbackWav(cleanText, language: language);
  }

  /// Writes Float32 PCM audio samples to a standard 16-bit PCM .wav file.
  Future<String> _saveToWavFile(Float32List samples, int sampleRate, String prefix) async {
    if (kIsWeb) return '';
    final tempDir = Directory.systemTemp;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final wavFile = File(p.join(tempDir.path, '${prefix}_$timestamp.wav'));

    const numChannels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    const blockAlign = numChannels * (bitsPerSample ~/ 8);
    final subChunk2Size = samples.length * (bitsPerSample ~/ 8);
    final chunkSize = 36 + subChunk2Size;

    final bytes = BytesBuilder();

    // RIFF header
    bytes.add(utf8.encode('RIFF'));
    bytes.add(_int32ToBytes(chunkSize));
    bytes.add(utf8.encode('WAVE'));

    // "fmt " sub-chunk
    bytes.add(utf8.encode('fmt '));
    bytes.add(_int32ToBytes(16)); // PCM subchunk size
    bytes.add(_int16ToBytes(1));  // Format 1 = PCM
    bytes.add(_int16ToBytes(numChannels));
    bytes.add(_int32ToBytes(sampleRate));
    bytes.add(_int32ToBytes(byteRate));
    bytes.add(_int16ToBytes(blockAlign));
    bytes.add(_int16ToBytes(bitsPerSample));

    // "data" sub-chunk
    bytes.add(utf8.encode('data'));
    bytes.add(_int32ToBytes(subChunk2Size));

    final byteData = ByteData(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i].clamp(-1.0, 1.0);
      final intSample = (sample < 0 ? sample * 32768 : sample * 32767).toInt();
      byteData.setInt16(i * 2, intSample, Endian.little);
    }
    bytes.add(byteData.buffer.asUint8List());

    await wavFile.writeAsBytes(bytes.toBytes(), flush: true);
    return wavFile.path;
  }

  Future<String> _generateFallbackWav(String text, {required String language}) async {
    // 0.5s of gentle audio placeholder for headless/mock environments
    const sampleRate = 16000;
    const durationSec = 0.5;
    final numSamples = (sampleRate * durationSec).toInt();
    final samples = Float32List(numSamples);
    return await _saveToWavFile(samples, sampleRate, 'tts_fallback_$language');
  }

  Uint8List _int16ToBytes(int value) {
    return Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.little);
  }

  Uint8List _int32ToBytes(int value) {
    return Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.little);
  }

  @override
  Future<void> dispose() async {
    try {
      _enTts?.free();
      _jaTts?.free();
    } catch (_) {}
    _enTts = null;
    _jaTts = null;
    _isEnNativeActive = false;
    _isJaNativeActive = false;
    _initialized = false;
    AppLogger.info('SherpaTtsService', 'Disposed Sherpa-ONNX TTS engines');
  }
}
