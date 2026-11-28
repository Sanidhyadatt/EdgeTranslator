// ignore_for_file: avoid_print
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/background_worker.dart';
import '../../../../core/utils/device_profile.dart';
import '../../../../core/utils/ort_utils.dart';
import '../../../../core/utils/wav_writer.dart';
import '../../domain/services/tts_service.dart';
import 'japanese_melo_g2p.dart';
import 'model_loader.dart';

/// Offline Text-to-Speech (TTS) engine supporting Japanese (Melo-VITS via ONNX Runtime)
/// and English (Piper VITS via Sherpa-ONNX when lexicon/espeak-ng-data is present).
///
/// Runs model loading, G2P, neural synthesis, and PCM16 WAV encoding inside a
/// dedicated [BackgroundWorker] isolate, supports per-language lazy loading on
/// low-end devices, and caches recent synthesized WAV files via a bounded LRU.
class SherpaTtsServiceImpl implements TtsService {
  static const int _maxWavCacheEntries = 16;

  final String? modelPath;
  final String? lexiconPath;
  final String? tokensPath;
  final String? dataDir;
  final ModelLoader _modelLoader;

  BackgroundWorker? _worker;
  Future<void>? _configFuture;
  Future<void>? _initFuture;
  bool _configPrepared = false;

  bool _hasEnFiles = false;
  bool _hasJaFiles = false;
  bool _isEnNativeActive = false;
  bool _isJaNativeActive = false;
  bool _initialized = false;
  bool _disposed = false;
  String? _lastInitError;

  Map<String, String>? _enSpec;
  Map<String, String>? _jaSpec;

  int _wavCounter = 0;
  final LinkedHashMap<String, String> _wavCache = LinkedHashMap<String, String>();
  final Map<String, Future<String>> _inFlightSyntheses = {};

  String? get lastInitError => _lastInitError;

  /// Indicates that this service manages and cleans up its synthesized WAV files.
  bool get managesTempFiles => true;

  bool isAvailableFor(String language) {
    final isJa = language.toLowerCase().startsWith('ja');
    return isJa ? (_isJaNativeActive || _hasJaFiles) : (_isEnNativeActive || _hasEnFiles);
  }

  SherpaTtsServiceImpl({
    this.modelPath,
    this.lexiconPath,
    this.tokensPath,
    this.dataDir,
    ModelLoader? modelLoader,
  }) : _modelLoader = modelLoader ?? const ModelLoader();

  @override
  Future<void> initialize() {
    if (_initialized && !_disposed && (_isEnNativeActive || _isJaNativeActive)) {
      return Future.value();
    }
    _disposed = false;
    return _initFuture ??= _doInitialize(loadEn: true, loadJa: true).whenComplete(() {
      if (!_disposed && (_isEnNativeActive || _isJaNativeActive)) {
        _initialized = true;
      }
      _initFuture = null;
    });
  }

  /// Lazily prepares and loads only the requested [language] (`'en'` or `'ja'`),
  /// avoiding loading ~235 MB of both TTS models upfront on low-end phones.
  Future<void> initializeForLanguage(String language) async {
    if (kIsWeb || _disposed) return;
    final isJa = language.toLowerCase().startsWith('ja');
    if (isJa && _isJaNativeActive) return;
    if (!isJa && _isEnNativeActive) return;

    await _ensureConfigured();
    if (_disposed || _worker == null || _worker!.isClosed) return;
    if (isJa && !_hasJaFiles) return;
    if (!isJa && !_hasEnFiles) return;

    final res = await _worker!.request({
      'op': 'ensureLang',
      'language': isJa ? 'ja' : 'en',
    }) as Map<Object?, Object?>;
    if (_disposed) return;

    _isEnNativeActive = res['enActive'] == true;
    _isJaNativeActive = res['jaActive'] == true;
    if (_isEnNativeActive || _isJaNativeActive) {
      _initialized = true;
    }
  }

  Future<void> _ensureConfigured() {
    if (_configPrepared && _worker != null && !_worker!.isClosed) {
      return Future.value();
    }
    return _configFuture ??= _prepareConfiguration().whenComplete(() {
      _configFuture = null;
    });
  }

