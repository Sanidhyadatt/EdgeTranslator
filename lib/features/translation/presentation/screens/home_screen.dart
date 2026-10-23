import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/chat_translation_provider.dart';
import '../../../../providers/translation_pipeline_provider.dart';
import '../../domain/models/chat_message.dart';
import '../widgets/chat_log_view.dart';
import '../widgets/continuous_listening_toggle.dart';
import '../widgets/hold_to_talk_button.dart';
import '../widgets/manual_text_input_bar.dart';
import '../widgets/status_banner.dart';

/// Main screen showcasing ML Kit offline chat translation, continuous VAD,
/// language toggle, dual send buttons, and offline model management.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipelineState = ref.watch(translationPipelineProvider);
    final pipelineNotifier = ref.read(translationPipelineProvider.notifier);

    final chatState = ref.watch(chatTranslationProvider);
    final chatNotifier = ref.read(chatTranslationProvider.notifier);

    // Merge messages from ML Kit Chat and VAD Voice pipeline for a unified conversation history
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
          // "Download Models" Button or Ready Badge
          _buildModelStatusAction(context, chatState, chatNotifier),
          const SizedBox(width: 8),
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
            // Prominent Model Download Banner if models are not yet downloaded
            if (!chatState.areModelsDownloaded)
              _buildDownloadBanner(context, chatState, chatNotifier),

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
                        chatState.loadingMessage ?? 'Processing with Google ML Kit...',
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

            // Bottom Controls Area
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // If continuous listening is active, show the quick control bar
                  if (pipelineState.isContinuousListening) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.errorRose,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              icon: const Icon(Icons.stop_circle_outlined, size: 20),
                              label: const Text(
                                'Stop Hearing',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              onPressed: () => pipelineNotifier.stopHearing(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.successEmerald,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                              label: const Text(
                                'Done Speaking',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              onPressed: () => pipelineNotifier.doneSpeakingNow(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Continuous Hands-Free Listening Toggle Switch (Silero VAD)
                  ContinuousListeningToggle(
                    isListening: pipelineState.isContinuousListening,
                    status: pipelineState.status,
                    onToggle: () => pipelineNotifier.toggleContinuousListening(),
                  ),
                  const SizedBox(height: 10),

                  // Push-to-Talk / Hold-to-Talk buttons for direct manual speech
                  if (!pipelineState.isContinuousListening) ...[
                    Row(
                      children: [
                        Expanded(
                          child: HoldToTalkButton(
                            language: TranslationLanguage.english,
                            isRecording: pipelineState.status == PipelineStatus.recording &&
                                pipelineState.activeLanguage == TranslationLanguage.english,
                            isProcessing: pipelineState.status.isProcessing,
                            isOtherActive: pipelineState.status == PipelineStatus.recording &&
                                pipelineState.activeLanguage != TranslationLanguage.english,
                            onHoldStart: () => pipelineNotifier.startPushToTalk(TranslationLanguage.english),
                            onHoldEnd: () => pipelineNotifier.stopPushToTalk(TranslationLanguage.english),
                            onHoldCancel: () => pipelineNotifier.cancelPushToTalk(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: HoldToTalkButton(
                            language: TranslationLanguage.japanese,
                            isRecording: pipelineState.status == PipelineStatus.recording &&
                                pipelineState.activeLanguage == TranslationLanguage.japanese,
                            isProcessing: pipelineState.status.isProcessing,
                            isOtherActive: pipelineState.status == PipelineStatus.recording &&
                                pipelineState.activeLanguage != TranslationLanguage.japanese,
                            onHoldStart: () => pipelineNotifier.startPushToTalk(TranslationLanguage.japanese),
                            onHoldEnd: () => pipelineNotifier.stopPushToTalk(TranslationLanguage.japanese),
                            onHoldCancel: () => pipelineNotifier.cancelPushToTalk(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Manual Text Input Bar (translates with Google ML Kit & reads aloud with TTS)
                  ManualTextInputBar(
                    isBusy: pipelineState.status.isBusy || chatState.isLoading,
                    activeLanguage: chatState.activeInputLanguage,
                    onLanguageChanged: (lang) => chatNotifier.setInputLanguage(lang),
                    onSendEnglish: (text) => pipelineNotifier.processText(
                      text,
                      explicitSourceLang: TranslationLanguage.english,
                    ),
                    onSendJapanese: (text) => pipelineNotifier.processText(
                      text,
                      explicitSourceLang: TranslationLanguage.japanese,
                    ),
                    onSubmit: (text) {
                      pipelineNotifier.processText(
                        text,
                        explicitSourceLang: chatState.activeInputLanguage,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelStatusAction(
    BuildContext context,
    ChatTranslationState state,
    ChatTranslationNotifier notifier,
  ) {
    if (state.isLoading && state.loadingMessage?.contains('model') == true) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryNeon),
            ),
            SizedBox(width: 6),
            Text(
              'Downloading...',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryNeon,
              ),
            ),
          ],
        ),
      );
    }

    if (state.areModelsDownloaded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 14, color: AppTheme.successEmerald),
            SizedBox(width: 4),
            Text(
              'Models Ready',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // "Download Models" Button
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primaryNeon,
        foregroundColor: const Color(0xFF0B0F17),
        elevation: 0,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: const Icon(Icons.download_rounded, size: 14),
      label: const Text(
        'Download Models',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
      onPressed: () => notifier.downloadModels(),
    );
  }

  Widget _buildDownloadBanner(
    BuildContext context,
    ChatTranslationState state,
    ChatTranslationNotifier notifier,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryNeon.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNeon.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryNeon.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.cloud_download_rounded,
              color: AppTheme.primaryNeon,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Offline ML Kit Models Required',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Download EN & JA offline model packs to enable real-time translation.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryNeon,
              foregroundColor: const Color(0xFF0B0F17),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              elevation: 0,
            ),
            icon: const Icon(Icons.download_rounded, size: 14),
            label: const Text(
              'Download Models',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            onPressed: state.isLoading ? null : () => notifier.downloadModels(),
          ),
        ],
      ),
    );
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
