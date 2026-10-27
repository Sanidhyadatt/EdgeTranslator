import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/chat_message.dart';

/// Dynamic status bar indicating the exact active stage in the translation pipeline.
class StatusBanner extends StatelessWidget {
  final PipelineStatus status;
  final TranslationLanguage? activeLanguage;

  const StatusBanner({
    super.key,
    required this.status,
    this.activeLanguage,
  });

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    IconData badgeIcon;
    String statusTitle;
    String statusDetail;

    switch (status) {
      case PipelineStatus.idle:
        badgeColor = AppTheme.successEmerald;
        badgeIcon = Icons.check_circle_outline_rounded;
        statusTitle = 'System Ready';
        statusDetail = 'Tap microphone or type text to translate';
        break;
      case PipelineStatus.recording:
        badgeColor = AppTheme.errorRose;
        badgeIcon = Icons.mic_rounded;
        final lang = activeLanguage?.name ?? 'Speech';
        statusTitle = 'Listening ($lang)';
        statusDetail = 'Tap microphone to finish speaking';
        break;
      case PipelineStatus.transcribing:
        badgeColor = AppTheme.primaryNeon;
        badgeIcon = Icons.graphic_eq_rounded;
        statusTitle = 'Transcribing Audio';
        statusDetail = 'Sherpa-ONNX Speech-to-Text inference...';
        break;
      case PipelineStatus.translating:
        badgeColor = AppTheme.primaryBlue;
        badgeIcon = Icons.translate_rounded;
        statusTitle = 'Translating Text';
        statusDetail = 'MarianMT Neural Machine Translation...';
        break;
      case PipelineStatus.synthesizing:
        badgeColor = AppTheme.warningAmber;
        badgeIcon = Icons.record_voice_over_rounded;
        statusTitle = 'Synthesizing Speech';
        statusDetail = 'Sherpa-ONNX VITS Text-to-Speech generation...';
        break;
      case PipelineStatus.playing:
        badgeColor = const Color(0xFF10B981);
        badgeIcon = Icons.volume_up_rounded;
        statusTitle = 'Playing Audio';
        statusDetail = 'Streaming voice translation playback';
        break;
      case PipelineStatus.error:
        badgeColor = AppTheme.errorRose;
        badgeIcon = Icons.error_outline_rounded;
        statusTitle = 'Pipeline Interrupted';
        statusDetail = 'An error occurred during processing';
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: badgeColor.withValues(alpha: status.isBusy ? 0.6 : 0.25),
          width: status.isBusy ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: badgeColor.withValues(alpha: 0.2),
            ),
            child: status.isProcessing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
                    ),
                  )
                : Icon(
                    badgeIcon,
                    color: badgeColor,
                    size: 18,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusDetail,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (status.isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.errorRose,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