  Future<void> _prepareConfiguration() async {
    if (kIsWeb || _disposed) return;
    _lastInitError = null;

    try {
      if (modelPath == null) {
        await _modelLoader.extractTtsModels();
      }
      if (_disposed) return;

      final ttsPaths = await _modelLoader.getTtsModelPaths();
      if (_disposed) return;

      final enModelFile = File(ttsPaths.en.modelPath);
      final enTokensFile = File(ttsPaths.en.tokensPath);
      final enLexiconPath = ttsPaths.en.lexiconPath ?? p.join(enModelFile.parent.path, 'lexicon.txt');
      final enLexiconFile = File(enLexiconPath);
      final enDataDir = dataDir ?? ttsPaths.en.dataDir ?? '';
      final hasEnLexicon = enLexiconFile.existsSync();
      final hasEnDataDir = enDataDir.isNotEmpty && Directory(enDataDir).existsSync();

      final jaModelPath = modelPath ?? ttsPaths.ja.modelPath;
      final jaTokensPath = tokensPath ?? ttsPaths.ja.tokensPath;
      final jaLexiconPath = lexiconPath ?? ttsPaths.ja.lexiconPath ?? '';
      final jaModelFile = File(jaModelPath);
      final jaTokensFile = File(jaTokensPath);

      _hasEnFiles = enModelFile.existsSync() &&
          enTokensFile.existsSync() &&
          (hasEnLexicon || hasEnDataDir);
      _hasJaFiles = jaModelFile.existsSync() && jaTokensFile.existsSync();

      _enSpec = _hasEnFiles
          ? {
              'model': enModelFile.path,
              'tokens': enTokensFile.path,
              'lexicon': hasEnLexicon ? enLexiconFile.path : '',
              'dataDir': enDataDir,
            }
          : null;
      _jaSpec = _hasJaFiles
          ? {
              'model': jaModelFile.path,
              'tokens': jaTokensFile.path,
              'lexicon': jaLexiconPath,
            }
          : null;

      if (!_hasEnFiles && !_hasJaFiles) {
        AppLogger.warning('SherpaTtsService', 'No native TTS weights resolved on disk.');
        _configPrepared = true;
        return;
      }

      final worker = await BackgroundWorker.spawn(_ttsWorkerHandler, debugName: 'ikho-tts');
      if (_disposed) {
        await worker.close(finalRequest: const {'op': 'dispose'});
        return;
      }
      _worker = worker;

      await worker.request({
        'op': 'configure',
        'threads': DeviceProfile.inferenceThreads,
        'lowEnd': DeviceProfile.isLowEnd,
        'enSpec': _enSpec,
        'jaSpec': _jaSpec,
      });

      if (_disposed) {
        await worker.close(finalRequest: const {'op': 'dispose'});
        _worker = null;
        return;
      }
      _configPrepared = true;
    } catch (e, st) {
      _lastInitError = e.toString();
      AppLogger.error('SherpaTtsService', 'Configuration error in Sherpa TTS', e, st);
    }
  }

  Future<void> _doInitialize({required bool loadEn, required bool loadJa}) async {
    if (kIsWeb) return;
    await _ensureConfigured();
    if (_disposed || _worker == null || _worker!.isClosed) return;

    try {
      if (loadJa && _hasJaFiles) {
        final res = await _worker!.request({
          'op': 'ensureLang',
          'language': 'ja',
        }) as Map<Object?, Object?>;
        _isEnNativeActive = res['enActive'] == true;
        _isJaNativeActive = res['jaActive'] == true;
      }
      if (loadEn && _hasEnFiles && !(_disposed || DeviceProfile.isLowEnd && _isJaNativeActive)) {
        final res = await _worker!.request({
          'op': 'ensureLang',
          'language': 'en',
        }) as Map<Object?, Object?>;
        _isEnNativeActive = res['enActive'] == true;
        _isJaNativeActive = res['jaActive'] == true;
      }
    } catch (e, st) {
      _lastInitError = e.toString();
      AppLogger.error('SherpaTtsService', 'Initialization error in Sherpa TTS', e, st);
    }
  }

