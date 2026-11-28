import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/background_worker.dart';
import '../../../../core/utils/device_profile.dart';
import '../../../../core/utils/ort_utils.dart';
import '../../domain/services/nmt_service.dart';
import 'model_loader.dart';
import 'sentencepiece_model.dart';

/// Everything needed to translate in a single direction (lives inside the NMT worker isolate).
class _DirectionEngine {
  final OrtSession encoder;
  final OrtSession decoder;
  final Map<String, int> vocab;
  final Set<String> vocabSet;
  final Map<int, String> reverseVocab;
  final SentencePieceModel sourceSpm;

  _DirectionEngine({
    required this.encoder,
    required this.decoder,
    required this.vocab,
    required this.reverseVocab,
    required this.sourceSpm,
  }) : vocabSet = vocab.keys.toSet();

  void release() {
    try {
      encoder.release();
      decoder.release();
    } catch (_) {}
  }
}

/// 100% on-device Neural Machine Translation using the MarianMT ONNX models delivered
/// via the Android install-time AI pack (`:ai_models`).
///
/// Runs session creation and greedy decoding inside a dedicated [BackgroundWorker]
/// isolate with zero-copy float32 logits views, single-output (`logits`) decoder
/// execution, direct native tensor allocation, and an LRU translation cache.
class OnnxNmtServiceImpl implements NmtService {
  static const int _maxCacheEntries = 64;

  final ModelLoader _modelLoader;
  final String? enJaEncoderPath;
  final String? enJaDecoderPath;
  final String? jaEnEncoderPath;
  final String? jaEnDecoderPath;

  bool _initialized = false;
  bool _disposed = false;
  Future<void>? _initFuture;
  String? _lastInitError;

  BackgroundWorker? _worker;
  bool _hasEnJaSpec = false;
  bool _hasJaEnSpec = false;

  final LinkedHashMap<String, String> _translationCache = LinkedHashMap<String, String>();

  /// True once at least one direction has valid ONNX weights and a live worker.
  bool get isReady =>
      !_disposed &&
      _worker != null &&
      !_worker!.isClosed &&
      (_hasEnJaSpec || _hasJaEnSpec);

  String? get lastInitError => _lastInitError;

  OnnxNmtServiceImpl({
    ModelLoader? modelLoader,
    this.enJaEncoderPath,
    this.enJaDecoderPath,
    this.jaEnEncoderPath,
    this.jaEnDecoderPath,
  }) : _modelLoader = modelLoader ?? const ModelLoader();

  @override
  Future<void> initialize() {
    if (_initialized && !_disposed && isReady) return Future.value();
    _disposed = false;
    return _initFuture ??= _doInitialize().whenComplete(() {
      if (!_disposed && isReady) {
        _initialized = true;
      }
      _initFuture = null;
    });
  }

  Future<void> _doInitialize() async {
    AppLogger.info(
      'OnnxNmtService',
      'Initializing offline MarianMT ONNX translation engines (${DeviceProfile.describe()})...',
    );
    _lastInitError = null;

    try {
      if (enJaEncoderPath == null || jaEnEncoderPath == null) {
        await _modelLoader.extractModelAssets();
      }
      if (_disposed) return;

      final nmtPaths = await _modelLoader.getNmtModelPaths();
      if (_disposed) return;

      final enJaSpec = _buildSpec(
        encoderPath: enJaEncoderPath ?? nmtPaths.enJa.encoderPath,
        decoderPath: enJaDecoderPath ?? nmtPaths.enJa.decoderPath,
        vocabPath: nmtPaths.enJa.vocabJsonPath,
        sourceSpmPath: nmtPaths.enJa.sourceSpmPath,
      );
      final jaEnSpec = _buildSpec(
        encoderPath: jaEnEncoderPath ?? nmtPaths.jaEn.encoderPath,
        decoderPath: jaEnDecoderPath ?? nmtPaths.jaEn.decoderPath,
        vocabPath: nmtPaths.jaEn.vocabJsonPath,
        sourceSpmPath: nmtPaths.jaEn.sourceSpmPath,
      );

      _hasEnJaSpec = enJaSpec != null;
      _hasJaEnSpec = jaEnSpec != null;

      if (!_hasEnJaSpec && !_hasJaEnSpec) {
        _lastInitError = 'No ONNX NMT translation weights could be loaded.';
        AppLogger.warning('OnnxNmtService', _lastInitError!);
        return;
      }

      final worker = await BackgroundWorker.spawn(_nmtWorkerHandler, debugName: 'ikho-nmt');
      if (_disposed) {
        await worker.close(finalRequest: const {'op': 'dispose'});
        return;
      }
      _worker = worker;

      final lowRam = DeviceProfile.totalRamMb > 0 && DeviceProfile.totalRamMb < 3200;
      await worker.request({
        'op': 'configure',
        'threads': DeviceProfile.inferenceThreads,
        'lowRam': lowRam,
        'warm': !DeviceProfile.isLowEnd,
        'enJa': enJaSpec,
        'jaEn': jaEnSpec,
      });

      if (_disposed) {
        await worker.close(finalRequest: const {'op': 'dispose'});
        _worker = null;
        return;
      }

      AppLogger.info(
        'OnnxNmtService',
        'NMT worker ready (enJa=$_hasEnJaSpec, jaEn=$_hasJaEnSpec, lazy=${DeviceProfile.isLowEnd}).',
      );
    } catch (e, st) {
      _lastInitError = e.toString();
      AppLogger.error('OnnxNmtService', 'Initialization error in MarianMT ONNX translation engine', e, st);
    }
  }

