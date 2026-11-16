import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edge_translator/core/services/audio_service.dart';
import 'package:edge_translator/core/services/tts_player_service.dart';
import 'package:edge_translator/features/translation/data/datasources/japanese_melo_g2p.dart';
import 'package:edge_translator/features/translation/domain/models/asr_result.dart';
import 'package:edge_translator/features/translation/domain/models/chat_message.dart';
import 'package:edge_translator/features/translation/domain/services/asr_service.dart';
import 'package:edge_translator/features/translation/domain/services/nmt_service.dart';
import 'package:edge_translator/main.dart';
import 'package:edge_translator/providers/service_providers.dart';
import 'package:edge_translator/providers/translation_pipeline_provider.dart';

class RecordingFakeAudioService implements AudioService {
  bool _recording = false;
  bool _streaming = false;
  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;
  final StreamController<Float32List> _controller = StreamController<Float32List>.broadcast();

  @override
  bool get isRecording => _recording;

  @override
  bool get isStreaming => _streaming;

  @override
  Stream<Float32List> get audioStream => _controller.stream;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> startContinuousStream() async {
    _streaming = true;
  }

  @override
  Future<void> stopContinuousStream() async {
    _streaming = false;
  }

  @override
  Future<void> startRecording() async {
    startCount++;
    _recording = true;
  }

  @override
  Future<Float32List> stopRecording() async {
    stopCount++;
    _recording = false;
    return Float32List(16000); // 1 second of samples
  }

  @override
  Future<void> cancelRecording() async {
    cancelCount++;
    _recording = false;
  }

  @override
  void dispose() {
    _controller.close();
  }
}

class FakeAsrService implements AsrService {
  AsrResult nextResult;
  FakeAsrService(this.nextResult);

  @override
  Future<void> initialize() async {}

  @override
  void acceptVadWaveform(Float32List samples) {}

  @override
  bool hasSpeechSegment() => false;

  @override
  Float32List? popSpeechSegment() => null;

  @override
  Float32List? flushSpeechSegment() => null;

  @override
  void resetVad() {}

  @override
  Future<AsrResult> transcribe(Float32List samples) async => nextResult;

  @override
  Future<void> dispose() async {}
}

class RecordingFakeNmtService implements NmtService {
  String? lastSourceLang;
  String? lastTargetLang;
  String? lastText;

  @override
  Future<void> initialize() async {}

  @override
  Future<String> translate(
    String text, {
    required String sourceLang,
    required String targetLang,
  }) async {
    lastText = text;
    lastSourceLang = sourceLang;
    lastTargetLang = targetLang;
    if (sourceLang == 'en' && targetLang == 'ja') {
      return '渋谷駅はどこですか。';
    }
    return 'Where is Shibuya Station?';
  }

  @override
  Future<void> dispose() async {}
}

