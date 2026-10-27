import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/chat_message.dart';

/// Clean, unified translation input bar featuring:
/// 1. A unified toggle button to switch from English to Japanese and vice-versa
/// 2. A single input TextField
/// 3. Just a single Send button and a single Mic / Speak button
class UnifiedInputBar extends StatefulWidget {
  final TranslationLanguage activeLanguage;
  final ValueChanged<TranslationLanguage> onLanguageChanged;
  final ValueChanged<String> onSend;
  final VoidCallback onMicTap;
  final bool isRecording;
  final bool isBusy;
  final String? interimText;

  const UnifiedInputBar({
    super.key,
    required this.activeLanguage,
    required this.onLanguageChanged,
    required this.onSend,
    required this.onMicTap,
    this.isRecording = false,
    this.isBusy = false,
    this.interimText,
  });

  @override
  State<UnifiedInputBar> createState() => _UnifiedInputBarState();
}

class _UnifiedInputBarState extends State<UnifiedInputBar> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _onTextChanged() {
    final hasContent = _textController.text.trim().isNotEmpty;
    if (hasContent != _hasText) {
      setState(() {
        _hasText = hasContent;
      });
    }
  }

  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isEmpty || widget.isBusy) return;

    widget.onSend(text);
    _textController.clear();
    _focusNode.unfocus();
  }

  void _toggleLanguage() {
    final next = widget.activeLanguage == TranslationLanguage.english
        ? TranslationLanguage.japanese
        : TranslationLanguage.english;
    widget.onLanguageChanged(next);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = widget.activeLanguage == TranslationLanguage.english;
    final canSend = _hasText && !widget.isBusy && !widget.isRecording;

    final inputHint = widget.isRecording
        ? (widget.interimText?.isNotEmpty == true
            ? widget.interimText!
            : (isEn ? 'Listening to English...' : '日本語を聞き取り中...'))
        : (isEn ? 'Type English to translate...' : '日本語を入力してください...');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Unified Switch Button (English ⇄ 日本語)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Unified Switch Pill
              GestureDetector(
                onTap: widget.isBusy ? null : _toggleLanguage,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isEn ? AppTheme.primaryNeon.withValues(alpha: 0.5) : const Color(0xFFFF5277).withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // English Side
                      Text(
                        '🇺🇸 English',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isEn ? FontWeight.bold : FontWeight.w500,
                          color: isEn ? AppTheme.primaryNeon : AppTheme.textMuted,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.swap_horiz_rounded,
                          size: 18,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      // Japanese Side
                      Text(
                        '🇯🇵 日本語',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: !isEn ? FontWeight.bold : FontWeight.w500,
                          color: !isEn ? const Color(0xFFFF5277) : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Direction Hint Label
              Text(
                isEn ? 'English ➔ Japanese' : 'Japanese ➔ English',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isEn ? AppTheme.primaryNeon : const Color(0xFFFF5277),
                ),
              ),
            ],
          ),
        ),

        // 2. Unified Input & Action Row
        Row(
          children: [
            // Mic / Speak Button (Tapping starts recording; tapping while recording STOPS it)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: (widget.isBusy && !widget.isRecording) ? null : widget.onMicTap,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: widget.isRecording ? _pulseAnimation.value : 1.0,
                    child: child,
                  );
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isRecording
                        ? AppTheme.errorRose
                        : (isEn ? AppTheme.primaryNeon.withValues(alpha: 0.15) : const Color(0xFFFF5277).withValues(alpha: 0.15)),
                    border: Border.all(
                      color: widget.isRecording
                          ? Colors.white
                          : (isEn ? AppTheme.primaryNeon : const Color(0xFFFF5277)),
                      width: widget.isRecording ? 2.0 : 1.2,
                    ),
                    boxShadow: [
                      if (widget.isRecording)
                        BoxShadow(
                          color: AppTheme.errorRose.withValues(alpha: 0.7),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                  child: Icon(
                    widget.isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: widget.isRecording
                        ? Colors.white
                        : (isEn ? AppTheme.primaryNeon : const Color(0xFFFF5277)),
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Text Input Box
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _focusNode.hasFocus
                        ? (isEn ? AppTheme.primaryNeon : const Color(0xFFFF5277))
                        : AppTheme.cardBorder,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        enabled: !widget.isBusy && !widget.isRecording,
                        textInputAction: TextInputAction.send,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: inputHint,
                          hintStyle: TextStyle(
                            color: widget.isRecording
                                ? (isEn ? AppTheme.primaryNeon : const Color(0xFFFF5277))
                                : AppTheme.textMuted,
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _handleSend(),
                      ),
                    ),
                    if (_hasText && !widget.isBusy && !widget.isRecording)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        color: AppTheme.textMuted,
                        onPressed: () => _textController.clear(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Just a single Send Button
            GestureDetector(
              onTap: canSend ? _handleSend : null,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: canSend
                      ? LinearGradient(
                          colors: isEn
                              ? [AppTheme.primaryNeon, AppTheme.primaryBlue]
                              : [const Color(0xFFFF5277), const Color(0xFFE11D48)],
                        )
                      : null,
                  color: canSend ? null : AppTheme.surfaceElevated,
                  border: Border.all(
                    color: canSend ? Colors.transparent : AppTheme.cardBorder,
                  ),
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: canSend ? const Color(0xFF0B0F17) : AppTheme.textMuted,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
