import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/services/nmt_service.dart';
import 'model_loader.dart';
import 'sentencepiece_model.dart';

/// Everything needed to translate in a single direction.
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

/// 100% on-device Neural Machine Translation using the MarianMT ONNX models that
/// ship inside the app bundle (`assets/models/nmt_en_ja` and `nmt_ja_en`).
///
/// No network access and no model download is ever required: the encoder/decoder
/// weights, SentencePiece tokenizers and vocabularies are pre-installed assets.
class OnnxNmtServiceImpl implements NmtService {
  final ModelLoader _modelLoader;
  final String? enJaEncoderPath;
  final String? enJaDecoderPath;
  final String? jaEnEncoderPath;
  final String? jaEnDecoderPath;

  bool _initialized = false;
  Future<void>? _initFuture;

  _DirectionEngine? _enJa;
  _DirectionEngine? _jaEn;

  /// True once at least one direction has real ONNX weights loaded.
  bool get isReady => _enJa != null || _jaEn != null;

  OnnxNmtServiceImpl({
    ModelLoader? modelLoader,
    this.enJaEncoderPath,
    this.enJaDecoderPath,
    this.jaEnEncoderPath,
    this.jaEnDecoderPath,
  }) : _modelLoader = modelLoader ?? const ModelLoader();