class SpyTtsPlayerService extends TtsPlayerService {
  final List<(String text, TranslationLanguage lang)> spokenCalls = [];
  int stopCalls = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak(String text, {required TranslationLanguage language}) async {
    spokenCalls.add((text, language));
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

void main() {
  test('Voice listening stays active until Stop is pressed, translates to appropriate language, and does not auto-speak', () async {
    final audio = RecordingFakeAudioService();
    final asr = FakeAsrService(const AsrResult(text: '渋谷駅はどこですか？', language: 'ja'));
    final nmt = RecordingFakeNmtService();
    final tts = SpyTtsPlayerService();

    final container = ProviderContainer(
      overrides: [
        audioServiceProvider.overrideWithValue(audio),
        asrServiceProvider.overrideWithValue(asr),
        nmtServiceProvider.overrideWithValue(nmt),
        ttsPlayerServiceProvider.overrideWithValue(tts),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(translationPipelineProvider.notifier);

    // 1. Start listening (stays recording until Stop is pressed, even if toggle was English)
    await notifier.toggleVoiceListening();
    expect(audio.startCount, 1);
    expect(audio.isRecording, true);
    expect(container.read(translationPipelineProvider).status, PipelineStatus.recording);

    // 2. Press Stop -> transcribes Japanese and translates JA -> EN automatically
    await notifier.toggleVoiceListening();
    expect(audio.stopCount, 1);
    expect(audio.isRecording, false);

    final state = container.read(translationPipelineProvider);
    expect(state.status, PipelineStatus.idle);
    expect(state.messages.length, 1);
    expect(state.messages.first.sourceLang, TranslationLanguage.japanese);
    expect(state.messages.first.targetLang, TranslationLanguage.english);
    expect(state.messages.first.originalText, '渋谷駅はどこですか？');
    expect(state.messages.first.translatedText, 'Where is Shibuya Station?');
    expect(nmt.lastSourceLang, 'ja');
    expect(nmt.lastTargetLang, 'en');

    // 3. Verify it did NOT speak automatically after generating translation
    expect(tts.spokenCalls, isEmpty);

    // 4. Ask to speak -> speaks translated text in target language
    await notifier.playMessageAudio(state.messages.first.id);
    expect(tts.spokenCalls.length, 1);
    expect(tts.spokenCalls.first, ('Where is Shibuya Station?', TranslationLanguage.english));
  });

  test('Cancel recording discards audio without translating', () async {
    final audio = RecordingFakeAudioService();
    final asr = FakeAsrService(const AsrResult(text: 'Hello', language: 'en'));
    final nmt = RecordingFakeNmtService();
    final tts = SpyTtsPlayerService();

    final container = ProviderContainer(
      overrides: [
        audioServiceProvider.overrideWithValue(audio),
        asrServiceProvider.overrideWithValue(asr),
        nmtServiceProvider.overrideWithValue(nmt),
        ttsPlayerServiceProvider.overrideWithValue(tts),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(translationPipelineProvider.notifier);
    await notifier.startVoiceListening();
    expect(container.read(translationPipelineProvider).status, PipelineStatus.recording);

    await notifier.cancelVoiceListening();
    expect(audio.cancelCount, 1);
    expect(audio.isRecording, false);
    expect(container.read(translationPipelineProvider).status, PipelineStatus.idle);
    expect(container.read(translationPipelineProvider).messages, isEmpty);
  });

  testWidgets('UI shows listening Stop/Cancel controls while recording and Speak button on generated card', (WidgetTester tester) async {
    final audio = RecordingFakeAudioService();
    final asr = FakeAsrService(const AsrResult(text: 'Where is Shibuya station?', language: 'en'));
    final nmt = RecordingFakeNmtService();
    final tts = SpyTtsPlayerService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioServiceProvider.overrideWithValue(audio),
          asrServiceProvider.overrideWithValue(asr),
          nmtServiceProvider.overrideWithValue(nmt),
          ttsPlayerServiceProvider.overrideWithValue(tts),
        ],
        child: const EdgeTranslatorApp(),
      ),
    );
    await tester.pump();

    // Tap Mic -> enters listening mode with Stop and Cancel controls
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();

    expect(find.text('Stop'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(tts.spokenCalls, isEmpty);

    // Tap Stop -> translates English -> Japanese and renders Speak pill
    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Where is Shibuya station?'), findsOneWidget);
    expect(find.text('渋谷駅はどこですか。'), findsOneWidget);
    expect(find.text('Speak'), findsOneWidget);
    expect(tts.spokenCalls, isEmpty);

    // Tap Speak -> speaks the translated Japanese text
    await tester.tap(find.text('Speak'));
    await tester.pump();
    expect(tts.spokenCalls, [('渋谷駅はどこですか。', TranslationLanguage.japanese)]);
  });

  test('JapaneseMeloG2p handles lexicon words, hiragana/katakana fallback, and punctuation', () {
    final g2p = JapaneseMeloG2p.fromFiles(
      tokenLines: [
        '_ 0',
        ', 1',
        '. 2',
        '? 3',
        'sh 4',
        'i 5',
        'b 6',
        'u 7',
        'y 8',
        'a 9',
        'e 10',
        'k 11',
        'o 12',
        'd 13',
        's 14',
        'N 15',
        'q 16',
        'r 17',
      ],
      lexiconLines: [
        '渋谷 sh i b u y a 0 0 0 0 0 0',
        '駅 e k i 0 0 0',
      ],
    );

    final encoded = g2p.encodeSentences('渋谷駅は？アレックス。');
    expect(encoded.length, 2);
    expect(encoded[0].first, 0);
    expect(encoded[0].last, 0);
    expect(encoded[1].length, greaterThan(5));
  });
}
