// ignore_for_file: avoid_print
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/language_detector.dart';
import '../../domain/models/asr_result.dart';
import '../../domain/services/asr_service.dart';
import 'model_loader.dart';

/// Multilingual offline ASR Service powered by SenseVoice Small (INT8) or Whisper
/// with integrated Silero VAD filtering and speech gain normalization.
class SherpaAsrServiceImpl implements AsrService {
  final String? encoderPath;
  final String? decoderPath;
  final String? tokensPath;
  final String? vadPath;
  final String? senseVoiceModelPath;
  final String? senseVoiceTokensPath;
  final ModelLoader _modelLoader;

  sherpa.OfflineRecognizer? _recognizer;
  sherpa.VoiceActivityDetector? _vad;

  String _resolvedEncoderPath = '';
  String _resolvedDecoderPath = '';
  String _resolvedTokensPath = '';
  String _resolvedSenseVoiceModel = '';
  String _resolvedSenseVoiceTokens = '';
  String _activeRecognizerLanguage = 'auto';

  bool _usingSenseVoice = false;
  bool _isInitialized = false;
  bool _disposed = false;
  Future<void>? _initFuture;
  bool _isNativeModelActive = false;
  bool _isNativeVadActive = false;
  String? _lastInitError;

  bool get isReady => _isInitialized && !_disposed && _isNativeModelActive;
  String? get lastInitError => _lastInitError;

  // Calibrated fallback VAD thresholds
  static const int _silenceTimeoutSamples = (1.0 * AppConstants.audioSampleRate) ~/ 1;
  static const double _speechEnergyThreshold = 0.012;

  final List<double> _accumulatedSpeech = [];
  final Queue<Float32List> _readySpeechSegments = Queue<Float32List>();
  int _consecutiveSilenceSamples = 0;
  bool _userWasSpeaking = false;

  SherpaAsrServiceImpl({
    this.encoderPath,
    this.decoderPath,
    this.tokensPath,
    this.vadPath,
    this.senseVoiceModelPath,
    this.senseVoiceTokensPath,
    ModelLoader? modelLoader,
  }) : _modelLoader = modelLoader ?? const ModelLoader();

  @override
  Future<void> initialize() {
    if (_isInitialized && !_disposed && _isNativeModelActive) return Future.value();
    _disposed = false;
    return _initFuture ??= _doInitialize().whenComplete(() {
      if (!_disposed && _isNativeModelActive) {
        _isInitialized = true;
      }
      _initFuture = null;
    });
  }

