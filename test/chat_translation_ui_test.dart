import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'package:edge_translator/main.dart';
import 'package:edge_translator/features/translation/domain/models/chat_message.dart';
import 'package:edge_translator/providers/chat_translation_provider.dart';
import 'package:edge_translator/providers/service_providers.dart';
import 'widget_test.dart';

class MockModelManager implements OnDeviceTranslatorModelManager {
  bool isDownloaded = false;
  int downloadCalls = 0;

  @override
  Future<bool> isModelDownloaded(String model) async => isDownloaded;

  @override
  Future<bool> downloadModel(String model, {bool isWifiRequired = true}) async {
    downloadCalls++;
    isDownloaded = true;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestTranslationService extends TranslationService {
  final MockModelManager mockManager;

  TestTranslationService(this.mockManager) : super(modelManager: mockManager);

  @override
  Future<bool> initializeModels({bool isWifiRequired = true}) async {
    await mockManager.downloadModel('en');
    await mockManager.downloadModel('ja');
    return true;
  }

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
    return mockManager.isDownloaded;
  }
}

void main() {
  group('ChatTranslationProvider Unit Tests', () {
    test('downloadModels triggers model download and updates areModelsDownloaded', () async {
      final mockManager = MockModelManager();
      final testService = TestTranslationService(mockManager);

      final container = ProviderContainer(
        overrides: [
          translationServiceProvider.overrideWithValue(testService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(chatTranslationProvider.notifier);
      expect(container.read(chatTranslationProvider).areModelsDownloaded, false);

      await notifier.downloadModels();

      expect(container.read(chatTranslationProvider).areModelsDownloaded, true);
      expect(container.read(chatTranslationProvider).isLoading, false);
      expect(mockManager.downloadCalls, greaterThanOrEqualTo(1));
    });

    test('sendEnglishText creates message with translated Japanese text', () async {
      final mockManager = MockModelManager();
      final testService = TestTranslationService(mockManager);

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
      final mockManager = MockModelManager();
      final testService = TestTranslationService(mockManager);

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
    testWidgets('renders Download Models button, toggle switch, and dual send buttons', (WidgetTester tester) async {
      final mockManager = MockModelManager();
      final testService = TestTranslationService(mockManager);

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

      // Download Models button is present
      expect(find.text('Download Models'), findsWidgets);

      // Input TextField is present
      expect(find.byType(TextField), findsOneWidget);

      // Both "Send EN" and "Send JA" buttons are present
      expect(find.text('Send EN'), findsOneWidget);
      expect(find.text('Send JA'), findsOneWidget);

      // Toggle options are present
      expect(find.text('English'), findsOneWidget);
      expect(find.text('日本語'), findsOneWidget);
    });

    testWidgets('typing English and pressing Send EN displays English on top and Japanese below on right side', (WidgetTester tester) async {
      final mockManager = MockModelManager();
      final testService = TestTranslationService(mockManager);

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

      // Tap "Send EN" button
      await tester.tap(find.text('Send EN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify the user's text and translated result are displayed
      expect(find.text('Where is Shibuya?'), findsOneWidget);
      expect(find.text('渋谷駅はどこですか？'), findsOneWidget);

      // Verify message alignment is to the right
      final alignFinder = find.ancestor(
        of: find.text('Where is Shibuya?'),
        matching: find.byType(Align),
      );
      expect(alignFinder, findsWidgets);
      final alignWidget = tester.widget<Align>(alignFinder.first);
      expect(alignWidget.alignment, Alignment.centerRight);
    });

    testWidgets('typing Japanese and pressing Send JA displays Japanese on top and English below on left side', (WidgetTester tester) async {
      final mockManager = MockModelManager();
      final testService = TestTranslationService(mockManager);

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

      // Enter Japanese text into TextField
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'こんにちは');
      await tester.pump();

      // Tap "Send JA" button
      await tester.tap(find.text('Send JA'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify user's Japanese text and translated English result are displayed
      expect(find.text('こんにちは'), findsOneWidget);
      expect(find.text('Hello! How are you?'), findsOneWidget);

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
