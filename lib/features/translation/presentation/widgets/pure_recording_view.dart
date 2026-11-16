import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/chat_message.dart';

/// Pure Recording viewport styled after Stitch's Pure Recording screen.
///
/// Keeps listening continuously until the user taps Done or Cancel,
/// and follows [strings] (`English` or `日本語` instruction mode).
class PureRecordingView extends StatefulWidget {
  final AppStrings strings;
  final PipelineStatus status;
  final TranslationLanguage activeLanguage;
  final int recordingSeconds;
  final String? interimTranscript;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  const PureRecordingView({
    super.key,
    required this.strings,
    required this.status,
    required this.activeLanguage,
    required this.recordingSeconds,
    this.interimTranscript,
    required this.onDone,
    required this.onCancel,
  });

  @override
  State<PureRecordingView> createState() => _PureRecordingViewState();
}

class _PureRecordingViewState extends State<PureRecordingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  static const List<double> _baseHeights = [10, 18, 28, 16, 32, 24, 15, 9];
  static const List<bool> _isAccentBar = [
    false,
    false,
    true,
    true,
    false,
    true,
    false,
    false,
  ];
  static const List<double> _barOpacity = [
    0.30,
    0.55,
    1.0,
    0.90,
    1.0,
    1.0,
    0.55,
    0.30,
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final mins = totalSeconds ~/ 60;
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final isProcessing = widget.status.isProcessing;
    final interim = widget.interimTranscript?.trim() ?? '';

    final topPromptText = interim.isNotEmpty
        ? interim
        : (isProcessing ? s.finishingHeading : s.listeningHeading);

    final bottomPromptText =
        isProcessing ? s.translatingInstruction : s.recordingInstruction;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 512),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 12, bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedBuilder(
                        animation: _animController,
                        builder: (context, _) {
                          final cursorAlpha = isProcessing
                              ? 0.0
                              : (0.25 +
                                  0.75 *
                                      (0.5 +
                                          0.5 *
                                              math.sin(_animController.value *
                                                  2 *
                                                  math.pi)));
                          return Text.rich(
                            TextSpan(
                              text: topPromptText,
                              style: s.isJa && interim.isEmpty
                                  ? AppTheme.minchoStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w500,
                                      height: 1.45,
                                      color: AppTheme.sumi,
                                    )
                                  : AppTheme.sansStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w500,
                                      height: 1.35,
                                      letterSpacing: -0.3,
                                      color: AppTheme.sumi,
                                    ),
                              children: [
                                if (!isProcessing)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      width: 2.5,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: AppTheme.cinnabarDeep
                                            .withValues(alpha: cursorAlpha),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Container(
                        height: 1,
                        color: AppTheme.outlineVariant.withValues(alpha: 0.55),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            bottomPromptText,
                            style: s.isJa
                                ? AppTheme.minchoStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w400,
                                    height: 1.65,
                                    color: AppTheme.sumi.withValues(alpha: 0.85),
                                  )
                                : AppTheme.sansStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w400,
                                    height: 1.5,
                                    color: AppTheme.sumi.withValues(alpha: 0.85),
                                  ),
                          ),
                          if (!isProcessing)
                            _BouncingDots(controller: _animController),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 36,
                    child: AnimatedBuilder(
                      animation: _animController,
                      builder: (context, _) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < _baseHeights.length; i++) ...[
                              Container(
                                width: _isAccentBar[i] || i == 4 ? 3 : 2.2,
                                height: isProcessing
                                    ? _baseHeights[i] * 0.45
                                    : (_baseHeights[i] *
                                            (0.55 +
                                                0.45 *
                                                    math.sin(
                                                        (_animController.value *
                                                                2 *
                                                                math.pi) +
                                                            i * 0.75)))
                                        .clamp(6.0, 34.0),
                                decoration: BoxDecoration(
                                  color: (_isAccentBar[i]
                                          ? AppTheme.cinnabarDeep
                                          : AppTheme.sumi)
                                      .withValues(alpha: _barOpacity[i]),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              if (i < _baseHeights.length - 1)
                                const SizedBox(width: 6),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDuration(widget.recordingSeconds),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                      color: AppTheme.sumi,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isProcessing ? null : widget.onCancel,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppTheme.recordingSurfaceHigh
                                .withValues(alpha: 0.85),
                            foregroundColor: AppTheme.sumi,
                            side: BorderSide(
                              color: AppTheme.outlineVariant
                                  .withValues(alpha: 0.65),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: AppTheme.outlineMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                s.cancelLabel,
                                style: AppTheme.sansStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.sumi,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isProcessing ? null : widget.onDone,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.cinnabarDeep,
                            disabledBackgroundColor:
                                AppTheme.cinnabarDeep.withValues(alpha: 0.8),
                            foregroundColor: Colors.white,
                            elevation: 1,
                            shadowColor:
                                AppTheme.cinnabarDeep.withValues(alpha: 0.25),
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: isProcessing
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      s.savingLabel,
                                      style: AppTheme.sansStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      s.doneLabel,
                                      style: AppTheme.sansStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BouncingDots extends StatelessWidget {
  final Animation<double> controller;

  const _BouncingDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final dy1 = -3.0 * math.sin(controller.value * 2 * math.pi).abs();
        final dy2 =
            -3.0 * math.sin((controller.value * 2 * math.pi) + 0.8).abs();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: Offset(0, dy1),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppTheme.cinnabarDeep,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Transform.translate(
              offset: Offset(0, dy2),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppTheme.cinnabarDeep.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