  Map<String, String>? _buildSpec({
    required String encoderPath,
    required String decoderPath,
    required String? vocabPath,
    required String? sourceSpmPath,
  }) {
    if (vocabPath == null || sourceSpmPath == null) return null;
    if (!File(encoderPath).existsSync() ||
        !File(decoderPath).existsSync() ||
        !File(vocabPath).existsSync() ||
        !File(sourceSpmPath).existsSync()) {
      return null;
    }
    return {
      'encoderPath': encoderPath,
      'decoderPath': decoderPath,
      'vocabPath': vocabPath,
      'sourceSpmPath': sourceSpmPath,
    };
  }

  /// Translates fully offline. Returns an empty string only when the on-device
  /// engine for that direction is unavailable or produced no usable output.
  @override
  Future<String> translate(String text, {required String sourceLang, required String targetLang}) async {
    if (!_initialized && !_disposed) {
      await initialize();
    }
    if (_disposed) return '';

    final clean = text.trim();
    if (clean.isEmpty) return '';

    final isEnToJa = sourceLang.toLowerCase().startsWith('en');
    final hasSpec = isEnToJa ? _hasEnJaSpec : _hasJaEnSpec;
    final worker = _worker;
    if (!hasSpec || worker == null || worker.isClosed) {
      AppLogger.warning('OnnxNmtService', 'ONNX engine for ${isEnToJa ? 'EN->JA' : 'JA->EN'} is unavailable.');
      return '';
    }

    final cacheKey = '${isEnToJa ? 'en>ja' : 'ja>en'}|$clean';
    final cached = _translationCache.remove(cacheKey);
    if (cached != null) {
      _translationCache[cacheKey] = cached;
      return cached;
    }

    try {
      final result = await worker.request({
        'op': 'translate',
        'direction': isEnToJa ? 'enJa' : 'jaEn',
        'text': clean,
        'targetIsJapanese': isEnToJa,
      }) as String?;

      if (result != null && _isValidTranslation(result)) {
        if (_translationCache.length >= _maxCacheEntries) {
          _translationCache.remove(_translationCache.keys.first);
        }
        _translationCache[cacheKey] = result;
        AppLogger.info('OnnxNmtService', '${isEnToJa ? 'EN->JA' : 'JA->EN'} on-device: "$clean" -> "$result"');
        return result;
      }
      AppLogger.warning('OnnxNmtService', 'Degenerate ONNX output ("${result ?? ''}").');
    } catch (err, st) {
      AppLogger.error('OnnxNmtService', 'ONNX runtime inference exception', err, st);
    }
    return '';
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _initFuture = null;
    _initialized = false;
    _hasEnJaSpec = false;
    _hasJaEnSpec = false;
    _translationCache.clear();
    final worker = _worker;
    _worker = null;
    if (worker != null) {
      await worker.close(finalRequest: const {'op': 'dispose'});
    }
    AppLogger.info('OnnxNmtService', 'Disposed OnnxNmtService ONNX sessions');
  }
}

// ---------------------------------------------------------------------------
// Top-level worker isolate handler & greedy MarianMT decoding
// ---------------------------------------------------------------------------

