import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:edge_translator/main.dart';
import 'package:edge_translator/features/translation/domain/models/chat_message.dart';
import 'package:edge_translator/features/translation/presentation/widgets/japanese_cat_face.dart';
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
    testWidgets('renders clean IKHO header, direction pill, dock, and navigation tabs', (WidgetTester tester) async {
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

      // No noisy download or offline chip clutter in header
      expect(find.text('Download Models'), findsNothing);
      expect(find.text('100% Offline'), findsNothing);
      expect(find.text('IKHO'), findsOneWidget);

      // Direction pill & floating dock (single main mic + Japanese cat face)
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Japanese'), findsWidgets);
      expect(find.text('Type'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byType(JapaneseCatFace), findsOneWidget);
    });

    testWidgets('typing English via Type dock translates into Hero card and shows actions', (WidgetTester tester) async {
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

      // Open Type composer
      await tester.tap(find.text('Type'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Where is Shibuya?');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Hero Stage displays original and translated text + localized action buttons
      expect(find.text('Where is Shibuya?'), findsWidgets);
      expect(find.text('渋谷駅はどこですか？'), findsWidgets);
      expect(find.text('EN → JA'), findsOneWidget);
      expect(find.text('0.8x Slow'), findsOneWidget);
      expect(find.text('Expand'), findsOneWidget);
      expect(find.text('Listen'), findsOneWidget);
    });

    testWidgets('swapping direction and sending Japanese updates Hero stage and Recent Phrases', (WidgetTester tester) async {
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

      // First send an English sentence
      await tester.tap(find.text('Type'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Where is Shibuya?');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Swap direction pill to Japanese -> English
      await tester.tap(find.byIcon(Icons.sync_alt_rounded));
      await tester.pump();

      // Send Japanese text
      await tester.tap(find.text('Type'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'こんにちは');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Latest JA->EN translation takes Hero Stage; earlier EN->JA moves to Recent Phrases
      expect(find.text('こんにちは'), findsWidgets);
      expect(find.text('Hello! How are you?'), findsWidgets);
      expect(find.text('JA → EN'), findsOneWidget);
      expect(find.text('RECENT PHRASES'), findsOneWidget);
      expect(find.text('Where is Shibuya?'), findsOneWidget);
    });
  });
}