  @override
  Future<String> synthesize(
    String text, {
    String language = 'ja',
    double speed = 1.0,
  }) async {
    if (kIsWeb || _disposed) return '';

    final cleanText = text.trim();
    if (cleanText.isEmpty) return '';

    final isJapanese = language.toLowerCase().startsWith('ja');
    final langKey = isJapanese ? 'ja' : 'en';
    final cacheKey = '$langKey|${speed.toStringAsFixed(2)}|$cleanText';

    final cachedPath = _wavCache.remove(cacheKey);
    if (cachedPath != null) {
      if (File(cachedPath).existsSync()) {
        _wavCache[cacheKey] = cachedPath;
        return cachedPath;
      }
    }

    final existingInFlight = _inFlightSyntheses[cacheKey];
    if (existingInFlight != null) {
      return existingInFlight;
    }

    final future = _performSynthesize(
      cleanText: cleanText,
      language: language,
      langKey: langKey,
      isJapanese: isJapanese,
      speed: speed,
      cacheKey: cacheKey,
    );
    _inFlightSyntheses[cacheKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightSyntheses[cacheKey], future)) {
        _inFlightSyntheses.remove(cacheKey);
      }
    }
  }

  Future<String> _performSynthesize({
    required String cleanText,
    required String language,
    required String langKey,
    required bool isJapanese,
    required double speed,
    required String cacheKey,
  }) async {
    await initializeForLanguage(langKey);
    if (_disposed) return '';

    final worker = _worker;
    final canRunNative = worker != null && !worker.isClosed && (isJapanese ? _hasJaFiles : _hasEnFiles);
    if (canRunNative) {
      try {
        final outPath = _nextTempWavPath(isJapanese ? 'tts_ja' : 'tts_en');
        final res = await worker.request({
          'op': 'synthesize',
          'language': langKey,
          'text': cleanText,
          'speed': speed,
          'wavPath': outPath,
        }) as Map<Object?, Object?>;

        if (_disposed) {
          _tryDeleteFile(outPath);
          return '';
        }

        _isEnNativeActive = res['enActive'] == true;
        _isJaNativeActive = res['jaActive'] == true;

        if (res['ok'] == true && File(outPath).existsSync()) {
          _putWavCache(cacheKey, outPath);
          AppLogger.info(
            'SherpaTtsService',
            'Synthesized ${res['samples']} $langKey samples to: $outPath',
          );
          return outPath;
        }
      } catch (err, st) {
        AppLogger.error('SherpaTtsService', 'Native $langKey TTS generation error', err, st);
      }
    }

    return _generateFallbackWav(cleanText, language: language);
  }

  String _nextTempWavPath(String prefix) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final seq = ++_wavCounter;
    return p.join(Directory.systemTemp.path, '${prefix}_${ts}_$seq.wav');
  }

  void _putWavCache(String key, String path) {
    while (_wavCache.length >= _maxWavCacheEntries) {
      final oldestKey = _wavCache.keys.first;
      final oldestPath = _wavCache.remove(oldestKey);
      if (oldestPath != null) {
        _tryDeleteFile(oldestPath);
      }
    }
    _wavCache[key] = path;
  }

  void _tryDeleteFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<String> _generateFallbackWav(String text, {required String language}) async {
    const sampleRate = 16000;
    const numSamples = 8000; // 0.5s placeholder for headless/mock environments
    final outPath = _nextTempWavPath('tts_fallback_$language');
    writePcm16WavSync(Float32List(numSamples), sampleRate, outPath);
    return outPath;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _initFuture = null;
    _configFuture = null;
    _configPrepared = false;
    _isEnNativeActive = false;
    _isJaNativeActive = false;
    _initialized = false;
    _inFlightSyntheses.clear();
    for (final path in _wavCache.values) {
      _tryDeleteFile(path);
    }
    _wavCache.clear();
    final worker = _worker;
    _worker = null;
    if (worker != null) {
      await worker.close(finalRequest: const {'op': 'dispose'});
    }
    AppLogger.info('SherpaTtsService', 'Disposed Sherpa-ONNX TTS engines');
  }
}

// ---------------------------------------------------------------------------
// Top-level TTS worker isolate handler & zero-copy Melo-VITS synthesis
// ---------------------------------------------------------------------------