Object? _nmtWorkerHandler(Object? request, Map<String, Object?> state) {
  final req = request as Map<Object?, Object?>;
  switch (req['op']) {
    case 'configure':
      final threads = (req['threads'] as int?) ?? 2;
      final lowRam = (req['lowRam'] as bool?) ?? false;
      final warm = (req['warm'] as bool?) ?? false;
      state['threads'] = threads;
      state['lowRam'] = lowRam;
      state['enJaSpec'] = req['enJa'];
      state['jaEnSpec'] = req['jaEn'];
      if (warm) {
        if (req['enJa'] != null) _ensureNmtDirection('enJa', state);
        if (!lowRam && req['jaEn'] != null) _ensureNmtDirection('jaEn', state);
      }
      return true;

    case 'translate':
      final direction = req['direction'] as String;
      final text = req['text'] as String;
      final targetIsJapanese = req['targetIsJapanese'] as bool;
      final engine = _ensureNmtDirection(direction, state);
      if (engine == null) return '';

      final sentences = _splitSentences(text);
      final translatedParts = <String>[];
      for (final sentence in sentences) {
        final translated = _runOnnxTranslation(
          sentence,
          engine,
          targetIsJapanese: targetIsJapanese,
        );
        if (_isValidTranslation(translated)) {
          translatedParts.add(translated);
        }
      }
      final joined = targetIsJapanese ? translatedParts.join('') : translatedParts.join(' ');
      return _isValidTranslation(joined) ? joined : '';

    case 'dispose':
      (state.remove('enJaEngine') as _DirectionEngine?)?.release();
      (state.remove('jaEnEngine') as _DirectionEngine?)?.release();
      state.clear();
      return true;

    default:
      return null;
  }
}

_DirectionEngine? _ensureNmtDirection(String direction, Map<String, Object?> state) {
  final engineKey = direction == 'enJa' ? 'enJaEngine' : 'jaEnEngine';
  final existing = state[engineKey] as _DirectionEngine?;
  if (existing != null) return existing;

  final specKey = direction == 'enJa' ? 'enJaSpec' : 'jaEnSpec';
  final spec = state[specKey] as Map<Object?, Object?>?;
  if (spec == null) return null;

  final lowRam = (state['lowRam'] as bool?) ?? false;
  if (lowRam) {
    final otherKey = direction == 'enJa' ? 'jaEnEngine' : 'enJaEngine';
    (state.remove(otherKey) as _DirectionEngine?)?.release();
  }

  final threads = (state['threads'] as int?) ?? 2;
  final encoderPath = spec['encoderPath'] as String;
  final decoderPath = spec['decoderPath'] as String;
  final vocabPath = spec['vocabPath'] as String;
  final sourceSpmPath = spec['sourceSpmPath'] as String;

  final map = jsonDecode(File(vocabPath).readAsStringSync()) as Map<String, dynamic>;
  final vocab = map.map((k, v) => MapEntry(k, (v as num).toInt()));
  final reverse = <int, String>{for (final e in vocab.entries) e.value: e.key};
  final spm = SentencePieceModel.parse(File(sourceSpmPath).readAsBytesSync());

  OrtSession? encoder;
  OrtSession? decoder;
  try {
    encoder = createOrtSessionSync(encoderPath, threads: threads);
    decoder = createOrtSessionSync(decoderPath, threads: threads);
    final loaded = _DirectionEngine(
      encoder: encoder,
      decoder: decoder,
      vocab: vocab,
      reverseVocab: reverse,
      sourceSpm: spm,
    );
    state[engineKey] = loaded;
    encoder = null;
    decoder = null;
    return loaded;
  } catch (_) {
    encoder?.release();
    decoder?.release();
    rethrow;
  }
}

