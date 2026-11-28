import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:edge_translator/core/services/tts_player_service.dart';
import 'package:edge_translator/core/utils/background_worker.dart';
import 'package:edge_translator/features/translation/data/datasources/japanese_melo_g2p.dart';
import 'package:edge_translator/features/translation/data/datasources/model_loader.dart';
import 'package:edge_translator/features/translation/data/datasources/onnx_nmt_service_impl.dart';
import 'package:edge_translator/features/translation/data/datasources/sherpa_asr_service_impl.dart';
import 'package:edge_translator/features/translation/data/datasources/sherpa_tts_service_impl.dart';
import 'package:edge_translator/features/translation/domain/models/chat_message.dart';
import 'package:edge_translator/features/translation/domain/services/tts_service.dart';

Object? _testWorkerHandler(Object? request, Map<String, Object?> state) {
  final req = request as Map<Object?, Object?>;
  switch (req['op']) {
    case 'inc':
      final next = ((state['count'] as int?) ?? 0) + ((req['by'] as int?) ?? 1);
      state['count'] = next;
      return next;
    case 'fail':
      throw ArgumentError('intentional worker failure');
    case 'dispose':
      final markerPath = req['markerPath'] as String?;
      if (markerPath != null) {
        File(markerPath).writeAsStringSync('disposed:${state['count'] ?? 0}');
      }
      state.clear();
      return true;
    default:
      return null;
  }
}

class _PipeliningSpyTtsService implements TtsService {
  final List<String> calls = [];
  final List<String> createdFiles = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<String> synthesize(
    String text, {
    String language = 'ja',
    double speed = 1.0,
  }) async {
    calls.add(text);
    final f = File(p.join(
      Directory.systemTemp.path,
      'ikho_pipe_test_${DateTime.now().microsecondsSinceEpoch}_${calls.length}.wav',
    ));
    f.writeAsBytesSync(const [0, 1, 2, 3]);
    createdFiles.add(f.path);
    return f.path;
  }

  @override
  Future<void> dispose() async {
    for (final path in createdFiles) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}

class _FakeAudioPlayer extends Fake implements AudioPlayer {
  final StreamController<void> _completeController = StreamController<void>.broadcast();
  final List<String> playedPaths = [];
  Completer<void>? _playStarted;

  @override
  Stream<void> get onPlayerComplete => _completeController.stream;

  Future<void> waitForNextPlay() {
    final c = Completer<void>();
    _playStarted = c;
    return c.future;
  }

  void completePlayback() {
    if (!_completeController.isClosed) {
      _completeController.add(null);
    }
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    if (source is DeviceFileSource) {
      playedPaths.add(source.path);
    }
    _playStarted?.complete();
    _playStarted = null;
  }

  @override
  Future<void> dispose() async {
    await _completeController.close();
  }
}

class _ReadOnlyLocalModelLoader extends ModelLoader {
  final Directory _dir;

  const _ReadOnlyLocalModelLoader(this._dir)
      : super(customModelsDirectory: _dir, useAndroidChannel: false);

  @override
  Future<Directory> get modelsDirectory async => _dir;

  @override
  Future<List<File>> extractModelAssets({bool overwrite = false}) async => const [];

  @override
  Future<List<File>> extractNmtModels({bool overwrite = false}) async => const [];

