import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/chat_message.dart';

/// Large touch-responsive Hold-to-Talk button for English or Japanese translation.
class HoldToTalkButton extends StatefulWidget {
  final TranslationLanguage language;
  final bool isRecording;
  final bool isProcessing;
  final bool isOtherActive;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onHoldCancel;

  const HoldToTalkButton({
    super.key,
    required this.language,
    required this.isRecording,
    required this.isProcessing,
    required this.isOtherActive,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onHoldCancel,
  });

  @override
  State<HoldToTalkButton> createState() => _HoldToTalkButtonState();
}

class _HoldToTalkButtonState extends State<HoldToTalkButton> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = widget.language == TranslationLanguage.english;
    final isEnabled = !widget.isOtherActive;

    // Default accent colors
    final primaryColor = isEn ? AppTheme.primaryNeon : const Color(0xFFFF5277);
    final secondaryColor = isEn ? AppTheme.primaryBlue : const Color(0xFFE11D48);

    // Recording turns vibrant Red / Crimson
    final recordingGradient = [
      AppTheme.errorRose,
      const Color(0xFFDC2626),
    ];

    final normalGradient = [
      AppTheme.surfaceElevated,
      AppTheme.surface,
    ];

    final String buttonLabel = widget.isRecording
        ? 'Recording...'
        : (isEn ? 'Hold for English' : 'Hold for Japanese');

    Widget buttonContent = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: widget.isRecording ? recordingGradient : normalGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: widget.isRecording ? Colors.white : primaryColor.withValues(alpha: 0.6),
          width: widget.isRecording ? 2.5 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.isRecording
                ? AppTheme.errorRose.withValues(alpha: 0.6)
                : secondaryColor.withValues(alpha: 0.25),
            blurRadius: widget.isRecording ? 24 : 12,
            spreadRadius: widget.isRecording ? 2 : 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.isProcessing) ...[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  widget.isRecording ? Colors.white : primaryColor,
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isRecording
                    ? Colors.white.withValues(alpha: 0.25)
                    : primaryColor.withValues(alpha: 0.15),
              ),
              child: Icon(
                widget.isRecording ? Icons.mic : Icons.mic_none_rounded,
                color: widget.isRecording ? Colors.white : primaryColor,
                size: 20,
              ),
            ),
          ],
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.language.flag,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        buttonLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: widget.isRecording ? Colors.white : AppTheme.textPrimary,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.isRecording ? 'Release to translate' : 'Press & hold to speak',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: widget.isRecording
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.isRecording) {
      buttonContent = ScaleTransition(
        scale: _pulseAnimation,
        child: buttonContent,
      );
    }

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: isEnabled ? (_) => widget.onHoldStart() : null,
        onTapUp: isEnabled ? (_) => widget.onHoldEnd() : null,
        onTapCancel: isEnabled ? () => widget.onHoldCancel() : null,
        child: buttonContent,
      ),
    );
  }
}