Object? _ttsWorkerHandler(Object? request, Map<String, Object?> state) {
  final req = request as Map<Object?, Object?>;
  switch (req['op']) {
    case 'configure':
      state['threads'] = (req['threads'] as int?) ?? 2;
      state['lowEnd'] = req['lowEnd'] == true;
      state['enSpec'] = req['enSpec'];
      state['jaSpec'] = req['jaSpec'];
      return true;

    case 'ensureLang':
      final lang = req['language'] as String? ?? 'en';
      final lowEnd = state['lowEnd'] == true;
      if (lang == 'ja') {
        _ensureJaTtsInWorker(state, unloadOpposite: lowEnd);
      } else {
        _ensureEnTtsInWorker(state, unloadOpposite: lowEnd);
      }
      return {
        'enActive': state['enTts'] != null,
        'jaActive': state['jaSession'] != null,
      };

    case 'synthesize':
      final lang = req['language'] as String? ?? 'en';
      final text = req['text'] as String? ?? '';
      final speed = (req['speed'] as num?)?.toDouble() ?? 1.0;
      final wavPath = req['wavPath'] as String;
      final lowEnd = state['lowEnd'] == true;

      if (lang == 'ja') {
        _ensureJaTtsInWorker(state, unloadOpposite: lowEnd);
        final session = state['jaSession'] as OrtSession?;
        final g2p = state['jaG2p'] as JapaneseMeloG2p?;
        if (session == null || g2p == null) {
          return {
            'ok': false,
            'enActive': state['enTts'] != null,
            'jaActive': false,
          };
        }
        final samples = _synthesizeJapaneseMelo(text, g2p, session, speed: speed);
        if (samples.isEmpty) {
          return {
            'ok': false,
            'enActive': state['enTts'] != null,
            'jaActive': true,
          };
        }
        writePcm16WavSync(samples, 44100, wavPath);
        return {
          'ok': true,
          'samples': samples.length,
          'enActive': state['enTts'] != null,
          'jaActive': true,
        };
      } else {
        _ensureEnTtsInWorker(state, unloadOpposite: lowEnd);
        final enTts = state['enTts'] as sherpa.OfflineTts?;
        if (enTts == null) {
          return {
            'ok': false,
            'enActive': false,
            'jaActive': state['jaSession'] != null,
          };
        }
        final audio = enTts.generate(text: text, speed: speed);
        if (audio.samples.isEmpty) {
          return {
            'ok': false,
            'enActive': true,
            'jaActive': state['jaSession'] != null,
          };
        }
        writePcm16WavSync(audio.samples, audio.sampleRate, wavPath);
        return {
          'ok': true,
          'samples': audio.samples.length,
          'enActive': true,
          'jaActive': state['jaSession'] != null,
        };
      }

    case 'dispose':
      (state.remove('enTts') as sherpa.OfflineTts?)?.free();
      (state.remove('jaSession') as OrtSession?)?.release();
      state.remove('jaG2p');
      state.clear();
      return true;

    default:
      return null;
  }
}

void _ensureEnTtsInWorker(Map<String, Object?> state, {required bool unloadOpposite}) {
  if (unloadOpposite) {
    (state.remove('jaSession') as OrtSession?)?.release();
    state.remove('jaG2p');
  }
  if (state['enTts'] != null) return;
  final spec = state['enSpec'] as Map<Object?, Object?>?;
  if (spec == null) return;

  if (state['sherpaBound'] != true) {
    sherpa.initBindings();
    state['sherpaBound'] = true;
  }

  final threads = (state['threads'] as int?) ?? 2;
  final enConfig = sherpa.OfflineTtsConfig(
    model: sherpa.OfflineTtsModelConfig(
      vits: sherpa.OfflineTtsVitsModelConfig(
        model: spec['model'] as String,
        tokens: spec['tokens'] as String,
        lexicon: spec['lexicon'] as String? ?? '',
        dataDir: spec['dataDir'] as String? ?? '',
      ),
      numThreads: threads,
      debug: false,
      provider: 'cpu',
    ),
  );
  state['enTts'] = sherpa.OfflineTts(enConfig);
}

