import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/chat_message.dart';
import 'chat_message_card.dart';

/// Scrollable conversation log area showing all completed translations and live in-progress state.
class ChatLogView extends StatefulWidget {
  final List<ChatMessage> messages;
  final PipelineStatus status;
  final TranslationLanguage? activeLanguage;
  final String? interimTranscript;
  final String? interimTranslation;
  final ValueChanged<String> onPlayMessage;

  const ChatLogView({
    super.key,
    required this.messages,
    required this.status,
    this.activeLanguage,
    this.interimTranscript,
    this.interimTranslation,
    required this.onPlayMessage,
  });

  @override
  State<ChatLogView> createState() => _ChatLogViewState();
}

class _ChatLogViewState extends State<ChatLogView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant ChatLogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length ||
        widget.status != oldWidget.status) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showEmptyState = widget.messages.isEmpty && !widget.status.isProcessing;

    if (showEmptyState) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surfaceElevated,
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 32,
                  color: AppTheme.primaryNeon,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Conversation Log',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap the microphone or type below to translate.\nTap Speak on any translation whenever you want it read aloud.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.cardBorder.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.security_rounded, size: 16, color: AppTheme.successEmerald),
                    const SizedBox(width: 8),
                    const Text(
                      '100% On-Device • Zero Cloud Tracking',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      physics: const BouncingScrollPhysics(),
      itemCount: widget.messages.length + (widget.status.isProcessing ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < widget.messages.length) {
          final message = widget.messages[index];
          return ChatMessageCard(
            key: ValueKey(message.id),
            message: message,
            onPlay: () => widget.onPlayMessage(message.id),
          );
        }

        // Live In-Progress Card
        return _buildInProgressCard();
      },
    );
  }

  Widget _buildInProgressCard() {
    final lang = widget.activeLanguage ?? TranslationLanguage.english;
    final isEn = lang == TranslationLanguage.english;
    final accentColor = widget.status.isRecording
        ? AppTheme.errorRose
        : (isEn ? AppTheme.primaryNeon : const Color(0xFFFF5277));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(lang.flag, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                widget.status.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
            ],
          ),
          if (widget.interimTranscript != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.interimTranscript!,
              style: const TextStyle(
                fontSize: 15,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          if (widget.interimTranslation != null) ...[
            const SizedBox(height: 8),
            Container(
              height: 1,
              color: AppTheme.cardBorder,
            ),
            const SizedBox(height: 8),
            Text(
              widget.interimTranslation!,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
