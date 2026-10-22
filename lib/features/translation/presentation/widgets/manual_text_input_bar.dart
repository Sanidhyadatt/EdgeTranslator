import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/chat_message.dart';

/// Text input bar featuring:
/// 1. Language Toggle Switch (🇺🇸 EN <-> 🇯🇵 JA)
/// 2. TextField with full keyboard submission
/// 3. Two separate send buttons: "Send EN" and "Send JA"
class ManualTextInputBar extends StatefulWidget {
  final ValueChanged<String>? onSubmit;
  final ValueChanged<String>? onSendEnglish;
  final ValueChanged<String>? onSendJapanese;
  final ValueChanged<TranslationLanguage>? onLanguageChanged;
  final TranslationLanguage activeLanguage;
  final bool isBusy;

  const ManualTextInputBar({
    super.key,
    this.onSubmit,
    this.onSendEnglish,
    this.onSendJapanese,
    this.onLanguageChanged,
    this.activeLanguage = TranslationLanguage.english,
    required this.isBusy,
  });

  @override
  State<ManualTextInputBar> createState() => _ManualTextInputBarState();
}

class _ManualTextInputBarState extends State<ManualTextInputBar> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;
  late TranslationLanguage _selectedLanguage;

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.activeLanguage;
    _textController.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant ManualTextInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeLanguage != oldWidget.activeLanguage) {
      _selectedLanguage = widget.activeLanguage;
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

  void _sendEnglish() {
    final text = _textController.text.trim();
    if (text.isEmpty || widget.isBusy) return;

    if (widget.onSendEnglish != null) {
      widget.onSendEnglish!(text);
    } else if (widget.onSubmit != null) {
      widget.onSubmit!(text);
    }
    _textController.clear();
    _focusNode.unfocus();
  }

  void _sendJapanese() {
    final text = _textController.text.trim();
    if (text.isEmpty || widget.isBusy) return;

    if (widget.onSendJapanese != null) {
      widget.onSendJapanese!(text);
    } else if (widget.onSubmit != null) {
      widget.onSubmit!(text);
    }
    _textController.clear();
    _focusNode.unfocus();
  }

  void _handleGeneralSubmit() {
    if (_selectedLanguage == TranslationLanguage.english) {
      _sendEnglish();
    } else {
      _sendJapanese();
    }
  }

  void _toggleLanguage() {
    setState(() {
      _selectedLanguage = _selectedLanguage == TranslationLanguage.english
          ? TranslationLanguage.japanese
          : TranslationLanguage.english;
    });
    widget.onLanguageChanged?.call(_selectedLanguage);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _hasText && !widget.isBusy;
    final isEn = _selectedLanguage == TranslationLanguage.english;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Language Toggle Switch Row
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Segmented Toggle Switch
              GestureDetector(
                onTap: widget.isBusy ? null : _toggleLanguage,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildToggleItem(
                        flag: '🇺🇸',
                        label: 'English',
                        isSelected: isEn,
                        activeColor: AppTheme.primaryNeon,
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.swap_horiz_rounded, size: 14, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                      _buildToggleItem(
                        flag: '🇯🇵',
                        label: '日本語',
                        isSelected: !isEn,
                        activeColor: const Color(0xFFFF5277),
                      ),
                    ],
                  ),
                ),
              ),

              // Helper Label
              Text(
                isEn ? 'English ➔ Japanese' : 'Japanese ➔ English',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),

        // 2. Main Input Container with TextField and Two Separate Send Buttons
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _focusNode.hasFocus ? AppTheme.primaryNeon : AppTheme.cardBorder,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: _focusNode.hasFocus
                    ? AppTheme.primaryNeon.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.keyboard_outlined,
                size: 20,
                color: AppTheme.textMuted,
              ),
              const SizedBox(width: 8),

              // TextField
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  enabled: !widget.isBusy,
                  textInputAction: TextInputAction.send,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Type English or Japanese to translate...',
                    hintStyle: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (_) => _handleGeneralSubmit(),
                ),
              ),

              if (_hasText && !widget.isBusy)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  color: AppTheme.textMuted,
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _textController.clear(),
                ),

              // 3. Two Separate Send Buttons
              // Send English Button
              Tooltip(
                message: 'Send English (translates to Japanese)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: canSend ? _sendEnglish : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: canSend
                          ? AppTheme.primaryNeon.withValues(alpha: 0.2)
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: canSend
                            ? AppTheme.primaryNeon
                            : AppTheme.cardBorder.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🇺🇸', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Text(
                          'Send EN',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: canSend ? AppTheme.primaryNeon : AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // Send Japanese Button
              Tooltip(
                message: 'Send Japanese (translates to English)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: canSend ? _sendJapanese : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: canSend
                          ? const Color(0xFFFF5277).withValues(alpha: 0.2)
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: canSend
                            ? const Color(0xFFFF5277)
                            : AppTheme.cardBorder.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🇯🇵', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Text(
                          'Send JA',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: canSend ? const Color(0xFFFF5277) : AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleItem({
    required String flag,
    required String label,
    required bool isSelected,
    required Color activeColor,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? activeColor.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? activeColor : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flag, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? activeColor : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