void _ensureJaTtsInWorker(Map<String, Object?> state, {required bool unloadOpposite}) {
  if (unloadOpposite) {
    (state.remove('enTts') as sherpa.OfflineTts?)?.free();
  }
  if (state['jaSession'] != null && state['jaG2p'] != null) return;
  final spec = state['jaSpec'] as Map<Object?, Object?>?;
  if (spec == null) return;

  final tokensPath = spec['tokens'] as String;
  final lexiconPath = spec['lexicon'] as String? ?? '';
  final modelPath = spec['model'] as String;

  final tokenLines = File(tokensPath).readAsLinesSync();
  final lexFile = File(lexiconPath);
  final lexiconLines =
      lexiconPath.isNotEmpty && lexFile.existsSync() ? lexFile.readAsLinesSync() : <String>[];

  state['jaG2p'] = JapaneseMeloG2p.fromFiles(
    tokenLines: tokenLines,
    lexiconLines: lexiconLines,
  );
  final threads = (state['threads'] as int?) ?? 2;
  state['jaSession'] = createOrtSessionSync(modelPath, threads: threads);
}

Float32List _synthesizeJapaneseMelo(
  String text,
  JapaneseMeloG2p g2p,
  OrtSession session, {
  double speed = 1.0,
}) {
  final sentences = g2p.encodeSentences(text);
  if (sentences.isEmpty) return Float32List(0);

  const sampleRate = 44100;
  const padSamples = (sampleRate * 0.05) ~/ 1;
  const pauseSamples = (sampleRate * 0.10) ~/ 1;
  const japaneseToneId = 6; // Matches `tone_start: 6` in MeloTTS metadata.json
  final lengthScale = speed > 0 ? 1.0 / speed : 1.0;

  final allChunks = <Float32List>[
    Float32List(padSamples),
  ];
  final runOptions = OrtRunOptions();

  try {
    for (var sIdx = 0; sIdx < sentences.length; sIdx++) {
      final x = sentences[sIdx];
      final xLen = x.length;
      final xInt64 = Int64List(xLen);
      final tonesInt64 = Int64List(xLen);
      for (var i = 0; i < xLen; i++) {
        final id = x[i];
        xInt64[i] = id;
        tonesInt64[i] = (id == g2p.blankId) ? 0 : japaneseToneId;
      }

      final xT = createInt64OrtTensor(xInt64, [1, xLen]);
      final lenT = createInt64OrtTensor(Int64List.fromList([xLen]), [1]);
      final tonesT = createInt64OrtTensor(tonesInt64, [1, xLen]);
      final sidT = createInt64OrtTensor(Int64List.fromList([0]), [1]);
      final nsT = createFloat32OrtTensor(Float32List.fromList([0.6]), [1]);
      final lsT = createFloat32OrtTensor(Float32List.fromList([lengthScale]), [1]);
      final nswT = createFloat32OrtTensor(Float32List.fromList([0.6]), [1]);

      List<OrtValue?>? outs;
      try {
        outs = session.run(runOptions, {
          'x': xT,
          'x_lengths': lenT,
          'tones': tonesT,
          'sid': sidT,
          'noise_scale': nsT,
          'length_scale': lsT,
          'noise_scale_w': nswT,
        });
        if (outs.isNotEmpty && outs[0] != null) {
          final view = ortFloatTensorView(outs[0]!);
          if (view.isNotEmpty) {
            allChunks.add(Float32List.fromList(view));
            if (sIdx + 1 < sentences.length) {
              allChunks.add(Float32List(pauseSamples));
            }
          }
        }
      } finally {
        for (final t in [xT, lenT, tonesT, sidT, nsT, lsT, nswT]) {
          t.release();
        }
        releaseOrtValues(outs);
      }
    }
  } finally {
    runOptions.release();
  }

  if (allChunks.length <= 1) return Float32List(0);
  allChunks.add(Float32List(padSamples));

  var totalLen = 0;
  for (final c in allChunks) {
    totalLen += c.length;
  }
  final result = Float32List(totalLen);
  var offset = 0;
  for (final c in allChunks) {
    result.setRange(offset, offset + c.length, c);
    offset += c.length;
  }
  return result;
}