  @override
  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initFuture ??= _doInitialize().whenComplete(() {
      _initialized = true;
      _initFuture = null;
    });
  }

  Future<void> _doInitialize() async {
    AppLogger.info('OnnxNmtService', 'Initializing offline MarianMT ONNX translation engines...');

    try {
      try {
        await _modelLoader.extractModelAssets();
      } catch (e) {
        AppLogger.error('OnnxNmtService', 'Asset extraction notice: $e');
      }

      final nmtPaths = await _modelLoader.getNmtModelPaths();

      try {
        OrtEnv.instance.init();
      } catch (_) {
        // OrtEnv might already be initialized by another subsystem
      }

      _enJa = await _loadDirection(
        label: 'EN->JA',
        encoderPath: enJaEncoderPath ?? nmtPaths.enJa.encoderPath,
        decoderPath: enJaDecoderPath ?? nmtPaths.enJa.decoderPath,
        vocabPath: nmtPaths.enJa.vocabJsonPath,
        sourceSpmPath: nmtPaths.enJa.sourceSpmPath,
      );
      _jaEn = await _loadDirection(
        label: 'JA->EN',
        encoderPath: jaEnEncoderPath ?? nmtPaths.jaEn.encoderPath,
        decoderPath: jaEnDecoderPath ?? nmtPaths.jaEn.decoderPath,
        vocabPath: nmtPaths.jaEn.vocabJsonPath,
        sourceSpmPath: nmtPaths.jaEn.sourceSpmPath,
      );
    } catch (e, st) {
      AppLogger.error('OnnxNmtService', 'Initialization error in MarianMT ONNX translation engine', e, st);
    }
  }

  Future<_DirectionEngine?> _loadDirection({
    required String label,
    required String encoderPath,
    required String decoderPath,
    required String? vocabPath,
    required String? sourceSpmPath,
  }) async {
    final encFile = File(encoderPath);
    final decFile = File(decoderPath);
    if (!await encFile.exists() || !await decFile.exists()) {
      AppLogger.warning('OnnxNmtService', '$label ONNX weights not found at: $encoderPath');
      return null;
    }
    if (vocabPath == null || sourceSpmPath == null) return null;
    final vocabFile = File(vocabPath);
    final spmFile = File(sourceSpmPath);
    if (!await vocabFile.exists() || !await spmFile.exists()) {
      AppLogger.warning('OnnxNmtService', '$label vocabulary / SentencePiece model missing.');
      return null;
    }

    try {
      final map = jsonDecode(await vocabFile.readAsString()) as Map<String, dynamic>;
      final vocab = map.map((k, v) => MapEntry(k, (v as num).toInt()));
      final reverse = <int, String>{for (final e in vocab.entries) e.value: e.key};
      final spm = SentencePieceModel.parse(await spmFile.readAsBytes());

      final options = OrtSessionOptions();
      final encoder = await _createSession(encFile, options);
      final decoder = await _createSession(decFile, options);

      AppLogger.info(
        'OnnxNmtService',
        '$label ready: ${vocab.length} vocab tokens, ${spm.vocabSize} SentencePiece pieces.',
      );
      return _DirectionEngine(
        encoder: encoder,
        decoder: decoder,
        vocab: vocab,
        reverseVocab: reverse,
        sourceSpm: spm,
      );
    } catch (e, st) {
      AppLogger.error('OnnxNmtService', 'Could not initialize $label ONNX engine', e, st);
      return null;
    }
  }

  Future<OrtSession> _createSession(File file, OrtSessionOptions options) async {
    if (Platform.isWindows) {
      // On Windows, OrtSession.fromBuffer avoids path encoding issues.
      final bytes = await file.readAsBytes();
      return OrtSession.fromBuffer(bytes, options);
    }
    try {
      return OrtSession.fromFile(file, options);
    } catch (_) {
      final bytes = await file.readAsBytes();
      return OrtSession.fromBuffer(bytes, options);
    }
  }

  /// Translates fully offline. Returns an empty string only when the on-device
  /// engine for that direction is unavailable or produced no usable output.
  @override
  Future<String> translate(String text, {required String sourceLang, required String targetLang}) async {
    if (!_initialized) {
      await initialize();
    }

    final clean = text.trim();
    if (clean.isEmpty) return '';

    final isEnToJa = sourceLang.toLowerCase().startsWith('en');
    final engine = isEnToJa ? _enJa : _jaEn;
    if (engine == null) {
      AppLogger.warning('OnnxNmtService', 'ONNX engine for ${isEnToJa ? 'EN->JA' : 'JA->EN'} is unavailable.');
      return '';
    }

    try {
      final sentences = _splitSentences(clean);
      final translatedParts = <String>[];
      for (final sentence in sentences) {
        final translated = _runOnnxTranslation(
          sentence,
          engine,
          targetIsJapanese: isEnToJa,
        );
        if (_isValidTranslation(translated)) {
          translatedParts.add(translated);
        }
      }
      final result = isEnToJa ? translatedParts.join('') : translatedParts.join(' ');
      if (_isValidTranslation(result)) {
        AppLogger.info('OnnxNmtService', '${isEnToJa ? 'EN->JA' : 'JA->EN'} on-device: "$clean" -> "$result"');
        return result;
      }
      AppLogger.warning('OnnxNmtService', 'Degenerate ONNX output ("$result").');
    } catch (err, st) {
      AppLogger.error('OnnxNmtService', 'ONNX runtime inference exception', err, st);
    }
    return '';
  }

  /// Splits multi-sentence text on sentence-ending punctuation while keeping the
  /// punctuation attached to each sentence so NMT models stay in their optimal
  /// single-sentence training distribution.
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

    // 1. SentencePiece-tokenize the source text (constrained to vocab.json), then map pieces -> vocab ids.
    final pieces = engine.sourceSpm.encode(text, allowedPieces: engine.vocabSet);
    if (pieces.isEmpty) return '';
    final tokenIds = <int>[
      for (final piece in pieces) vocab[piece] ?? unkId,
      eosId,
    ];
    final seqLen = tokenIds.length;
    final maxNewTokens = math.max(96, math.min(256, seqLen * 4));

    final inputTensor = OrtValueTensor.createTensorWithDataList(tokenIds, [1, seqLen]);
    final attentionMaskTensor =
        OrtValueTensor.createTensorWithDataList(List<int>.filled(seqLen, 1), [1, seqLen]);
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

      // Marian decoders start from the pad token.
      final decoderInputIds = <int>[padId];

      for (var step = 0; step < maxNewTokens; step++) {
        final decInput = OrtValueTensor.createTensorWithDataList(
          decoderInputIds,
          [1, decoderInputIds.length],
        );
        List<OrtValue?>? decoderOutputs;
        try {
          decoderOutputs = engine.decoder.run(runOptions, {
            'input_ids': decInput,
            'encoder_hidden_states': hidden,
            'encoder_attention_mask': attentionMaskTensor,
          });
          final logitsTensor = decoderOutputs[0];
          if (logitsTensor == null || logitsTensor.value == null) break;

          final raw = logitsTensor.value as List<dynamic>;
          final batch = raw[0] as List<dynamic>;
          final last = batch.last as List<dynamic>;

          final banned = _repeatedNgramBans(generated);
          var bestToken = eosId;
          var bestLogit = double.negativeInfinity;
          for (var i = 0; i < last.length; i++) {
            if (i == padId || i == unkId || banned.contains(i)) continue;
            if (step == 0 && i == eosId) continue;
            final v = (last[i] as num).toDouble();
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
          if (decoderOutputs != null) {
            for (final out in decoderOutputs) {
              out?.release();
            }
          }
        }
      }
    } finally {
      inputTensor.release();
      attentionMaskTensor.release();
      if (encoderOutputs != null) {
        for (final out in encoderOutputs) {
          out?.release();
        }
      }
      runOptions.release();
    }

    return _detokenize(generated, engine.reverseVocab, targetIsJapanese: targetIsJapanese);
  }

  /// No-repeat-trigram blocking: returns tokens that would repeat an n-gram.
  Set<int> _repeatedNgramBans(List<int> generated, {int n = 3}) {
    if (generated.length < n - 1) return const {};
    final prefix = generated.sublist(generated.length - (n - 1));
    final banned = <int>{};
    for (var i = 0; i + n <= generated.length; i++) {
      var match = true;
      for (var k = 0; k < n - 1; k++) {
        if (generated[i + k] != prefix[k]) {
          match = false;
          break;
        }
      }
      if (match) banned.add(generated[i + n - 1]);
    }
    return banned;
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
      // Remove spaces between CJK characters and around CJK/sentence punctuation.
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

  @override
  Future<void> dispose() async {
    _enJa?.release();
    _jaEn?.release();
    _enJa = null;
    _jaEn = null;
    _initialized = false;
    AppLogger.info('OnnxNmtService', 'Disposed OnnxNmtService ONNX sessions');
  }
}

/// Convenience for platforms where native ONNX Runtime FFI is unavailable (web).
bool get onnxNmtSupported => !kIsWeb;