List<String> _splitSentences(String text) {
  final normalized = text.trim();
  if (normalized.isEmpty) return const [];
  final parts = normalized
      .split(RegExp(r'(?<=[。！？!?])\s*|(?<=\.)\s+(?=[A-Za-z0-9\u3040-\u9FFF])'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  return parts.isEmpty ? [normalized] : parts;
}

bool _isValidTranslation(String result) {
  final trimmed = result.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.contains('\u2581') || trimmed.contains('<unk>')) return false;
  return true;
}

String _runOnnxTranslation(
  String text,
  _DirectionEngine engine, {
  required bool targetIsJapanese,
}) {
  final vocab = engine.vocab;
  final eosId = vocab['</s>'] ?? 0;
  final padId = vocab['<pad>'] ?? 0;
  final unkId = vocab['<unk>'] ?? 1;

  final pieces = engine.sourceSpm.encode(text, allowedPieces: engine.vocabSet);
  if (pieces.isEmpty) return '';
  final seqLen = pieces.length + 1;
  final tokenIds = Int64List(seqLen);
  for (var i = 0; i < pieces.length; i++) {
    tokenIds[i] = vocab[pieces[i]] ?? unkId;
  }
  tokenIds[pieces.length] = eosId;

  final attentionMask = Int64List(seqLen)..fillRange(0, seqLen, 1);
  final maxNewTokens = math.min(192, math.max(32, seqLen * 3 + 16));

  final inputTensor = createInt64OrtTensor(tokenIds, [1, seqLen]);
  final attentionMaskTensor = createInt64OrtTensor(attentionMask, [1, seqLen]);
  final runOptions = OrtRunOptions();

  List<OrtValue?>? encoderOutputs;
  final generated = <int>[];

  try {
    encoderOutputs = engine.encoder.run(runOptions, {
      'input_ids': inputTensor,
      'attention_mask': attentionMaskTensor,
    });
    final hidden = encoderOutputs[0];
    if (hidden == null) return '';

    final decoderInputIds = <int>[padId];

    for (var step = 0; step < maxNewTokens; step++) {
      final decInput = createInt64OrtTensor(
        Int64List.fromList(decoderInputIds),
        [1, decoderInputIds.length],
      );
      List<OrtValue?>? decoderOutputs;
      try {
        // Request only 'logits' so ONNX Runtime skips materializing unused KV cache tensors.
        decoderOutputs = engine.decoder.run(
          runOptions,
          {
            'input_ids': decInput,
            'encoder_hidden_states': hidden,
            'encoder_attention_mask': attentionMaskTensor,
          },
          const ['logits'],
        );
        final logitsTensor = decoderOutputs[0];
        if (logitsTensor == null) break;

        final flat = ortFloatTensorView(logitsTensor);
        if (flat.isEmpty) break;
        final stepVocab = flat.length ~/ decoderInputIds.length;
        final base = flat.length - stepVocab;

        final banned = _repeatedTrigramBans(generated);
        var bestToken = eosId;
        var bestLogit = double.negativeInfinity;
        for (var i = 0; i < stepVocab; i++) {
          if (i == padId || i == unkId) continue;
          if (step == 0 && i == eosId) continue;
          if (banned.isNotEmpty && banned.contains(i)) continue;
          final v = flat[base + i];
          if (v > bestLogit) {
            bestLogit = v;
            bestToken = i;
          }
        }

        if (bestToken == eosId) break;
        generated.add(bestToken);
        decoderInputIds.add(bestToken);
      } finally {
        decInput.release();
        releaseOrtValues(decoderOutputs);
      }
    }
  } finally {
    inputTensor.release();
    attentionMaskTensor.release();
    releaseOrtValues(encoderOutputs);
    runOptions.release();
  }

  return _detokenize(generated, engine.reverseVocab, targetIsJapanese: targetIsJapanese);
}

/// In-place no-repeat-trigram ban set without sublist allocations.
Set<int> _repeatedTrigramBans(List<int> generated) {
  final len = generated.length;
  if (len < 2) return const {};
  final p0 = generated[len - 2];
  final p1 = generated[len - 1];
  Set<int>? banned;
  for (var i = 0; i <= len - 3; i++) {
    if (generated[i] == p0 && generated[i + 1] == p1) {
      (banned ??= <int>{}).add(generated[i + 2]);
    }
  }
  return banned ?? const {};
}

String _detokenize(List<int> ids, Map<int, String> reverseVocab, {required bool targetIsJapanese}) {
  final buffer = StringBuffer();
  for (final id in ids) {
    final tok = reverseVocab[id];
    if (tok == null || tok == '</s>' || tok == '<pad>' || tok == '<unk>') continue;
    buffer.write(tok);
  }
  var out = buffer.toString().replaceAll(SentencePieceModel.spaceMarker, ' ').trim();
  if (targetIsJapanese) {
    const cjk = r'[\u3000-\u9fff\uff00-\uffef]';
    out = out.replaceAll(RegExp('(?<=$cjk) +(?=$cjk)'), '');
    out = out.replaceAll(RegExp(r'\s+([。、．，！？!?」』）】])'), r'$1');
    out = out.replaceAll(RegExp(r'([「『（【])\s+'), r'$1');
  } else {
    out = out.replaceAll(RegExp(r'\s+([.,!?;:\)\]])'), r'$1');
    out = out.replaceAll(RegExp(r'([\(\[])\s+'), r'$1');
    out = out.replaceAll(RegExp(r"\s+'(s|m|re|ve|ll|d|t)\b"), r"'$1");
    out = out.replaceAll(RegExp(r"n\s+'t\b"), "n't");
  }
  return out.trim();
}

/// Convenience for platforms where native ONNX Runtime FFI is unavailable (web).
bool get onnxNmtSupported => !kIsWeb;
