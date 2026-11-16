import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/chat_message.dart';

/// Shared confirmation dialog for clearing saved conversation history.
Future<bool> showClearHistoryDialog(
  BuildContext context, {
  required AppStrings strings,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.washiCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.lineSubtle),
      ),
      title: Text(
        strings.clearDialogTitle,
        style: AppTheme.sansStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppTheme.sumi,
        ),
      ),
      content: Text(
        strings.clearDialogMessage,
        style: AppTheme.sansStyle(
          fontSize: 14,
          color: AppTheme.sumiMuted,
          height: 1.45,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            strings.dialogCancel,
            style: AppTheme.sansStyle(
              color: AppTheme.sumiMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.cinnabarDeep,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(strings.dialogConfirmClear),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Shared Hanko stamp brand mark (`端`).
class HankoMark extends StatelessWidget {
  final double size;
  final Color backgroundColor;

  const HankoMark({
    super.key,
    this.size = 26,
    this.backgroundColor = AppTheme.cinnabar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '端',
        style: AppTheme.minchoStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }
}

/// Quiet minimalist top bar displaying the cursive "IKHO" wordmark and Hanko seal.
class ZenHeader extends StatelessWidget {
  final AppStrings strings;
  final bool showDirectionPill;
  final TranslationLanguage activeLanguage;

  const ZenHeader({
    super.key,
    required this.strings,
    this.showDirectionPill = false,
    this.activeLanguage = TranslationLanguage.english,
  });

  @override
  Widget build(BuildContext context) {
    final isEnSource = activeLanguage == TranslationLanguage.english;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.washi.withValues(alpha: 0.86),
        border: const Border(
          bottom: BorderSide(color: AppTheme.lineSubtle, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 512),
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    HankoMark(
                      size: 26,
                      backgroundColor: showDirectionPill
                          ? AppTheme.cinnabarDeep
                          : AppTheme.cinnabar,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      strings.appTitle,
                      style: AppTheme.cursiveBrandStyle(
                        fontSize: 23,
                        color: AppTheme.sumi,
                      ),
                    ),
                    const Spacer(),
                    if (showDirectionPill)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.recordingSurfaceHigh
                              .withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppTheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              strings.langName(activeLanguage),
                              style: isEnSource && !strings.isJa
                                  ? AppTheme.sansStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.sumi,
                                    )
                                  : AppTheme.minchoStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.sumi,
                                    ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 5),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 13,
                                color: AppTheme.cinnabarDeep,
                              ),
                            ),
                            Text(
                              strings.langName(activeLanguage.opposite),
                              style: !isEnSource && !strings.isJa
                                  ? AppTheme.sansStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.cinnabarDeep,
                                    )
                                  : AppTheme.minchoStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.cinnabarDeep,
                                    ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