  Future<void> _doInitialize() async {
    if (kIsWeb) return;

    AppLogger.info('ASRService', 'Initializing offline multilingual ASR and Silero VAD engine...');
    _lastInitError = null;

    try {
      sherpa.initBindings();

      if (senseVoiceModelPath == null && encoderPath == null) {
        await _modelLoader.extractModelAssets();
      }
      if (_disposed) return;

      String? resolvedVadPath = vadPath;

      if (senseVoiceModelPath != null && senseVoiceTokensPath != null) {
        _resolvedSenseVoiceModel = senseVoiceModelPath!;
        _resolvedSenseVoiceTokens = senseVoiceTokensPath!;
      } else if (encoderPath != null && decoderPath != null && tokensPath != null) {
        _resolvedEncoderPath = encoderPath!;
        _resolvedDecoderPath = decoderPath!;
        _resolvedTokensPath = tokensPath!;
      } else {
        final asrPaths = await _modelLoader.getAsrModelPaths();
        _resolvedEncoderPath = asrPaths.encoderPath;
        _resolvedDecoderPath = asrPaths.decoderPath;
        _resolvedTokensPath = asrPaths.tokensPath;
        _resolvedSenseVoiceModel = asrPaths.senseVoiceModelPath ?? '';
        _resolvedSenseVoiceTokens = asrPaths.senseVoiceTokensPath ?? '';
        resolvedVadPath ??= asrPaths.vadPath;
      }
      if (_disposed) return;

      final vadFile = resolvedVadPath != null && resolvedVadPath.isNotEmpty
          ? File(resolvedVadPath)
          : null;

      // 1. Initialize Silero VAD with responsive silence segmentation
      if (vadFile != null && vadFile.existsSync()) {
        try {
          final sileroConfig = sherpa.SileroVadModelConfig(
            model: vadFile.path,
            threshold: 0.35,
            minSilenceDuration: 0.8,
            minSpeechDuration: 0.2,
            windowSize: 512,
          );

          final vadConfig = sherpa.VadModelConfig(
            sileroVad: sileroConfig,
            sampleRate: AppConstants.audioSampleRate,
            numThreads: 1,
            debug: false,
          );

          final vad = sherpa.VoiceActivityDetector(
            config: vadConfig,
            bufferSizeInSeconds: 30,
          );
          if (_disposed) {
            vad.free();
            return;
          }
          _vad = vad;
          _isNativeVadActive = true;
          AppLogger.info('ASRService', 'Silero VAD initialized (threshold=0.35).');
        } catch (vadErr, st) {
          AppLogger.error('ASRService', 'Failed initializing native Silero VAD', vadErr, st);
        }
      }

      // 2. Prefer SenseVoice Small INT8 for high-accuracy EN/JA recognition
      final svModelFile = File(_resolvedSenseVoiceModel);
      final svTokensFile = File(_resolvedSenseVoiceTokens);
      if (_resolvedSenseVoiceModel.isNotEmpty &&
          svModelFile.existsSync() &&
          svTokensFile.existsSync()) {
        try {
          _usingSenseVoice = true;
          _activeRecognizerLanguage = 'auto';
          final recognizer = sherpa.OfflineRecognizer(
            _buildRecognizerConfig(language: 'auto'),
          );
          if (_disposed) {
            recognizer.free();
            return;
          }
          _recognizer = recognizer;
          _isNativeModelActive = true;
          AppLogger.info(
            'ASRService',
            'SenseVoice Small INT8 offline recognizer initialized.',
          );
          return;
        } catch (svErr, st) {
          _usingSenseVoice = false;
          AppLogger.error('ASRService', 'Failed initializing SenseVoice recognizer', svErr, st);
        }
      }

      // 3. Fallback to Whisper ONNX if provided
      final encoderFile = File(_resolvedEncoderPath);
      final decoderFile = File(_resolvedDecoderPath);
      final tokensFile = File(_resolvedTokensPath);
      if (_resolvedDecoderPath.isNotEmpty &&
          encoderFile.existsSync() &&
          decoderFile.existsSync() &&
          tokensFile.existsSync()) {
        try {
          _usingSenseVoice = false;
          _activeRecognizerLanguage = '';
          final recognizer = sherpa.OfflineRecognizer(
            _buildRecognizerConfig(language: ''),
          );
          if (_disposed) {
            recognizer.free();
            return;
          }
          _recognizer = recognizer;
          _isNativeModelActive = true;
          AppLogger.info('ASRService', 'Whisper ONNX offline recognizer initialized.');
        } catch (whisperErr, st) {
          AppLogger.error('ASRService', 'Failed initializing native Whisper recognizer', whisperErr, st);
        }
      } else {
        _lastInitError = 'No native ASR weights resolved on disk.';
        AppLogger.warning('ASRService', _lastInitError!);
      }
    } catch (e, st) {
      _lastInitError = e.toString();
      AppLogger.error('ASRService', 'Initialization error in offline ASR', e, st);
    }
  }

