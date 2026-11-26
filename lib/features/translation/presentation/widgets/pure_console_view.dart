import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/chat_message.dart';
import 'japanese_cat_face.dart';

/// Pure Console translation workspace matching Stitch's Sumi & Washi editorial layout.
class PureConsoleView extends StatefulWidget {
  final AppStrings strings;
  final TranslationLanguage activeLanguage;
  final ValueChanged<TranslationLanguage> onLanguageChanged;
  final List<ChatMessage> messages;
  final ChatMessage? selectedMessage;
  final ValueChanged<ChatMessage> onSelectMessage;
  final bool isBusy;
  final bool isSlowMode;
  final String? errorMessage;
  final VoidCallback onDismissError;
  final ValueChanged<String> onSendText;
  final VoidCallback onStartMic;
  final ValueChanged<String> onPlayTranslation;
  final ValueChanged<String> onPlayOriginal;
  final ValueChanged<ChatMessage> onOpenFullscreen;
  final VoidCallback onToggleSlowMode;

  const PureConsoleView({
    super.key,
    required this.strings,
    required this.activeLanguage,
    required this.onLanguageChanged,
    required this.messages,
    required this.selectedMessage,
    required this.onSelectMessage,
    required this.isBusy,
    required this.isSlowMode,
    this.errorMessage,
    required this.onDismissError,
    required this.onSendText,
    required this.onStartMic,
    required this.onPlayTranslation,
    required this.onPlayOriginal,
    required this.onOpenFullscreen,
    required this.onToggleSlowMode,
  });

  @override
  State<PureConsoleView> createState() => _PureConsoleViewState();
}

