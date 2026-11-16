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

  testWidgets('UI supports English/Japanese instruction modes, Pure Recording Done/Cancel, 0.8x Slow, History, and Settings without engines card', (WidgetTester tester) async {
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

    // Tap primary Mic FAB -> enters Pure Recording with English instructions by default
    await tester.tap(find.byIcon(Icons.mic_rounded).first);
    await tester.pump();

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.textContaining('Listening…', findRichText: true), findsOneWidget);
    expect(find.text('Speak freely — tap Done when finished'), findsOneWidget);
    expect(tts.spokenCalls, isEmpty);

    // Tap Done -> translates English -> Japanese and renders Hero card with Listen & 0.8x Slow
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Where is Shibuya station?'), findsOneWidget);
    expect(find.text('渋谷駅はどこですか。'), findsOneWidget);
    expect(find.text('Listen'), findsOneWidget);
    expect(find.text('0.8x Slow'), findsOneWidget);
    expect(find.text('Expand'), findsOneWidget);
    expect(tts.spokenCalls, isEmpty);

    // Enable 0.8x Slow and tap Listen -> speaks at 0.8x speed
    await tester.tap(find.text('0.8x Slow'));
    await tester.pump();
    await tester.tap(find.text('Listen'));
    await tester.pump();
    expect(tts.spokenCalls, [('渋谷駅はどこですか。', TranslationLanguage.japanese)]);
    expect(tts.speechRate, closeTo(0.8, 0.001));

    // Tap Expand -> opens fullscreen display modal and closes cleanly
    await tester.tap(find.text('Expand'));
    await tester.pumpAndSettle();
    expect(find.text('Display Translation'), findsOneWidget);
    expect(find.text('Play Audio'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Open Settings tab -> ON-DEVICE ENGINES card is removed; switch UI mode to 日本語
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.text('ON-DEVICE ENGINES'), findsNothing);
    expect(find.text('Whisper Tiny INT8 + Silero VAD'), findsNothing);
    expect(find.text('APP LANGUAGE'), findsOneWidget);

    // Adjust speed to 1.2x Fast & verify speechRate updates
    await tester.tap(find.text('1.2x Fast'));
    await tester.pump();
    expect(tts.speechRate, closeTo(1.2, 0.001));
    expect(find.text('1.20x'), findsOneWidget);

    // Switch entire UI to Japanese instructions (日本語)
    await tester.tap(find.text('日本語').first);
    await tester.pump();

    expect(find.text('設定'), findsWidgets);
    expect(find.text('翻訳'), findsOneWidget);
    expect(find.text('履歴'), findsOneWidget);
    expect(find.text('アプリ表示言語'), findsOneWidget);
    expect(find.text('音声・再生速度'), findsOneWidget);

    // Switch to Translate in Japanese mode -> Hero buttons & recording instructions are in Japanese
    await tester.tap(find.text('翻訳'));
    await tester.pump();
    expect(find.text('0.8倍速'), findsOneWidget);
    expect(find.text('拡大'), findsOneWidget);
    expect(find.text('聞く'), findsOneWidget);

    // Start recording in Japanese UI mode -> instructions show in Japanese
    await tester.tap(find.byIcon(Icons.mic_rounded).first);
    await tester.pump();
    expect(find.textContaining('聞き取っています…', findRichText: true), findsOneWidget);
    expect(find.text('話し終わったら「完了」を押してください'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('完了'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();

    // Open History tab in Japanese mode -> clear with localized confirmation dialog
    await tester.tap(find.text('履歴'));
    await tester.pump();
    expect(find.text('渋谷駅はどこですか。'), findsOneWidget);
    await tester.tap(find.text('すべて削除'));
    await tester.pumpAndSettle();
    expect(find.text('履歴をすべて削除しますか？'), findsOneWidget);
    await tester.tap(find.text('削除する'));
    await tester.pumpAndSettle();
    expect(find.text('履歴はまだありません'), findsOneWidget);
  });

  test('TtsPlayerService maps user speed multiplier cleanly to OS flutter_tts rate', () {
    expect(TtsPlayerService.toFlutterTtsRate(1.0), closeTo(0.5, 0.001));
    expect(TtsPlayerService.toFlutterTtsRate(0.8), closeTo(0.4, 0.001));
    expect(TtsPlayerService.toFlutterTtsRate(1.2), closeTo(0.6, 0.001));
  });

  testWidgets('Phone 390x844 layout renders without overflow across History search, Settings test audio, and auto-detect toggle', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    // Generate two translations (one EN->JA, one JA->EN)
    await tester.tap(find.text('Type'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Where is Shibuya station?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Type'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '渋谷駅はどこですか。');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Switch to History -> filter with search -> open earlier item in Translate
    await tester.tap(find.text('History'));
    await tester.pump();
    expect(find.text('All (2)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Shibuya station');
    await tester.pump();
    expect(find.text('Where is Shibuya station?'), findsWidgets);

    // Tapping a phrase promotes it to Hero in Translate
    await tester.tap(find.text('Where is Shibuya station?').last);
    await tester.pump();
    expect(find.text('Type'), findsOneWidget);
    expect(find.text('EN → JA'), findsOneWidget);

    // Switch to Settings -> test EN voice, test JA voice, toggle auto-detect
    await tester.tap(find.text('Settings'));
    await tester.pump();

    await tester.tap(find.text('Test EN Voice'));
    await tester.pump();
    expect(tts.spokenCalls.last, ('Hello, this is a speech speed preview.', TranslationLanguage.english));

    await tester.tap(find.text('Test JA Voice'));
    await tester.pump();
    expect(tts.spokenCalls.last, ('こんにちは、音声速度のテストです。', TranslationLanguage.japanese));

    await tester.ensureVisible(find.text('Auto-detect typed script'));
    await tester.pump();
    await tester.tap(find.text('Auto-detect typed script'));
    await tester.pump();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, false);
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
