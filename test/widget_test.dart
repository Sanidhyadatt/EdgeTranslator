import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:edge_translator/main.dart';
import 'package:edge_translator/core/services/audio_service.dart';
import 'package:edge_translator/core/utils/language_detector.dart';
import 'package:edge_translator/features/translation/data/datasources/sherpa_asr_service_impl.dart';
import 'package:edge_translator/features/translation/domain/models/chat_message.dart';
import 'package:edge_translator/providers/service_providers.dart';
import 'package:edge_translator/providers/translation_pipeline_provider.dart';

class FakeAudioService implements AudioService {
  bool _recording = false;
  bool _streaming = false;
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
    _recording = true;
  }

  @override
  Future<Float32List> stopRecording() async {
    _recording = false;
    return Float32List(16000);
  }

  @override
  Future<void> cancelRecording() async {
    _recording = false;
  }

  @override
  void dispose() {
    _controller.close();
  }
}

class MockTranslationService extends TranslationService {
  @override
  Future<String> translateToJapanese(String text) async => '渋谷駅はどこですか？';

  @override
  Future<String> translateToEnglish(String text) async => 'Hello! How are you?';

  @override
  Future<bool> areModelsDownloaded() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async => 1,
    );
  });
  testWidgets('EdgeTranslatorApp smoke test verifies header, unified language switch, mic, and send button', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioServiceProvider.overrideWithValue(FakeAudioService()),
        ],
        child: const EdgeTranslatorApp(),
      ),
    );

    // Header & offline badge
    expect(find.text('Edge Translator'), findsOneWidget);
    expect(find.text('100% Offline'), findsOneWidget);

    // Unified language switch button
    expect(find.text('🇺🇸 English'), findsOneWidget);
    expect(find.text('🇯🇵 日本語'), findsOneWidget);

    // Mic & Send icons
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    // Manual text input TextField
    expect(find.byType(TextField), findsOneWidget);

    // Initial status banner
    expect(find.text('System Ready'), findsOneWidget);
  });

  test('detectLanguage correctly distinguishes Japanese and English characters', () {
    // English text
    expect(detectLanguage('Hello, where is the train station?'), TranslationLanguage.english);
    expect(detectLanguage('Good morning! How are you?'), TranslationLanguage.english);
    expect(detectLanguage('1234567890 !?#'), TranslationLanguage.english);

    // Japanese Hiragana
    expect(detectLanguage('こんにちは'), TranslationLanguage.japanese);
    expect(detectLanguage('ありがとう'), TranslationLanguage.japanese);

    // Japanese Katakana
    expect(detectLanguage('ラーメン'), TranslationLanguage.japanese);
    expect(detectLanguage('コンビニ'), TranslationLanguage.japanese);

    // Japanese Kanji
    expect(detectLanguage('渋谷駅'), TranslationLanguage.japanese);
    expect(detectLanguage('東京タワー'), TranslationLanguage.japanese);
    expect(detectLanguage('日本へようこそ'), TranslationLanguage.japanese);
  });

  test('TranslationPipelineNotifier toggles continuous listening on and off', () async {
    final container = ProviderContainer(
      overrides: [
        audioServiceProvider.overrideWithValue(FakeAudioService()),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(translationPipelineProvider.notifier);

    expect(container.read(translationPipelineProvider).isContinuousListening, false);

    await notifier.startContinuousListening();
    expect(container.read(translationPipelineProvider).isContinuousListening, true);

    await notifier.stopContinuousListening();
    expect(container.read(translationPipelineProvider).isContinuousListening, false);
  });

  test('TranslationPipelineNotifier processText translates bidirectional EN to JA and JA to EN', () async {
    final container = ProviderContainer(
      overrides: [
        audioServiceProvider.overrideWithValue(FakeAudioService()),
        translationServiceProvider.overrideWithValue(MockTranslationService()),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(translationPipelineProvider.notifier);

    // 1. Test English input -> translates to Japanese & outputs to Japanese TTS
    final enFuture = notifier.processText('Where is Shibuya station?');
    expect(container.read(translationPipelineProvider).status, PipelineStatus.translating);
    expect(container.read(translationPipelineProvider).activeLanguage, TranslationLanguage.english);

    await enFuture;
    expect(container.read(translationPipelineProvider).status, PipelineStatus.idle);
    expect(container.read(translationPipelineProvider).messages.length, 1);

    final enMsg = container.read(translationPipelineProvider).messages.first;
    expect(enMsg.sourceLang, TranslationLanguage.english);
    expect(enMsg.targetLang, TranslationLanguage.japanese);
    expect(enMsg.originalText, 'Where is Shibuya station?');
    expect(enMsg.translatedText, isNotEmpty);

    // 2. Test Japanese input -> translates to English & outputs to English TTS
    final jaFuture = notifier.processText('こんにちは、お元気ですか？');
    expect(container.read(translationPipelineProvider).status, PipelineStatus.translating);
    expect(container.read(translationPipelineProvider).activeLanguage, TranslationLanguage.japanese);

    await jaFuture;
    expect(container.read(translationPipelineProvider).status, PipelineStatus.idle);
    expect(container.read(translationPipelineProvider).messages.length, 2);

    final jaMsg = container.read(translationPipelineProvider).messages.last;
    expect(jaMsg.sourceLang, TranslationLanguage.japanese);
    expect(jaMsg.targetLang, TranslationLanguage.english);
    expect(jaMsg.originalText, 'こんにちは、お元気ですか？');
    expect(jaMsg.translatedText, contains('Hello'));
  });

  test('Multilingual Whisper ASRService handles empty or silent audio gracefully', () async {
    final asrService = SherpaAsrServiceImpl();
    final resultEmpty = await asrService.transcribe(Float32List(0));
    expect(resultEmpty.text, isEmpty);
    expect(resultEmpty.language, 'en');

    final resultSilence = await asrService.transcribe(Float32List(16000));
    // Without active native hardware models, empty/silence safely returns empty transcript
    expect(resultSilence.text, isEmpty);
  });
}