  sherpa.OfflineRecognizerConfig _buildRecognizerConfig({required String language}) {
    if (_usingSenseVoice) {
      return sherpa.OfflineRecognizerConfig(
        feat: const sherpa.FeatureConfig(
          sampleRate: AppConstants.audioSampleRate,
          featureDim: 80,
        ),
        model: sherpa.OfflineModelConfig(
          senseVoice: sherpa.OfflineSenseVoiceModelConfig(
            model: _resolvedSenseVoiceModel,
            language: language,
            useInverseTextNormalization: true,
          ),
          tokens: _resolvedSenseVoiceTokens,
          numThreads: 2,
          debug: false,
          provider: 'cpu',
        ),
      );
    }

    return sherpa.OfflineRecognizerConfig(
      feat: const sherpa.FeatureConfig(
        sampleRate: AppConstants.audioSampleRate,
        featureDim: 80,
      ),
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: _resolvedEncoderPath,
          decoder: _resolvedDecoderPath,
          language: language,
          task: 'transcribe',
        ),
        tokens: _resolvedTokensPath,
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
    );
  }

  void _setRecognizerLanguage(String language) {
    if (_recognizer == null || _activeRecognizerLanguage == language) return;
    _recognizer!.setConfig(_buildRecognizerConfig(language: language));
    _activeRecognizerLanguage = language;
  }

  @override
  void acceptVadWaveform(Float32List samples) {
    if (samples.isEmpty) return;

    if (_accumulatedSpeech.length + samples.length > 30 * AppConstants.audioSampleRate) {
      _accumulatedSpeech.removeRange(0, samples.length);
    }
    _accumulatedSpeech.addAll(samples);

    if (_isNativeVadActive && _vad != null) {
      _feedVadChunks(samples);
      _drainVadSegments();
      return;
    }

    double energySum = 0;
    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      energySum += s * s;
    }
    final rms = energySum / samples.length;
    final isVoiceActive = rms > (_speechEnergyThreshold * _speechEnergyThreshold);

    if (isVoiceActive) {
      _userWasSpeaking = true;
      _consecutiveSilenceSamples = 0;
    } else if (_userWasSpeaking) {
      _consecutiveSilenceSamples += samples.length;
      if (_consecutiveSilenceSamples >= _silenceTimeoutSamples) {
        if (_accumulatedSpeech.length > 4000) {
          _readySpeechSegments.add(Float32List.fromList(_accumulatedSpeech));
        }
        _accumulatedSpeech.clear();
        _consecutiveSilenceSamples = 0;
        _userWasSpeaking = false;
      }
    }
  }

  void _feedVadChunks(Float32List samples) {
    final vad = _vad;
    if (vad == null) return;
    int offset = 0;
    while (offset + 512 <= samples.length) {
      vad.acceptWaveform(Float32List.sublistView(samples, offset, offset + 512));
      offset += 512;
    }
    if (offset < samples.length) {
      final padded = Float32List(512);
      padded.setRange(0, samples.length - offset, samples, offset);
      vad.acceptWaveform(padded);
    }
  }

  void _drainVadSegments() {
    final vad = _vad;
    if (vad == null) return;
    while (!vad.isEmpty()) {
      final segment = vad.front();
      if (segment.samples.isNotEmpty) {
        _readySpeechSegments.add(segment.samples);
      }
      vad.pop();
    }
  }

  @override
  bool hasSpeechSegment() => _readySpeechSegments.isNotEmpty;

  @override
  Float32List? popSpeechSegment() {
    if (_readySpeechSegments.isEmpty) return null;
    return _readySpeechSegments.removeFirst();
  }

  @override
  Float32List? flushSpeechSegment() {
    if (_isNativeVadActive && _vad != null) {
      _vad!.flush();
      _drainVadSegments();
    }
    if (_readySpeechSegments.isNotEmpty) {
      return _readySpeechSegments.removeFirst();
    }
    if (_accumulatedSpeech.length > 4000) {
      final flushed = Float32List.fromList(_accumulatedSpeech);
      _accumulatedSpeech.clear();
      _consecutiveSilenceSamples = 0;
      _userWasSpeaking = false;
      return flushed;
    }
    return null;
  }

  @override
  void resetVad() {
    _vad?.reset();
    _vad?.clear();
    _accumulatedSpeech.clear();
    _readySpeechSegments.clear();
    _consecutiveSilenceSamples = 0;
    _userWasSpeaking = false;
  }

  @override
  Future<AsrResult> transcribe(
    Float32List samples, {
    String? preferredLanguage,
  }) async {
    if (!_isInitialized && !_disposed) {
      await initialize();
    }

    if (_disposed || samples.isEmpty) {
      return const AsrResult(text: '', language: 'en');
    }

    if (!_isNativeModelActive || _recognizer == null) {
      final hasAudioSignal = _conditionSpeechAudio(samples) != null;
      if (hasAudioSignal && _lastInitError != null) {
        throw StateError('Offline speech recognition unavailable: $_lastInitError');
      }
      return const AsrResult(text: '', language: 'en');
    }

    final conditioned = _conditionSpeechAudio(samples);
    if (conditioned == null || conditioned.isEmpty) {
      AppLogger.info('ASRService', 'Audio below speech energy floor; skipping decode.');
      return const AsrResult(text: '', language: 'en');
    }

    final chunks = _extractSpeechChunks(conditioned);
    if (chunks.isEmpty) {
      AppLogger.info('ASRService', 'No voiced speech segments extracted.');
      return const AsrResult(text: '', language: 'en');
    }

    final defaultLang = _usingSenseVoice ? 'auto' : '';
    final normalizedPreferred = _normalizeLangCode(preferredLanguage ?? '');
    final hintLang = (normalizedPreferred == 'ja' || normalizedPreferred == 'en')
        ? normalizedPreferred
        : '';

    final transcripts = <String>[];
    var lastLang = '';
    var detectedJa = false;

    try {
      for (final chunk in chunks) {
        final padded = _padSilence(chunk, 1600); // 100ms cushion for clean CTC onset/offset

        _setRecognizerLanguage(defaultLang);
        var decoded = _decodeChunk(padded);
        var langCode = _normalizeLangCode(decoded.lang);
        var cleaned = _cleanAsrText(decoded.text);

        // If auto-detection produced empty text, <nospeech>, or overlapping CJK/KO language
        // while we have an explicit EN/JA preference, retry forcing the preferred language.
        final isAmbiguousLang = langCode.isEmpty ||
            (langCode != 'en' && langCode != 'ja');
        if (hintLang.isNotEmpty && (cleaned.isEmpty || isAmbiguousLang)) {
          _setRecognizerLanguage(hintLang);
          final retried = _decodeChunk(padded);
          final retriedCleaned = _cleanAsrText(retried.text);
          final retriedLang = _normalizeLangCode(retried.lang);
          if (retriedCleaned.isNotEmpty) {
            cleaned = retriedCleaned;
            langCode = retriedLang.isNotEmpty ? retriedLang : hintLang;
          }
        }

        if (cleaned.isNotEmpty) {
          transcripts.add(cleaned);
          if (langCode.isNotEmpty) lastLang = langCode;
          if (langCode == 'ja' || _hasJapaneseKana(cleaned)) {
            detectedJa = true;
          }
        }
      }
    } finally {
      _setRecognizerLanguage(defaultLang);
    }

    if (transcripts.isEmpty) {
      return const AsrResult(text: '', language: 'en');
    }

    var fullText = transcripts.join(detectedJa ? '' : ' ').trim();
    final hasKana = _hasJapaneseKana(fullText);
    final hasKanjiOrCjk = isJapaneseText(fullText);
    final hasLatin = RegExp(r'[A-Za-z]').hasMatch(fullText);

    final String finalLang;
    if (hasKana) {
      finalLang = 'ja';
    } else if (hasKanjiOrCjk && (lastLang == 'ja' || hintLang == 'ja' || !hasLatin)) {
      finalLang = 'ja';
    } else if (hasLatin) {
      finalLang = 'en';
    } else if (lastLang == 'ja' || detectedJa) {
      finalLang = 'ja';
    } else {
      finalLang = hintLang == 'ja' ? 'ja' : 'en';
    }

    if (finalLang == 'ja') {
      fullText = _normalizeJapaneseSpacing(fullText);
    }

    AppLogger.info('ASRService', 'Decoded audio -> "$fullText" [Language: $finalLang]');
    return AsrResult(text: fullText, language: finalLang);
  }

  ({String text, String lang}) _decodeChunk(Float32List samples) {
    final stream = _recognizer!.createStream();
    try {
      stream.acceptWaveform(
        samples: samples,
        sampleRate: AppConstants.audioSampleRate,
      );
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);
      return (text: result.text, lang: result.lang);
    } catch (err, st) {
      AppLogger.error('ASRService', 'Native ASR decoding error', err, st);
      return (text: '', lang: '');
    } finally {
      stream.free();
    }
  }

  /// Removes DC offset and normalizes quiet handheld recordings using the 90th-percentile
  /// 20ms frame RMS so brief mic taps do not suppress real speech amplification.
  Float32List? _conditionSpeechAudio(Float32List samples) {
    final n = samples.length;
    if (n == 0) return null;

    var mean = 0.0;
    for (var i = 0; i < n; i++) {
      mean += samples[i];
    }
    mean /= n;

    final centered = Float32List(n);
    var peak = 0.0;
    var sumSq = 0.0;
    for (var i = 0; i < n; i++) {
      final v = samples[i] - mean;
      centered[i] = v;
      final a = v.abs();
      if (a > peak) peak = a;
      sumSq += v * v;
    }

    final totalRms = math.sqrt(sumSq / n);
    if (peak < 0.002 && totalRms < 0.0004) {
      return null;
    }

    const frameLen = 320; // 20ms @ 16kHz
    final frameRms = <double>[];
    for (var i = 0; i + frameLen <= n; i += frameLen) {
      var fs = 0.0;
      for (var k = 0; k < frameLen; k++) {
        final v = centered[i + k];
        fs += v * v;
      }
      frameRms.add(math.sqrt(fs / frameLen));
    }
    frameRms.sort();
    final activeRms = frameRms.isNotEmpty
        ? frameRms[((frameRms.length - 1) * 0.90).floor()]
        : totalRms;

    if (activeRms >= 0.11 || peak >= 0.55 || activeRms < 0.0005) {
      return centered;
    }

    final gain = (0.14 / activeRms).clamp(1.0, 12.0);
    if (gain <= 1.15) return centered;

    final normalized = Float32List(n);
    for (var i = 0; i < n; i++) {
      final scaled = centered[i] * gain;
      // Smooth soft-knee saturation prevents harsh clipping on loud peaks
      final limited = scaled.abs() > 0.85
          ? scaled.sign * (0.85 + 0.13 * (1.0 - math.exp(-(scaled.abs() - 0.85) * 4.0)))
          : scaled;
      normalized[i] = limited.clamp(-0.98, 0.98);
    }
    return normalized;
  }

  /// Removes leading/trailing dead air with generous onset cushion so soft initial vowels
  /// (`お`, `え`, `あ`) are never clipped, using Silero VAD segmentation on long (>12s) captures.
  List<Float32List> _extractSpeechChunks(Float32List samples) {
    const maxChunkSamples = 24 * AppConstants.audioSampleRate;
    final trimmed = _trimSilence(samples);
    if (trimmed == null || trimmed.isEmpty) return const [];

    if (trimmed.length <= 12 * AppConstants.audioSampleRate) {
      return [trimmed];
    }

    if (_isNativeVadActive && _vad != null) {
      final vad = _vad!;
      vad.reset();
      vad.clear();

      final paddedForVad = _padSilence(trimmed, 2560);
      _feedVadChunks(paddedForVad);
      vad.flush();

      final vadSegments = <Float32List>[];
      while (!vad.isEmpty()) {
        final seg = vad.front();
        if (seg.samples.isNotEmpty) {
          vadSegments.add(seg.samples);
        }
        vad.pop();
      }
      vad.reset();
      vad.clear();

      if (vadSegments.isNotEmpty) {
        return _mergeShortSegments(vadSegments, maxSamples: maxChunkSamples);
      }
    }

    return _splitLongAudio(trimmed, maxChunkSamples);
  }

  List<Float32List> _mergeShortSegments(
    List<Float32List> segments, {
    required int maxSamples,
  }) {
    final merged = <Float32List>[];
    final current = <double>[];
    const gapSamples = 2400; // 150ms natural inter-clause pause

    for (final seg in segments) {
      if (current.isNotEmpty && current.length + gapSamples + seg.length > maxSamples) {
        merged.add(Float32List.fromList(current));
        current.clear();
      }
      if (current.isNotEmpty) {
        current.addAll(List<double>.filled(gapSamples, 0.0));
      }
      if (seg.length > maxSamples) {
        if (current.isNotEmpty) {
          merged.add(Float32List.fromList(current));
          current.clear();
        }
        merged.addAll(_splitLongAudio(seg, maxSamples));
      } else {
        current.addAll(seg);
      }
    }
    if (current.isNotEmpty) {
      merged.add(Float32List.fromList(current));
    }
    return merged;
  }

  Float32List _padSilence(Float32List samples, int padSamples) {
    final out = Float32List(samples.length + padSamples * 2);
    out.setRange(padSamples, padSamples + samples.length, samples);
    return out;
  }

  /// Trims leading and trailing near-silence while keeping 0.3s padding.
  Float32List? _trimSilence(Float32List samples) {
    double peak = 0.0;
    double sumSq = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i].abs();
      if (v > peak) peak = v;
      sumSq += v * v;
    }
    final rms = math.sqrt(sumSq / samples.length);
    if (peak < 0.002 && rms < 0.0005) {
      return null;
    }

    const activeThreshold = 0.006;
    var firstActive = -1;
    var lastActive = -1;
    for (var i = 0; i < samples.length; i++) {
      if (samples[i].abs() >= activeThreshold) {
        if (firstActive == -1) firstActive = i;
        lastActive = i;
      }
    }
    if (firstActive == -1) return samples;

    const padSamples = (0.3 * AppConstants.audioSampleRate) ~/ 1;
    final start = math.max(0, firstActive - padSamples);
    final end = math.min(samples.length, lastActive + padSamples);
    if (start == 0 && end == samples.length) return samples;
    return Float32List.sublistView(samples, start, end);
  }

  /// Splits recordings exceeding 24s at low-energy boundaries.
  List<Float32List> _splitLongAudio(Float32List samples, int maxSamples) {
    if (samples.length <= maxSamples) return [samples];
    final chunks = <Float32List>[];
    var start = 0;
    const searchBack = 3 * AppConstants.audioSampleRate;
    const winSize = 1600;

    while (start < samples.length) {
      if (samples.length - start <= maxSamples) {
        chunks.add(Float32List.sublistView(samples, start));
        break;
      }
      final hardEnd = start + maxSamples;
      final searchStart = math.max(start + AppConstants.audioSampleRate, hardEnd - searchBack);
      var bestSplit = hardEnd;
      var bestEnergy = double.infinity;
      for (var pos = searchStart; pos + winSize <= hardEnd; pos += winSize) {
        var energy = 0.0;
        for (var k = 0; k < winSize; k++) {
          final v = samples[pos + k];
          energy += v * v;
        }
        if (energy < bestEnergy) {
          bestEnergy = energy;
          bestSplit = pos + winSize ~/ 2;
        }
      }
      chunks.add(Float32List.sublistView(samples, start, bestSplit));
      start = bestSplit;
    }
    return chunks;
  }

  String _normalizeLangCode(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[<|>]'), '').trim().toLowerCase();
    if (cleaned.startsWith('ja')) return 'ja';
    if (cleaned.startsWith('en')) return 'en';
    return cleaned;
  }

  bool _hasJapaneseKana(String text) =>
      RegExp(r'[\u3040-\u309F\u30A0-\u30FF\u31F0-\u31FF]').hasMatch(text);

  String _normalizeJapaneseSpacing(String text) {
    const jp = r'[\u3000-\u30ff\u4e00-\u9fff\uff00-\uffef]';
    var out = text.replaceAll(RegExp('(?<=$jp) +(?=$jp)'), '');
    out = out.replaceAll(RegExp(r'\s+([。、．，！？!?」』）】])'), r'$1');
    out = out.replaceAll(RegExp(r'([「『（【])\s+'), r'$1');
    return out.trim();
  }

  String _cleanAsrText(String raw) {
    return raw
        .replaceAll(RegExp(r'<\|[^|>]+\|>'), '')
        .replaceAll(RegExp(r'\[(?:BLANK_AUDIO|SILENCE|MUSIC|APPLAUSE|INAUDIBLE|NOISE)\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\((?:silence|music|applause|inaudible|noise|blank audio)\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _initFuture = null;
    _recognizer?.free();
    _recognizer = null;
    _vad?.free();
    _vad = null;
    _isInitialized = false;
    _isNativeModelActive = false;
    _isNativeVadActive = false;
    _readySpeechSegments.clear();
    _accumulatedSpeech.clear();
    AppLogger.info('ASRService', 'Multilingual ASR & Silero VAD engine disposed.');
  }
}
