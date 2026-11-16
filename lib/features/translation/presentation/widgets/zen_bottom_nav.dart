import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';

/// Clean 3-tab bottom navigation honoring the selected UI instruction language.
class ZenBottomNav extends StatelessWidget {
  final AppStrings strings;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const ZenBottomNav({
    super.key,
    required this.strings,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (icon: Icons.translate_rounded, label: strings.navTranslate),
      (icon: Icons.history_rounded, label: strings.navHistory),
      (icon: Icons.tune_rounded, label: strings.navSettings),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.washi.withValues(alpha: 0.94),
        border: const Border(
          top: BorderSide(color: AppTheme.lineSubtle, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SizedBox(
              height: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: InkWell(
                        onTap: () => onTap(i),
                        splashColor: AppTheme.cinnabarLight,
                        highlightColor: Colors.transparent,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              items[i].icon,
                              size: 22,
                              color: currentIndex == i
                                  ? AppTheme.cinnabar
                                  : AppTheme.sumiMuted,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              items[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.sansStyle(
                                fontSize: 11,
                                fontWeight: currentIndex == i
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: currentIndex == i
                                    ? AppTheme.cinnabar
                                    : AppTheme.sumiMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
