import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'package:edge_translator/core/services/audio_service.dart';
import 'package:edge_translator/features/translation/domain/models/chat_message.dart';
import 'package:edge_translator/providers/service_providers.dart';
import 'package:edge_translator/providers/translation_pipeline_provider.dart';

class MockAudioService implements AudioService {
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

class MockChatTranslationService extends TranslationService {
  @override
  Future<String> translateToJapanese(String text) async {
    return 'お元気ですか？';
  }

  @override
  Future<String> translateToEnglish(String text) async {
    return 'Hello, how are you?';
  }

  @override
  Future<bool> areModelsDownloaded() async => true;

  @override
  Future<bool> initializeModels({bool isWifiRequired = false}) async => true;
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

  group('Chat & Voice System Complete Verification', () {
    test('English chat input translates to Japanese and adds to messages', () async {
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(MockAudioService()),
          translationServiceProvider.overrideWithValue(MockChatTranslationService()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(translationPipelineProvider.notifier);

      // Verify initial empty state
      expect(container.read(translationPipelineProvider).messages.isEmpty, true);

      // Send English chat message
      await notifier.processText('How are you?', explicitSourceLang: TranslationLanguage.english);

      // Verify state after translation
      final state = container.read(translationPipelineProvider);
      expect(state.status, PipelineStatus.idle);
      expect(state.messages.length, 1);

      final msg = state.messages.first;
      expect(msg.sourceLang, TranslationLanguage.english);
      expect(msg.targetLang, TranslationLanguage.japanese);
      expect(msg.originalText, 'How are you?');
      expect(msg.translatedText, 'お元気ですか？');
    });

    test('Japanese chat input translates to English and adds to messages', () async {
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(MockAudioService()),
          translationServiceProvider.overrideWithValue(MockChatTranslationService()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(translationPipelineProvider.notifier);

      // Send Japanese chat message
      await notifier.processText('こんにちは', explicitSourceLang: TranslationLanguage.japanese);

      final state = container.read(translationPipelineProvider);
      expect(state.status, PipelineStatus.idle);
      expect(state.messages.length, 1);

      final msg = state.messages.first;
      expect(msg.sourceLang, TranslationLanguage.japanese);
      expect(msg.targetLang, TranslationLanguage.english);
      expect(msg.originalText, 'こんにちは');
      expect(msg.translatedText, 'Hello, how are you?');
    });

    test('Stop Hearing button cancels listening without hanging', () async {
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(MockAudioService()),
          translationServiceProvider.overrideWithValue(MockChatTranslationService()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(translationPipelineProvider.notifier);

      await notifier.startContinuousListening();
      expect(container.read(translationPipelineProvider).isContinuousListening, true);

      await notifier.stopHearing();
      expect(container.read(translationPipelineProvider).isContinuousListening, false);
      expect(container.read(translationPipelineProvider).status, PipelineStatus.idle);
    });

    test('Done Speaking button stops continuous stream cleanly', () async {
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(MockAudioService()),
          translationServiceProvider.overrideWithValue(MockChatTranslationService()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(translationPipelineProvider.notifier);

      await notifier.startContinuousListening();
      expect(container.read(translationPipelineProvider).isContinuousListening, true);

      await notifier.doneSpeakingNow();
      expect(container.read(translationPipelineProvider).isContinuousListening, false);
    });
  });
}
