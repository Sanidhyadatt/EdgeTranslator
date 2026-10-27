import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:edge_translator/main.dart';
import 'package:edge_translator/features/translation/domain/models/chat_message.dart';
import 'package:edge_translator/providers/chat_translation_provider.dart';
import 'package:edge_translator/providers/service_providers.dart';
import 'widget_test.dart';

class TestTranslationService extends TranslationService {
  TestTranslationService();

  @override
  Future<bool> initializeModels({bool isWifiRequired = false}) async => true;

  @override
  Future<String> translateToJapanese(String text) async {
    if (text.contains('Shibuya')) return '渋谷駅はどこですか？';
    return '$text (日本語訳)';
  }

  @override
  Future<String> translateToEnglish(String text) async {
    if (text.contains('こんにちは')) return 'Hello! How are you?';
    return '$text (English translation)';
  }

  @override
  Future<bool> areModelsDownloaded() async {
    return true;
  }
}

void main() {
  group('ChatTranslationProvider Unit Tests', () {
    test('sendEnglishText creates message with translated Japanese text', () async {
      final testService = TestTranslationService();

      final container = ProviderContainer(
        overrides: [
          translationServiceProvider.overrideWithValue(testService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(chatTranslationProvider.notifier);

      await notifier.sendEnglishText('Where is Shibuya?');

      final state = container.read(chatTranslationProvider);
      expect(state.messages.length, 1);
      final msg = state.messages.first;
      expect(msg.sourceLang, TranslationLanguage.english);
      expect(msg.targetLang, TranslationLanguage.japanese);
      expect(msg.originalText, 'Where is Shibuya?');
      expect(msg.translatedText, '渋谷駅はどこですか？');
    });

    test('sendJapaneseText creates message with translated English text', () async {
      final testService = TestTranslationService();

      final container = ProviderContainer(
        overrides: [
          translationServiceProvider.overrideWithValue(testService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(chatTranslationProvider.notifier);

      await notifier.sendJapaneseText('こんにちは');

      final state = container.read(chatTranslationProvider);
      expect(state.messages.length, 1);
      final msg = state.messages.first;
      expect(msg.sourceLang, TranslationLanguage.japanese);
      expect(msg.targetLang, TranslationLanguage.english);
      expect(msg.originalText, 'こんにちは');
      expect(msg.translatedText, 'Hello! How are you?');
    });

    test('toggleInputLanguage alternates between English and Japanese', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatTranslationProvider.notifier);
      expect(container.read(chatTranslationProvider).activeInputLanguage, TranslationLanguage.english);

      notifier.toggleInputLanguage();
      expect(container.read(chatTranslationProvider).activeInputLanguage, TranslationLanguage.japanese);

      notifier.toggleInputLanguage();
      expect(container.read(chatTranslationProvider).activeInputLanguage, TranslationLanguage.english);
    });
  });

  group('Chat UI Widget Tests', () {
    testWidgets('renders offline badge (no download), unified toggle switch, mic, and send button', (WidgetTester tester) async {
      final testService = TestTranslationService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioServiceProvider.overrideWithValue(FakeAudioService()),
            translationServiceProvider.overrideWithValue(testService),
          ],
          child: const EdgeTranslatorApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // No model download UI: models ship pre-installed\r\n      expect(find.text('Download Models'), findsNothing);\r\n      expect(find.text('100% Offline'), findsOneWidget);

      // Input TextField is present
      expect(find.byType(TextField), findsOneWidget);

      // Unified switch pill is present
      expect(find.text('🇺🇸 English'), findsOneWidget);
      expect(find.text('🇯🇵 日本語'), findsOneWidget);

      // Unified Mic and Send buttons are present
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('typing English and pressing Send displays English on top and Japanese below on right side', (WidgetTester tester) async {
      final testService = TestTranslationService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioServiceProvider.overrideWithValue(FakeAudioService()),
            translationServiceProvider.overrideWithValue(testService),
          ],
          child: const EdgeTranslatorApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Enter English text into TextField
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Where is Shibuya?');
      await tester.pump();

      // Tap Send button (arrow upward)
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Verify the user's text and translated result are displayed
      expect(find.text('Where is Shibuya?'), findsWidgets);
      expect(find.text('渋谷駅はどこですか？'), findsWidgets);

      // Verify message alignment is to the right
      final alignFinder = find.ancestor(
        of: find.text('Where is Shibuya?'),
        matching: find.byType(Align),
      );
      expect(alignFinder, findsWidgets);
      final alignWidget = tester.widget<Align>(alignFinder.first);
      expect(alignWidget.alignment, Alignment.centerRight);
    });

    testWidgets('switching to Japanese, typing Japanese and pressing Send displays Japanese on top and English below on left side', (WidgetTester tester) async {
      final testService = TestTranslationService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioServiceProvider.overrideWithValue(FakeAudioService()),
            translationServiceProvider.overrideWithValue(testService),
          ],
          child: const EdgeTranslatorApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap the unified toggle to switch from English to Japanese
      await tester.tap(find.text('🇺🇸 English'));
      await tester.pump(const Duration(milliseconds: 300));

      // Enter Japanese text into TextField
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'こんにちは');
      await tester.pump();

      // Tap Send button
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Verify user's Japanese text and translated English result are displayed
      expect(find.text('こんにちは'), findsWidgets);
      expect(find.text('Hello! How are you?'), findsWidgets);

      // Verify message alignment is to the left
      final alignFinder = find.ancestor(
        of: find.text('こんにちは'),
        matching: find.byType(Align),
      );
      expect(alignFinder, findsWidgets);
      final alignWidget = tester.widget<Align>(alignFinder.first);
      expect(alignWidget.alignment, Alignment.centerLeft);
    });
  });
}

