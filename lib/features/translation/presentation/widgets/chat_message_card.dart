import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/chat_message.dart';

/// Card presenting a translated conversation item in the chat log.
///
/// English input messages align to the RIGHT side of the screen.
/// Japanese input messages align to the LEFT side of the screen.
/// Original text is shown on top, with the translated text immediately below it.
class ChatMessageCard extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onPlay;

  const ChatMessageCard({
    super.key,
    required this.message,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final isEnglishSource = message.sourceLang == TranslationLanguage.english;
    final alignment = isEnglishSource ? Alignment.centerRight : Alignment.centerLeft;

    final primaryAccent = isEnglishSource ? AppTheme.primaryNeon : const Color(0xFFFF5277);
    final bubbleGradient = isEnglishSource
        ? LinearGradient(
            colors: [
              AppTheme.surfaceElevated,
              AppTheme.primaryBlue.withValues(alpha: 0.15),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              AppTheme.surfaceElevated,
              const Color(0xFFFF5277).withValues(alpha: 0.12),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          );

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: isEnglishSource ? const Radius.circular(20) : const Radius.circular(4),
      bottomRight: isEnglishSource ? const Radius.circular(4) : const Radius.circular(20),
    );

    return Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: math.min(MediaQuery.of(context).size.width * 0.85, 640),
        ),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          gradient: bubbleGradient,
          borderRadius: borderRadius,
          border: Border.all(
            color: message.isPlaying ? primaryAccent : primaryAccent.withValues(alpha: 0.35),
            width: message.isPlaying ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: message.isPlaying
                  ? primaryAccent.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.25),
              blurRadius: message.isPlaying ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: isEnglishSource ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Header Row: Source -> Target Pill & Action Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment:
                    isEnglishSource ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primaryAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(message.sourceLang.flag, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Text(
                          message.sourceLang.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: primaryAccent,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4.0),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        Text(message.targetLang.flag, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Text(
                          message.targetLang.name,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Copy Button
                  Tooltip(
                    message: 'Copy translation',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: message.translatedText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Translation copied to clipboard'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Icon(Icons.copy_rounded, size: 14, color: AppTheme.textMuted),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // 1. Original User Input Text (Displayed on top)
              Text(
                message.originalText,
                textAlign: isEnglishSource ? TextAlign.right : TextAlign.left,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.textSecondary,
                  height: 1.35,
                ),
              ),

              const SizedBox(height: 10),
              Container(
                height: 1,
                color: AppTheme.cardBorder.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 10),

              // 2. Translated Result Text (Displayed immediately below it)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (message.translatedText == 'Translating...')
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(primaryAccent),
                        ),
                      ),
                    ),
                  Flexible(
                    child: Text(
                      message.translatedText,
                      textAlign: isEnglishSource ? TextAlign.right : TextAlign.left,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                        height: 1.4,
                        letterSpacing:
                            message.targetLang == TranslationLanguage.japanese ? 0.3 : 0,
                      ),
                    ),
                  ),
                ],
              ),

              if (onPlay != null &&
                  message.translatedText.trim().isNotEmpty &&
                  message.translatedText != 'Translating...') ...[
                const SizedBox(height: 10),
                Align(
                  alignment: isEnglishSource ? Alignment.centerRight : Alignment.centerLeft,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onPlay,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: message.isPlaying
                              ? primaryAccent.withValues(alpha: 0.25)
                              : primaryAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: message.isPlaying
                                ? primaryAccent
                                : primaryAccent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              message.isPlaying
                                  ? Icons.stop_rounded
                                  : Icons.volume_up_rounded,
                              size: 16,
                              color: primaryAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              message.isPlaying ? 'Stop' : 'Speak',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: primaryAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
