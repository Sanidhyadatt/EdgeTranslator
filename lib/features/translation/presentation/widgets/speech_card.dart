import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';

/// Card component presenting either source speech or translated output.
class SpeechCard extends StatelessWidget {
  final String title;
  final String languageBadge;
  final String content;
  final String placeholder;
  final VoidCallback? onPlay;
  final bool isTarget;

  const SpeechCard({
    super.key,
    required this.title,
    required this.languageBadge,
    required this.content,
    required this.placeholder,
    this.onPlay,
    this.isTarget = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent = content.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isTarget && hasContent ? AppTheme.primaryNeon.withValues(alpha: 0.4) : AppTheme.cardBorder,
          width: isTarget && hasContent ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isTarget
                          ? AppTheme.primaryNeon.withValues(alpha: 0.15)
                          : AppTheme.primaryBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      languageBadge,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isTarget ? AppTheme.primaryNeon : AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              if (hasContent)
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: 'Copy text',
                      color: AppTheme.textMuted,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied "$title" to clipboard'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                    if (onPlay != null)
                      IconButton(
                        icon: const Icon(Icons.volume_up_rounded, size: 20),
                        tooltip: 'Play speech',
                        color: AppTheme.primaryNeon,
                        onPressed: onPlay,
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            hasContent ? content : placeholder,
            style: TextStyle(
              fontSize: isTarget ? 22 : 18,
              fontWeight: isTarget ? FontWeight.w600 : FontWeight.w400,
              color: hasContent ? AppTheme.textPrimary : AppTheme.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
