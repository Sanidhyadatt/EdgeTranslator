import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/chat_message.dart';

/// Single interactive toggle switch activating hands-free continuous listening with Silero VAD.
class ContinuousListeningToggle extends StatefulWidget {
  final bool isListening;
  final PipelineStatus status;
  final VoidCallback onToggle;

  const ContinuousListeningToggle({
    super.key,
    required this.isListening,
    required this.status,
    required this.onToggle,
  });

  @override
  State<ContinuousListeningToggle> createState() => _ContinuousListeningToggleState();
}

class _ContinuousListeningToggleState extends State<ContinuousListeningToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseScale = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isListening && widget.status == PipelineStatus.recording) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ContinuousListeningToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && widget.status == PipelineStatus.recording) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isListening = widget.isListening;
    final isSpeaking = widget.status == PipelineStatus.recording;
    final isProcessing = widget.status.isProcessing;

    Color primaryColor;
    Color secondaryColor;
    String titleText;
    String subtitleText;
    IconData icon;

    if (!isListening) {
      primaryColor = AppTheme.primaryNeon;
      secondaryColor = AppTheme.primaryBlue;
      titleText = 'Tap to Start Listening';
      subtitleText = 'Hands-free continuous translation • Silero VAD';
      icon = Icons.mic_none_rounded;
    } else if (isSpeaking) {
      primaryColor = AppTheme.errorRose;
      secondaryColor = const Color(0xFFDC2626);
      titleText = 'Hearing Speech...';
      subtitleText = '1.5s silence triggers auto-translation';
      icon = Icons.mic;
    } else if (isProcessing) {
      primaryColor = AppTheme.warningAmber;
      secondaryColor = Colors.deepOrange;
      titleText = widget.status.label;
      subtitleText = 'Translating utterance...';
      icon = Icons.auto_awesome_rounded;
    } else {
      primaryColor = AppTheme.successEmerald;
      secondaryColor = const Color(0xFF059669);
      titleText = 'Continuous Listening Active';
      subtitleText = 'Speak naturally • Translates after 1.5s silence';
      icon = Icons.graphic_eq_rounded;
    }

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isListening ? primaryColor : AppTheme.cardBorder,
          width: isListening ? 2.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isListening
                ? primaryColor.withValues(alpha: 0.35)
                : Colors.black.withValues(alpha: 0.3),
            blurRadius: isListening ? 20 : 10,
            spreadRadius: isListening ? 1.5 : 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left Icon with animated glowing badge
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isListening
                  ? primaryColor.withValues(alpha: 0.25)
                  : AppTheme.surface,
              border: Border.all(
                color: isListening ? primaryColor : AppTheme.cardBorder,
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isListening ? primaryColor : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 14),

          // Central Label and Subtitle
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isListening) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        titleText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isListening ? primaryColor : AppTheme.textPrimary,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitleText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isListening
                        ? AppTheme.textSecondary
                        : AppTheme.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Switch Toggle Indicator (ON / OFF)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 48,
            height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: isListening
                  ? LinearGradient(colors: [primaryColor, secondaryColor])
                  : null,
              color: isListening ? null : AppTheme.surface,
              border: Border.all(
                color: isListening ? primaryColor : AppTheme.cardBorder,
              ),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: isListening ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isListening ? Colors.white : AppTheme.textMuted,
                  boxShadow: [
                    if (isListening)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (isListening && isSpeaking) {
      content = ScaleTransition(
        scale: _pulseScale,
        child: content,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: widget.onToggle,
        child: content,
      ),
    );
  }
}
