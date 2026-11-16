import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/language_detector.dart';
import '../../../../providers/chat_translation_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../providers/translation_pipeline_provider.dart';
import '../../domain/models/chat_message.dart';
import '../widgets/history_view.dart';
import '../widgets/pure_console_view.dart';
import '../widgets/pure_recording_view.dart';
import '../widgets/settings_view.dart';
import '../widgets/zen_bottom_nav.dart';
import '../widgets/zen_fullscreen_modal.dart';
import '../widgets/zen_header.dart';

/// Main IKHO screen hosting the Japanese Sumi & Washi wallpaper backdrop,
/// Pure Console, Pure Recording, History, and Settings views.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tabIndex = 0;
  String? _selectedMessageId;

  TranslationLanguage _resolveTextSourceLanguage(
    String text, {
    required TranslationLanguage fallback,
    required bool autoDetect,
  }) {
    if (!autoDetect) return fallback;
    if (isJapaneseText(text)) return TranslationLanguage.japanese;
    if (RegExp(r'[a-zA-Z]').hasMatch(text)) return TranslationLanguage.english;
    return fallback;
  }

  Future<void> _confirmAndClearHistory(
    AppStrings strings,
    TranslationPipelineNotifier pipelineNotifier,
    ChatTranslationNotifier chatNotifier,
  ) async {
    final confirmed = await showClearHistoryDialog(context, strings: strings);
    if (!confirmed) return;
    pipelineNotifier.clearHistory();
    chatNotifier.clearChat();
    setState(() => _selectedMessageId = null);
  }

  Future<void> _startMicForLanguage(TranslationLanguage language) async {
    final pipelineNotifier = ref.read(translationPipelineProvider.notifier);
    final chatNotifier = ref.read(chatTranslationProvider.notifier);
    pipelineNotifier.setLanguage(language);
    chatNotifier.setInputLanguage(language);
    setState(() {
      _tabIndex = 0;
      _selectedMessageId = null;
    });
    await pipelineNotifier.startVoiceListening();
  }

  @override
  Widget build(BuildContext context) {
    final pipelineState = ref.watch(translationPipelineProvider);
    final pipelineNotifier = ref.read(translationPipelineProvider.notifier);
    final chatState = ref.watch(chatTranslationProvider);
    final chatNotifier = ref.read(chatTranslationProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final strings = AppStrings.of(settings.uiLanguage);

    ref.listen<List<ChatMessage>>(
      translationPipelineProvider.select((s) => s.messages),
      (prev, next) {
        if ((prev?.length ?? 0) < next.length) {
          setState(() => _selectedMessageId = null);
        }
      },
    );

    final allMessages = [
      ...chatState.messages,
      ...pipelineState.messages,
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final selectedMessage = _selectedMessageId == null
        ? null
        : allMessages.where((m) => m.id == _selectedMessageId).firstOrNull;

    final isRecordingScreen = pipelineState.status == PipelineStatus.recording ||
        pipelineState.status == PipelineStatus.transcribing;

    Widget bodyContent;
    if (isRecordingScreen && _tabIndex == 0) {
      bodyContent = PureRecordingView(
        strings: strings,
        status: pipelineState.status,
        activeLanguage: pipelineState.activeLanguage,
        recordingSeconds: pipelineState.recordingSeconds,
        interimTranscript: pipelineState.interimTranscript,
        onDone: () => pipelineNotifier.stopVoiceListening(),
        onCancel: () => pipelineNotifier.cancelVoiceListening(),
      );
    } else if (_tabIndex == 1) {
      bodyContent = HistoryView(
        strings: strings,
        messages: allMessages,
        onOpenInTranslate: (msg) {
          setState(() {
            _selectedMessageId = msg.id;
            _tabIndex = 0;
          });
        },
        onPlayTranslation: (id) => pipelineNotifier.playMessageAudio(id),
        onOpenFullscreen: (msg) =>
            showZenFullscreenModal(context, initialMessage: msg),
        onClearAll: () =>
            _confirmAndClearHistory(strings, pipelineNotifier, chatNotifier),
      );
    } else if (_tabIndex == 2) {
      bodyContent = SettingsView(
        strings: strings,
        settings: settings,
        activeLanguage: pipelineState.activeLanguage,
        isSpeaking: pipelineState.status == PipelineStatus.playing,
        historyCount: allMessages.length,
        onUiLanguageChanged: (lang) => settingsNotifier.setUiLanguage(lang),
        onSpeechRateChanged: (rate) => settingsNotifier.setSpeechRate(rate),
        onToggleAutoDetect: () => settingsNotifier.setAutoDetectTypedLanguage(
          !settings.autoDetectTypedLanguage,
        ),
        onDefaultLanguageChanged: (lang) {
          settingsNotifier.setDefaultLanguage(lang);
          pipelineNotifier.setLanguage(lang);
          chatNotifier.setInputLanguage(lang);
        },
        onTestEnglishSpeech: () => pipelineNotifier.speakPreview(
          'Hello, this is a speech speed preview.',
          language: TranslationLanguage.english,
        ),
        onTestJapaneseSpeech: () => pipelineNotifier.speakPreview(
          'こんにちは、音声速度のテストです。',
          language: TranslationLanguage.japanese,
        ),
        onClearHistory: () =>
            _confirmAndClearHistory(strings, pipelineNotifier, chatNotifier),
      );
    } else {
      bodyContent = PureConsoleView(
        strings: strings,
        activeLanguage: pipelineState.activeLanguage,
        onLanguageChanged: (lang) {
          pipelineNotifier.setLanguage(lang);
          chatNotifier.setInputLanguage(lang);
        },
        messages: allMessages,
        selectedMessage: selectedMessage,
        onSelectMessage: (msg) => setState(() => _selectedMessageId = msg.id),
        isBusy: pipelineState.status.isProcessing ||
            pipelineState.status.isRecording,
        isSlowMode: settings.isSlowMode,
        errorMessage: pipelineState.errorMessage,
        onDismissError: () => pipelineNotifier.dismissError(),
        onSendText: (text) {
          setState(() => _selectedMessageId = null);
          final sourceLang = _resolveTextSourceLanguage(
            text,
            fallback: pipelineState.activeLanguage,
            autoDetect: settings.autoDetectTypedLanguage,
          );
          pipelineNotifier.processText(
            text,
            explicitSourceLang: sourceLang,
          );
        },
        onStartMic: _startMicForLanguage,
        onPlayTranslation: (id) => pipelineNotifier.playMessageAudio(id),
        onPlayOriginal: (id) =>
            pipelineNotifier.playMessageAudio(id, speakOriginal: true),
        onOpenFullscreen: (msg) =>
            showZenFullscreenModal(context, initialMessage: msg),
        onToggleSlowMode: () => settingsNotifier.toggleSlowMode(),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.washi,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.85,
                child: Image.asset(
                  AppConstants.washiWallpaperAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomCenter,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Column(
              children: [
                ZenHeader(
                  strings: strings,
                  showDirectionPill: isRecordingScreen && _tabIndex == 0,
                  activeLanguage: pipelineState.activeLanguage,
                ),
                Expanded(child: bodyContent),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: ZenBottomNav(
        strings: strings,
        currentIndex: _tabIndex,
        onTap: (idx) {
          if (isRecordingScreen && idx != 0) {
            return;
          }
          setState(() => _tabIndex = idx);
        },
      ),
    );
  }
}
