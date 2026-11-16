import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/language_detector.dart';
import '../../../../providers/chat_translation_provider.dart';
import '../../../../providers/translation_pipeline_provider.dart';
import '../../domain/models/chat_message.dart';
import '../widgets/chat_log_view.dart';
import '../widgets/status_banner.dart';
import '../widgets/unified_input_bar.dart';

/// Main screen showcasing on-device offline chat translation, continuous VAD,
/// language toggle, dual send buttons, and offline model management.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipelineState = ref.watch(translationPipelineProvider);
    final pipelineNotifier = ref.read(translationPipelineProvider.notifier);

    final chatState = ref.watch(chatTranslationProvider);
    final chatNotifier = ref.read(chatTranslationProvider.notifier);

    // Merge messages from Chat and VAD Voice pipeline for a unified conversation history
    final allMessages = [
      ...chatState.messages,
      ...pipelineState.messages,
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppTheme.primaryNeon, AppTheme.primaryBlue],
                ),
              ),
              child: const Icon(Icons.bolt, color: Color(0xFF0B0F17), size: 16),
            ),
            const SizedBox(width: 8),
            Text(AppConstants.appName),
          ],
        ),
        actions: [
          // 100% Offline Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.successEmerald.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.successEmerald.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.successEmerald,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '100% Offline',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.successEmerald,
                  ),
                ),
              ],
            ),
          ),
          // Clear History Action
          if (allMessages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, size: 20),
              tooltip: 'Clear history',
              color: AppTheme.textMuted,
              onPressed: () => _confirmClearHistory(context, pipelineNotifier, chatNotifier),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Active Loading Progress Indicator (e.g. downloading models or translating)
            if (chatState.isLoading)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppTheme.surfaceElevated,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryNeon),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        chatState.loadingMessage ?? 'Translating on-device...',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryNeon,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Live Status Banner
            StatusBanner(
              status: pipelineState.status,
              activeLanguage: pipelineState.activeLanguage,
              recordingSeconds: pipelineState.recordingSeconds,
              errorMessage: pipelineState.errorMessage,
            ),

            // Scrollable Conversation History Area (ListView with Right/Left aligned bubbles)
            Expanded(
              child: ChatLogView(
                messages: allMessages,
                status: pipelineState.status,
                activeLanguage: pipelineState.activeLanguage,
                interimTranscript: pipelineState.interimTranscript,
                interimTranslation: pipelineState.interimTranslation,
                onPlayMessage: (id) => pipelineNotifier.playMessageAudio(id),
              ),
            ),

            // Bottom Controls Area: Minimal, simplified Unified Translation Input Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: AppTheme.background,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: UnifiedInputBar(
                activeLanguage: pipelineState.activeLanguage,
                onLanguageChanged: (lang) {
                  pipelineNotifier.setLanguage(lang);
                  chatNotifier.setInputLanguage(lang);
                },
                onSend: (text) {
                  final sourceLang = _resolveTextSourceLanguage(
                    text,
                    fallback: pipelineState.activeLanguage,
                  );
                  pipelineNotifier.processText(
                    text,
                    explicitSourceLang: sourceLang,
                  );
                },
                onMicTap: () => pipelineNotifier.toggleVoiceListening(),
                onCancelRecording: () => pipelineNotifier.cancelVoiceListening(),
                isRecording: pipelineState.status == PipelineStatus.recording,
                isBusy: pipelineState.status.isProcessing || pipelineState.status.isRecording,
                recordingSeconds: pipelineState.recordingSeconds,
                interimText: pipelineState.interimTranscript,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TranslationLanguage _resolveTextSourceLanguage(
    String text, {
    required TranslationLanguage fallback,
  }) {
    if (isJapaneseText(text)) return TranslationLanguage.japanese;
    if (RegExp(r'[a-zA-Z]').hasMatch(text)) return TranslationLanguage.english;
    return fallback;
  }

  void _confirmClearHistory(
    BuildContext context,
    TranslationPipelineNotifier pipelineNotifier,
    ChatTranslationNotifier chatNotifier,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Text(
          'Clear Conversation?',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will clear all translated messages from your current session.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRose,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              pipelineNotifier.clearHistory();
              chatNotifier.clearChat();
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