class _PureConsoleViewState extends State<PureConsoleView> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isComposerOpen = false;
  bool _hasText = false;
  bool _justCopied = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      final hasContent = _textController.text.trim().isNotEmpty;
      if (hasContent != _hasText) {
        setState(() => _hasText = hasContent);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleComposer() {
    setState(() {
      _isComposerOpen = !_isComposerOpen;
    });
    if (_isComposerOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } else {
      _focusNode.unfocus();
    }
  }

  void _submitText() {
    final text = _textController.text.trim();
    if (text.isEmpty || widget.isBusy) return;
    widget.onSendText(text);
    _textController.clear();
    _focusNode.unfocus();
    setState(() => _isComposerOpen = false);
  }

  void _copyTranslation(String text) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _justCopied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.strings.copiedSnackbar),
        duration: const Duration(seconds: 1),
      ),
    );
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _justCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final heroMessage = widget.selectedMessage ??
        (widget.messages.isNotEmpty ? widget.messages.last : null);
    final recentMessages = heroMessage == null
        ? const <ChatMessage>[]
        : widget.messages
            .where((m) => m.id != heroMessage.id)
            .toList()
            .reversed
            .take(8)
            .toList();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 512),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DirectionPill(
                      strings: s,
                      activeLanguage: widget.activeLanguage,
                      disabled: widget.isBusy,
                      onSwap: () => widget.onLanguageChanged(
                        widget.activeLanguage.opposite,
                      ),
                    ),
                    if (widget.errorMessage != null &&
                        widget.errorMessage!.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _NoticeStrip(
                        message: widget.errorMessage!,
                        onDismiss: widget.onDismissError,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _HeroStageCard(
                      strings: s,
                      message: heroMessage,
                      isSlowMode: widget.isSlowMode,
                      justCopied: _justCopied,
                      onCopy: heroMessage == null ||
                              heroMessage.translatedText == 'Translating...'
                          ? null
                          : () => _copyTranslation(heroMessage.translatedText),
                      onPlaySource: heroMessage == null
                          ? null
                          : () => widget.onPlayOriginal(heroMessage.id),
                      onPlayTarget: heroMessage == null ||
                              heroMessage.translatedText == 'Translating...'
                          ? null
                          : () => widget.onPlayTranslation(heroMessage.id),
                      onToggleSlow: widget.onToggleSlowMode,
                      onExpand: heroMessage == null ||
                              heroMessage.translatedText == 'Translating...'
                          ? null
                          : () => widget.onOpenFullscreen(heroMessage),
                    ),
                    if (recentMessages.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.recentPhrasesTitle,
                            style: AppTheme.sansStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                              color: AppTheme.sumiMuted,
                            ),
                          ),
                          Text(
                            s.todayLabel,
                            style: AppTheme.sansStyle(
                              fontSize: 11,
                              color: AppTheme.sumiMuted.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < recentMessages.length; i++) ...[
                        _RecentPhraseRow(
                          strings: s,
                          message: recentMessages[i],
                          onTap: () => widget.onSelectMessage(recentMessages[i]),
                          onSpeak: () =>
                              widget.onPlayTranslation(recentMessages[i].id),
                        ),
                        if (i < recentMessages.length - 1)
                          const Divider(height: 1, color: AppTheme.lineSubtle),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isComposerOpen) ...[
                    _InlineComposer(
                      strings: s,
                      controller: _textController,
                      focusNode: _focusNode,
                      activeLanguage: widget.activeLanguage,
                      hasText: _hasText,
                      isBusy: widget.isBusy,
                      onSubmit: _submitText,
                      onClose: _toggleComposer,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _FloatingDock(
                    strings: s,
                    activeLanguage: widget.activeLanguage,
                    isComposerOpen: _isComposerOpen,
                    isBusy: widget.isBusy,
                    onTypeTap: _toggleComposer,
                    onMicTap: widget.onStartMic,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectionPill extends StatelessWidget {
  final AppStrings strings;
  final TranslationLanguage activeLanguage;
  final bool disabled;
  final VoidCallback onSwap;

  const _DirectionPill({
    required this.strings,
    required this.activeLanguage,
    required this.disabled,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final source = activeLanguage;
    final target = activeLanguage.opposite;
    return Center(
      heightFactor: 1.0,
      child: InkWell(
        onTap: disabled ? null : onSwap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.washiSubtle.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.lineSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppTheme.cinnabar,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                strings.langName(source),
                style: source == TranslationLanguage.japanese
                    ? AppTheme.minchoStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.sumi,
                      )
                    : AppTheme.sansStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.sumi,
                      ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.sync_alt_rounded,
                  size: 16,
                  color: AppTheme.sumiMuted,
                ),
              ),
              Text(
                strings.langName(target),
                style: target == TranslationLanguage.japanese
                    ? AppTheme.minchoStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.sumiMuted,
                      )
                    : AppTheme.sansStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.sumiMuted,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeStrip extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _NoticeStrip({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cinnabarLight.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: AppTheme.cinnabarDeep,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTheme.sansStyle(
                fontSize: 12,
                color: AppTheme.sumi,
                height: 1.35,
              ),
            ),
          ),
          InkWell(
            onTap: onDismiss,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppTheme.sumiMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStageCard extends StatelessWidget {
  final AppStrings strings;
  final ChatMessage? message;
  final bool isSlowMode;
  final bool justCopied;
  final VoidCallback? onCopy;
  final VoidCallback? onPlaySource;
  final VoidCallback? onPlayTarget;
  final VoidCallback onToggleSlow;
  final VoidCallback? onExpand;

  const _HeroStageCard({
    required this.strings,
    required this.message,
    required this.isSlowMode,
    required this.justCopied,
    required this.onCopy,
    required this.onPlaySource,
    required this.onPlayTarget,
    required this.onToggleSlow,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.washiCard.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.lineSubtle),
        boxShadow: [
          BoxShadow(
            color: AppTheme.sumi.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
        child: message == null
            ? _buildEmptyHero()
            : _buildPopulatedHero(message!),
      ),
    );
  }

  Widget _buildEmptyHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.washiSubtle,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.lineSubtle),
            ),
            child: const Icon(
              Icons.translate_rounded,
              size: 24,
              color: AppTheme.cinnabar,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            strings.emptyHeroTitle,
            textAlign: TextAlign.center,
            style: strings.isJa
                ? AppTheme.minchoStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.sumi,
                  )
                : AppTheme.sansStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.sumi,
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            strings.emptyHeroSubtitle,
            textAlign: TextAlign.center,
            style: AppTheme.sansStyle(
              fontSize: 13,
              color: AppTheme.sumiMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopulatedHero(ChatMessage msg) {
    final isJapaneseSource = msg.sourceLang == TranslationLanguage.japanese;
    final isJapaneseTarget = msg.targetLang == TranslationLanguage.japanese;
    final isTranslating = msg.translatedText == 'Translating...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _IconAction(
              icon: justCopied
                  ? Icons.check_rounded
                  : Icons.content_copy_rounded,
              color: justCopied ? AppTheme.cinnabar : AppTheme.sumiMuted,
              tooltip: strings.copyTooltip,
              onTap: onCopy,
            ),
            const SizedBox(width: 8),
            _IconAction(
              icon: Icons.volume_up_outlined,
              color: AppTheme.sumiMuted,
              tooltip: strings.listenOriginalTooltip,
              onTap: onPlaySource,
            ),
            const Spacer(),
            Text(
              strings.directionBadge(msg.sourceLang),
              style: AppTheme.sansStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppTheme.sumiMuted.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: AppTheme.lineSubtle),
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 20),
          child: SelectableText(
            msg.originalText,
            style: isJapaneseSource
                ? AppTheme.minchoStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    height: 1.65,
                    color: AppTheme.sumiMuted,
                  )
                : AppTheme.sansStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                    color: AppTheme.sumiMuted,
                  ),
          ),
        ),
        const Divider(height: 1, color: AppTheme.lineSubtle),
        Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 20),
          child: isTranslating
              ? Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.cinnabar,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      strings.translatingLabel,
                      style: AppTheme.sansStyle(
                        fontSize: 15,
                        color: AppTheme.sumiMuted,
                      ),
                    ),
                  ],
                )
              : SelectableText(
                  msg.translatedText,
                  style: isJapaneseTarget
                      ? AppTheme.minchoStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w500,
                          height: 1.75,
                          letterSpacing: 0.5,
                          color: AppTheme.sumi,
                        )
                      : AppTheme.sansStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          color: AppTheme.sumi,
                        ),
                ),
        ),
        Divider(height: 1, color: AppTheme.lineSubtle.withValues(alpha: 0.65)),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            InkWell(
              onTap: onToggleSlow,
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color:
                      isSlowMode ? AppTheme.cinnabarLight : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.slow_motion_video_rounded,
                      size: 16,
                      color:
                          isSlowMode ? AppTheme.cinnabar : AppTheme.sumiMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      strings.slowSpeedLabel,
                      style: AppTheme.sansStyle(
                        fontSize: 12,
                        fontWeight:
                            isSlowMode ? FontWeight.w600 : FontWeight.w500,
                        color:
                            isSlowMode ? AppTheme.cinnabar : AppTheme.sumiMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: onExpand,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fullscreen_rounded,
                      size: 17,
                      color: onExpand == null
                          ? AppTheme.sumiMuted.withValues(alpha: 0.4)
                          : AppTheme.sumiMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      strings.expandLabel,
                      style: AppTheme.sansStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: onExpand == null
                            ? AppTheme.sumiMuted.withValues(alpha: 0.4)
                            : AppTheme.sumiMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: onPlayTarget,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cinnabar,
                disabledBackgroundColor:
                    AppTheme.cinnabar.withValues(alpha: 0.35),
                foregroundColor: Colors.white,
                elevation: 1,
                shadowColor: AppTheme.cinnabar.withValues(alpha: 0.28),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 34),
              ),
              icon: Icon(
                msg.isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
                size: 16,
              ),
              label: Text(
                msg.isPlaying ? strings.stopLabel : strings.listenLabel,
                style: AppTheme.sansStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecentPhraseRow extends StatelessWidget {
  final AppStrings strings;
  final ChatMessage message;
  final VoidCallback onTap;
  final VoidCallback onSpeak;

  const _RecentPhraseRow({
    required this.strings,
    required this.message,
    required this.onTap,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    final isJapaneseTarget = message.targetLang == TranslationLanguage.japanese;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.washiCard.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.originalText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sansStyle(
                      fontSize: 13,
                      color: AppTheme.sumiMuted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.translatedText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: isJapaneseTarget
                        ? AppTheme.minchoStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.sumi,
                            height: 1.5,
                          )
                        : AppTheme.sansStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.sumi,
                            height: 1.4,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onSpeak,
              tooltip:
                  message.isPlaying ? strings.stopLabel : strings.replayTooltip,
              icon: Icon(
                message.isPlaying
                    ? Icons.stop_rounded
                    : Icons.volume_up_outlined,
                size: 18,
                color: message.isPlaying ? AppTheme.cinnabar : AppTheme.sumiMuted,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineComposer extends StatelessWidget {
  final AppStrings strings;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TranslationLanguage activeLanguage;
  final bool hasText;
  final bool isBusy;
  final VoidCallback onSubmit;
  final VoidCallback onClose;

  const _InlineComposer({
    required this.strings,
    required this.controller,
    required this.focusNode,
    required this.activeLanguage,
    required this.hasText,
    required this.isBusy,
    required this.onSubmit,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.washiCard.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.lineSubtle),
        boxShadow: [
          BoxShadow(
            color: AppTheme.sumi.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            tooltip: strings.hideInputTooltip,
            icon: const Icon(
              Icons.keyboard_hide_rounded,
              size: 19,
              color: AppTheme.sumiMuted,
            ),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: !isBusy,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              style: AppTheme.sansStyle(fontSize: 14, color: AppTheme.sumi),
              decoration: InputDecoration(
                hintText: strings.composerHint(activeLanguage),
                hintStyle: AppTheme.sansStyle(
                  fontSize: 13,
                  color: AppTheme.sumiMuted.withValues(alpha: 0.75),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
              ),
            ),
          ),
          if (hasText && !isBusy)
            IconButton(
              onPressed: () => controller.clear(),
              icon: const Icon(Icons.close_rounded, size: 16),
              color: AppTheme.sumiMuted,
              visualDensity: VisualDensity.compact,
            ),
          const SizedBox(width: 4),
          InkWell(
            onTap: (hasText && !isBusy) ? onSubmit : null,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (hasText && !isBusy)
                    ? AppTheme.cinnabar
                    : AppTheme.washiSubtle,
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                size: 18,
                color: (hasText && !isBusy) ? Colors.white : AppTheme.sumiMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingDock extends StatelessWidget {
  final AppStrings strings;
  final TranslationLanguage activeLanguage;
  final bool isComposerOpen;
  final bool isBusy;
  final VoidCallback onTypeTap;
  final VoidCallback onMicTap;

  const _FloatingDock({
    required this.strings,
    required this.activeLanguage,
    required this.isComposerOpen,
    required this.isBusy,
    required this.onTypeTap,
    required this.onMicTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.washiCard.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.lineSubtle),
            boxShadow: [
              BoxShadow(
                color: AppTheme.sumi.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: onTypeTap,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.keyboard_rounded,
                            size: 20,
                            color: isComposerOpen
                                ? AppTheme.cinnabar
                                : AppTheme.sumiMuted,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            strings.typeButton,
                            style: AppTheme.sansStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isComposerOpen
                                  ? AppTheme.cinnabar
                                  : AppTheme.sumiMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: strings.speakTooltip(activeLanguage),
                child: Material(
                  color: isBusy
                      ? AppTheme.cinnabar.withValues(alpha: 0.45)
                      : AppTheme.cinnabar,
                  shape: const CircleBorder(),
                  elevation: isBusy ? 0 : 3,
                  shadowColor: AppTheme.cinnabar.withValues(alpha: 0.4),
                  child: InkWell(
                    onTap: isBusy ? null : onMicTap,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.mic_rounded,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: JapaneseCatFace(
                    size: 36,
                    tooltip: strings.isJa ? '招き猫' : 'Maneki-neko',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  const _IconAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 18,
            color: onTap == null ? color.withValues(alpha: 0.35) : color,
          ),
        ),
      ),
    );
  }
}
