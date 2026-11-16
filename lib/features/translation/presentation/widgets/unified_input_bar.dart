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
  final VoidCallback? onCancelRecording;
  final bool isRecording;
  final bool isBusy;
  final int recordingSeconds;
  final String? interimText;

  const UnifiedInputBar({
    super.key,
    required this.activeLanguage,
    required this.onLanguageChanged,
    required this.onSend,
    required this.onMicTap,
    this.onCancelRecording,
    this.isRecording = false,
    this.isBusy = false,
    this.recordingSeconds = 0,
    this.interimText,
  });

  @override
  State<UnifiedInputBar> createState() => _UnifiedInputBarState();
}

class _UnifiedInputBarState extends State<UnifiedInputBar> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;
  bool _hasFocus = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus != _hasFocus) {
      setState(() {
        _hasFocus = _focusNode.hasFocus;
      });
    }
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

  String _formatDuration(int totalSeconds) {
    final mins = totalSeconds ~/ 60;
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = widget.activeLanguage == TranslationLanguage.english;
    final canSend = _hasText && !widget.isBusy && !widget.isRecording;
    final inputHint = isEn ? 'Type English or Japanese to translate...' : '日本語・英語を入力してください...';

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
              Tooltip(
                message: 'Switch input language direction',
                child: MouseRegion(
                  cursor: widget.isBusy ? SystemMouseCursors.basic : SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.isBusy ? null : _toggleLanguage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isEn
                              ? AppTheme.primaryNeon.withValues(alpha: 0.5)
                              : const Color(0xFFFF5277).withValues(alpha: 0.5),
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

        // 2. Active Listening Bar OR Standard Input Row
        if (widget.isRecording)
          _buildListeningBar()
        else
          _buildStandardInputRow(isEn, canSend, inputHint),
      ],
    );
  }

  Widget _buildListeningBar() {
    final timerLabel = _formatDuration(widget.recordingSeconds);
    final interim = widget.interimText?.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.errorRose.withValues(alpha: 0.7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.errorRose.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (widget.onCancelRecording != null) ...[
            Tooltip(
              message: 'Cancel recording',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: widget.onCancelRecording,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.surface,
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],

          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Transform.scale(
              scale: _pulseAnimation.value,
              child: child,
            ),
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.errorRose,
              ),
            ),
          ),
          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Listening... $timerLabel',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  (interim != null && interim.isNotEmpty)
                      ? interim
                      : 'Speak freely — press Stop to translate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          Tooltip(
            message: 'Stop listening & translate',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onMicTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.errorRose,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.errorRose.withValues(alpha: 0.45),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Stop',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardInputRow(bool isEn, bool canSend, String inputHint) {
    final accentColor = isEn ? AppTheme.primaryNeon : const Color(0xFFFF5277);

    return Row(
      children: [
        // Mic / Speak Button
        Tooltip(
          message: 'Tap to start speaking (listens until Stop)',
          child: MouseRegion(
            cursor: widget.isBusy ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.isBusy ? null : widget.onMicTap,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withValues(alpha: 0.15),
                  border: Border.all(color: accentColor, width: 1.2),
                ),
                child: Icon(
                  Icons.mic_rounded,
                  color: accentColor,
                  size: 22,
                ),
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
                color: _hasFocus ? accentColor : AppTheme.cardBorder,
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    enabled: !widget.isBusy,
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: inputHint,
                      hintStyle: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                if (_hasText && !widget.isBusy)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    color: AppTheme.textMuted,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _textController.clear(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Send Button
        Tooltip(
          message: 'Translate text',
          child: MouseRegion(
            cursor: canSend ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: GestureDetector(
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
          ),
        ),
      ],
    );
  }
}
