import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../providers/translation_pipeline_provider.dart';
import '../../domain/models/chat_message.dart';
import 'zen_header.dart';

/// Opens the large high-legibility Japanese/English fullscreen card (`拡大`),
/// suitable for showing directly to station staff or locals.
Future<void> showZenFullscreenModal(
  BuildContext context, {
  required ChatMessage initialMessage,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close fullscreen translation',
    barrierColor: AppTheme.washi,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) =>
        _ZenFullscreenDialog(initialMessage: initialMessage),
  );
}

class _ZenFullscreenDialog extends ConsumerWidget {
  final ChatMessage initialMessage;

  const _ZenFullscreenDialog({required this.initialMessage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipelineState = ref.watch(translationPipelineProvider);
    final pipelineNotifier = ref.read(translationPipelineProvider.notifier);
    final uiLang = ref.watch(settingsProvider.select((s) => s.uiLanguage));
    final strings = AppStrings.of(uiLang);

    final liveMessage = pipelineState.messages
            .where((m) => m.id == initialMessage.id)
            .firstOrNull ??
        initialMessage;
    final isJapaneseTarget =
        liveMessage.targetLang == TranslationLanguage.japanese;

    return Scaffold(
      backgroundColor: AppTheme.washi,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: Image.asset(
                  AppConstants.washiWallpaperAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomCenter,
                  color: const Color.fromRGBO(255, 255, 255, 0.78),
                  colorBlendMode: BlendMode.modulate,
                  filterQuality: FilterQuality.low,
                  cacheWidth: (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .round()
                      .clamp(360, 1440),
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const HankoMark(size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          strings.fullscreenHeader,
                          style: AppTheme.sansStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.sumiMuted,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.washiSubtle.withValues(alpha: 0.9),
                            border: Border.all(color: AppTheme.lineSubtle),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 22,
                            color: AppTheme.sumi,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          vertical: 24,
                          horizontal: 8,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SelectableText(
                              liveMessage.translatedText,
                              textAlign: TextAlign.center,
                              style: isJapaneseTarget
                                  ? AppTheme.minchoStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w600,
                                      height: 1.85,
                                      letterSpacing: 1.1,
                                      color: AppTheme.sumi,
                                    )
                                  : AppTheme.sansStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w600,
                                      height: 1.45,
                                      color: AppTheme.sumi,
                                    ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              liveMessage.originalText,
                              textAlign: TextAlign.center,
                              style: AppTheme.sansStyle(
                                fontSize: 14,
                                color: AppTheme.sumiMuted,
                              ),
                            ),
                            const SizedBox(height: 32),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  pipelineNotifier.playMessageAudio(liveMessage.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.cinnabar,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                shadowColor:
                                    AppTheme.cinnabar.withValues(alpha: 0.35),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 14,
                                ),
                                shape: const StadiumBorder(),
                              ),
                              icon: Icon(
                                liveMessage.isPlaying
                                    ? Icons.stop_rounded
                                    : Icons.volume_up_rounded,
                                size: 20,
                              ),
                              label: Text(
                                liveMessage.isPlaying
                                    ? strings.fullscreenStopAudio
                                    : strings.fullscreenPlayAudio,
                                style: AppTheme.sansStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Text(
                    strings.fullscreenFooterHint,
                    style: AppTheme.sansStyle(
                      fontSize: 12,
                      color: AppTheme.sumiMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
