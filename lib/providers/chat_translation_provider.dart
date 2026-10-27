
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/translation_service.dart';
import '../core/utils/app_logger.dart';
import '../features/translation/domain/models/chat_message.dart';

/// State of the translation chat.
class ChatTranslationState {
  final bool isLoading;
  final String? loadingMessage;
  final bool areModelsDownloaded;
  final List<ChatMessage> messages;
  final String? errorMessage;
  final TranslationLanguage activeInputLanguage;

  const ChatTranslationState({
    this.isLoading = false,
    this.loadingMessage,
    this.areModelsDownloaded = false,
    this.messages = const [],
    this.errorMessage,
    this.activeInputLanguage = TranslationLanguage.english,
  });

  ChatTranslationState copyWith({
    bool? isLoading,
    String? loadingMessage,
    bool? areModelsDownloaded,
    List<ChatMessage>? messages,
    String? errorMessage,
    TranslationLanguage? activeInputLanguage,
    bool clearLoadingMessage = false,
    bool clearError = false,
  }) {
    return ChatTranslationState(
      isLoading: isLoading ?? this.isLoading,
      loadingMessage: clearLoadingMessage ? null : (loadingMessage ?? this.loadingMessage),
      areModelsDownloaded: areModelsDownloaded ?? this.areModelsDownloaded,
      messages: messages ?? this.messages,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      activeInputLanguage: activeInputLanguage ?? this.activeInputLanguage,
    );
  }
}

/// Riverpod Notifier managing offline translation state and history.
class ChatTranslationNotifier extends Notifier<ChatTranslationState> {
  bool _disposed = false;

  @override
  ChatTranslationState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
    });

    // Warm up the bundled on-device engine in the background (no download involved).
    Future.microtask(() async {
      if (_disposed) return;
      try {
        await ref.read(translationServiceProvider).initializeModels();
      } catch (e) {
        AppLogger.warning('ChatTranslationNotifier', 'Engine warm-up notice: $e');
      }
    });
    return const ChatTranslationState(areModelsDownloaded: true);
  }

  /// Sends English text:
  /// 1. Immediately displays the text on the right side of the screen.
  /// 2. Runs translateToJapanese with OnDeviceTranslator.
  /// 3. Displays the translated Japanese text immediately below it.
  Future<void> sendEnglishText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isLoading) return;

    final messageId = DateTime.now().millisecondsSinceEpoch.toString();

    // Optimistically append the message so user's text displays immediately on the right side
    final initialMessage = ChatMessage(
      id: messageId,
      sourceLang: TranslationLanguage.english,
      targetLang: TranslationLanguage.japanese,
      originalText: trimmed,
      translatedText: 'Translating...',
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      isLoading: true,
      loadingMessage: 'Translating to Japanese (on-device)...',
      messages: [...state.messages, initialMessage],
      clearError: true,
    );

    try {
      final translationService = ref.read(translationServiceProvider);
      final translated = await translationService.translateToJapanese(trimmed);

      // Update message with final translation
      final updatedMessages = state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(translatedText: translated);
        }
        return m;
      }).toList();

      state = state.copyWith(
        isLoading: false,
        messages: updatedMessages,
        clearLoadingMessage: true,
      );
    } catch (e, st) {
      AppLogger.error('ChatTranslationNotifier', 'Translation to Japanese failed', e, st);
      final failedMessages = state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(translatedText: '[Translation failed: $e]');
        }
        return m;
      }).toList();

      state = state.copyWith(
        isLoading: false,
        messages: failedMessages,
        errorMessage: 'Translation failed: $e',
        clearLoadingMessage: true,
      );
    }
  }

  /// Sends Japanese text:
  /// 1. Immediately displays the text on the left side of the screen.
  /// 2. Runs translateToEnglish with OnDeviceTranslator.
  /// 3. Displays the translated English text immediately below it.
  Future<void> sendJapaneseText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isLoading) return;

    final messageId = DateTime.now().millisecondsSinceEpoch.toString();

    // Optimistically append the message so user's text displays immediately on the left side
    final initialMessage = ChatMessage(
      id: messageId,
      sourceLang: TranslationLanguage.japanese,
      targetLang: TranslationLanguage.english,
      originalText: trimmed,
      translatedText: 'Translating...',
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      isLoading: true,
      loadingMessage: 'Translating to English (on-device)...',
      messages: [...state.messages, initialMessage],
      clearError: true,
    );

    try {
      final translationService = ref.read(translationServiceProvider);
      final translated = await translationService.translateToEnglish(trimmed);

      // Update message with final translation
      final updatedMessages = state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(translatedText: translated);
        }
        return m;
      }).toList();

      state = state.copyWith(
        isLoading: false,
        messages: updatedMessages,
        clearLoadingMessage: true,
      );
    } catch (e, st) {
      AppLogger.error('ChatTranslationNotifier', 'Translation to English failed', e, st);
      final failedMessages = state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(translatedText: '[Translation failed: $e]');
        }
        return m;
      }).toList();

      state = state.copyWith(
        isLoading: false,
        messages: failedMessages,
        errorMessage: 'Translation failed: $e',
        clearLoadingMessage: true,
      );
    }
  }

  /// Sets the active input language for the toggle switch.
  void setInputLanguage(TranslationLanguage lang) {
    state = state.copyWith(activeInputLanguage: lang);
  }

  /// Toggles the active input language between English and Japanese.
  void toggleInputLanguage() {
    final next = state.activeInputLanguage == TranslationLanguage.english
        ? TranslationLanguage.japanese
        : TranslationLanguage.english;
    state = state.copyWith(activeInputLanguage: next);
  }

  /// Clears the chat history.
  void clearChat() {
    state = state.copyWith(
      messages: const [],
      clearError: true,
      clearLoadingMessage: true,
    );
  }
}

/// Riverpod provider for ChatTranslationState
final chatTranslationProvider =
    NotifierProvider<ChatTranslationNotifier, ChatTranslationState>(
  ChatTranslationNotifier.new,
);