  @override
  Future<List<File>> extractTtsModels({bool overwrite = false}) async => const [];
}

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

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => 1,
    );
  });

  group('Performance optimizations', () {
    test('BackgroundWorker runs stateful requests, propagates errors, and runs finalRequest on close', () async {
      final tempDir = await Directory.systemTemp.createTemp('ikho_worker_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final marker = File(p.join(tempDir.path, 'dispose_marker.txt'));
      final worker = await BackgroundWorker.spawn(
        _testWorkerHandler,
        debugName: 'test-worker',
      );

      expect(await worker.request({'op': 'inc', 'by': 2}), 2);
      expect(await worker.request({'op': 'inc', 'by': 5}), 7);

      await expectLater(
        worker.request({'op': 'fail'}),
        throwsA(isA<StateError>()),
      );

      await worker.close(
        finalRequest: {'op': 'dispose', 'markerPath': marker.path},
      );
      expect(worker.isClosed, isTrue);
      expect(marker.existsSync(), isTrue);
      expect(marker.readAsStringSync(), 'disposed:7');

      await expectLater(
        worker.request({'op': 'inc', 'by': 1}),
        throwsA(isA<StateError>()),
      );
    });

    test('SherpaAsrServiceImpl short-circuits empty and silent audio without initializing native models', () async {
      final asr = SherpaAsrServiceImpl(
        senseVoiceModelPath: 'non_existent_model.onnx',
        senseVoiceTokensPath: 'non_existent_tokens.txt',
      );
      addTearDown(asr.dispose);

      final emptyRes = await asr.transcribe(Float32List(0));
      expect(emptyRes.text, isEmpty);
      expect(emptyRes.language, 'en');
      expect(asr.isReady, isFalse);

      final silentRes = await asr.transcribe(Float32List(16000));
      expect(silentRes.text, isEmpty);
      expect(silentRes.language, 'en');
      expect(asr.isReady, isFalse);
      expect(asr.lastInitError, isNull);
    });

    test('TtsPlayerService pipelines synthesis of sentence N+1 while sentence N plays', () async {
      final spyTts = _PipeliningSpyTtsService();
      addTearDown(spyTts.dispose);
      final fakePlayer = _FakeAudioPlayer();
      final playerService = TtsPlayerService(
        offlineTtsService: spyTts,
        audioPlayer: fakePlayer,
      );
      addTearDown(playerService.dispose);

      final firstPlay = fakePlayer.waitForNextPlay();
      final speakFuture = playerService.speak(
        'First sentence. Second sentence.',
        language: TranslationLanguage.english,
      );

      await firstPlay.timeout(const Duration(seconds: 5));
      // Allow microtasks to pre-synthesize sentence 2 while sentence 1 is playing
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(spyTts.calls, ['First sentence.', 'Second sentence.']);
      expect(fakePlayer.playedPaths.length, 1);

      final secondPlay = fakePlayer.waitForNextPlay();
      fakePlayer.completePlayback();
      await secondPlay.timeout(const Duration(seconds: 5));
      fakePlayer.completePlayback();

      await speakFuture.timeout(const Duration(seconds: 5));
      expect(fakePlayer.playedPaths.length, 2);
    });

    final localModelsDir = Directory(p.join(Directory.current.path, 'assets', 'models'));
    final hasLocalNmt = File(p.join(localModelsDir.path, 'nmt_en_ja', 'encoder_model_quantized.onnx')).existsSync() &&
        File(p.join(localModelsDir.path, 'nmt_ja_en', 'encoder_model_quantized.onnx')).existsSync();

    test(
      'OnnxNmtServiceImpl translates off-thread with zero-copy logits and hits LRU cache on repeat',
      () async {
        final loader = _ReadOnlyLocalModelLoader(localModelsDir);
        final nmt = OnnxNmtServiceImpl(modelLoader: loader);
        addTearDown(nmt.dispose);

        await nmt.initialize();
        expect(nmt.isReady, isTrue);

        final enToJa = await nmt.translate(
          'Where is Shibuya station?',
          sourceLang: 'en',
          targetLang: 'ja',
        );
        expect(enToJa, contains('渋谷'));

        final jaToEn = await nmt.translate(
          'こんにちは',
          sourceLang: 'ja',
          targetLang: 'en',
        );
        expect(jaToEn.toLowerCase(), contains('hello'));

        // Repeat call hits LRU cache immediately
        final sw = Stopwatch()..start();
        final cachedEnToJa = await nmt.translate(
          'Where is Shibuya station?',
          sourceLang: 'en',
          targetLang: 'ja',
        );
        sw.stop();
        expect(cachedEnToJa, enToJa);
        expect(sw.elapsedMilliseconds, lessThan(20));
      },
      skip: !hasLocalNmt ? 'Local assets/models NMT weights not present' : false,
    );

    final hasLocalTts = File(p.join(localModelsDir.path, 'tts_ja', 'model.onnx')).existsSync() &&
        File(p.join(localModelsDir.path, 'tts_ja', 'tokens.txt')).existsSync();

    test(
      'SherpaTtsServiceImpl synthesizes in worker, caches WAV path, and cleans up on dispose',
      () async {
        final loader = _ReadOnlyLocalModelLoader(localModelsDir);
        final tts = SherpaTtsServiceImpl(modelLoader: loader);

        final wav1 = await tts.synthesize('こんにちは', language: 'ja');
        expect(wav1, isNotEmpty);
        expect(File(wav1).existsSync(), isTrue);

        final sw = Stopwatch()..start();
        final wav2 = await tts.synthesize('こんにちは', language: 'ja');
        sw.stop();
        expect(wav2, wav1);
        expect(sw.elapsedMilliseconds, lessThan(20));

        await tts.dispose();
        expect(File(wav1).existsSync(), isFalse);
      },
      skip: !hasLocalTts ? 'Local assets/models TTS weights not present' : false,
    );

    test('JapaneseMeloG2p preserves long vowels for Kanji compounds and reads multi-digit numbers naturally', () {
      final g2p = JapaneseMeloG2p.fromFiles(
        tokenLines: [
          '_ 0',
          't 1',
          'o 2',
          'u 3',
          'ky 4',
          'k 5',
          'e 6',
          'i 7',
          'g 8',
          'n 9',
          'h 10',
          'N 11',
          'j 12',
        ],
        lexiconLines: [
          '東京 t o ky o 6 6 6 6',
          '空港 k u k o 6 6 6 6',
          '英語 e g o 6 6 6',
          '日本 n i q p o N 6 6 6 6 6',
        ],
      );

      List<int> stripBlanks(List<int> ids) => ids.where((id) => id != 0).toList();

      // 東京 -> t o u ky o u (1, 2, 3, 4, 2, 3)
      expect(stripBlanks(g2p.encodeSentences('東京').single), [1, 2, 3, 4, 2, 3]);
      // 空港 -> k u u k o u (5, 3, 3, 5, 2, 3)
      expect(stripBlanks(g2p.encodeSentences('空港').single), [5, 3, 3, 5, 2, 3]);
      // 英語 -> e i g o (6, 7, 8, 2)
      expect(stripBlanks(g2p.encodeSentences('英語').single), [6, 7, 8, 2]);
      // 日本 -> n i h o N (9, 7, 10, 2, 11)
      expect(stripBlanks(g2p.encodeSentences('日本').single), [9, 7, 10, 2, 11]);
      // 10 -> j u u (12, 3, 3), 25 -> n i j u u g o (9, 7, 12, 3, 3, 8, 2)
      expect(stripBlanks(g2p.encodeSentences('10').single), [12, 3, 3]);
      expect(stripBlanks(g2p.encodeSentences('25').single), [9, 7, 12, 3, 3, 8, 2]);
    });

    test(
      'SherpaTtsServiceImpl deduplicates concurrent in-flight synthesis requests',
      () async {
        final loader = _ReadOnlyLocalModelLoader(localModelsDir);
        final tts = SherpaTtsServiceImpl(modelLoader: loader);
        addTearDown(tts.dispose);

        final results = await Future.wait([
          tts.synthesize('東京', language: 'ja'),
          tts.synthesize('東京', language: 'ja'),
        ]);
        expect(results[0], isNotEmpty);
        expect(results[1], results[0]);
        expect(File(results[0]).existsSync(), isTrue);
      },
      skip: !hasLocalTts ? 'Local assets/models TTS weights not present' : false,
    );
  });
}
