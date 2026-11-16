import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/settings_provider.dart';
import '../../domain/models/chat_message.dart';

/// Functional Settings view with UI language mode selector (English / Japanese),
/// OS & offline TTS speech speed slider, direction defaults, and session history management.
class SettingsView extends StatelessWidget {
  final AppStrings strings;
  final AppSettings settings;
  final TranslationLanguage activeLanguage;
  final bool isSpeaking;
  final int historyCount;
  final ValueChanged<TranslationLanguage> onUiLanguageChanged;
  final ValueChanged<double> onSpeechRateChanged;
  final VoidCallback onToggleAutoDetect;
  final ValueChanged<TranslationLanguage> onDefaultLanguageChanged;
  final VoidCallback onTestEnglishSpeech;
  final VoidCallback onTestJapaneseSpeech;
  final VoidCallback onClearHistory;

  const SettingsView({
    super.key,
    required this.strings,
    required this.settings,
    required this.activeLanguage,
    required this.isSpeaking,
    required this.historyCount,
    required this.onUiLanguageChanged,
    required this.onSpeechRateChanged,
    required this.onToggleAutoDetect,
    required this.onDefaultLanguageChanged,
    required this.onTestEnglishSpeech,
    required this.onTestJapaneseSpeech,
    required this.onClearHistory,
  });

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 512),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.settingsTitle,
                style: s.isJa
                    ? AppTheme.minchoStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.sumi,
                      )
                    : AppTheme.sansStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.sumi,
                      ),
              ),
              const SizedBox(height: 16),

              // 1. Two-Mode App Language Selector (English vs 日本語)
              _SectionCard(
                title: s.sectionAppLanguage,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      s.uiLanguageTitle,
                      style: AppTheme.sansStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.sumi,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.uiLanguageSubtitle,
                      style: AppTheme.sansStyle(
                        fontSize: 12,
                        color: AppTheme.sumiMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _OptionPill(
                            label: 'English',
                            selected: settings.uiLanguage ==
                                TranslationLanguage.english,
                            onTap: () => onUiLanguageChanged(
                              TranslationLanguage.english,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _OptionPill(
                            label: '日本語',
                            selected: settings.uiLanguage ==
                                TranslationLanguage.japanese,
                            onTap: () => onUiLanguageChanged(
                              TranslationLanguage.japanese,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. Speech Speed & TTS Section
              _SectionCard(
                title: s.sectionSpeechSpeed,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          s.playbackRateTitle,
                          style: AppTheme.sansStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.sumi,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.cinnabarLight,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${settings.speechRate.toStringAsFixed(2)}x',
                            style: AppTheme.sansStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.cinnabar,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.playbackRateSubtitle,
                      style: AppTheme.sansStyle(
                        fontSize: 12,
                        color: AppTheme.sumiMuted,
                        height: 1.4,
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppTheme.cinnabar,
                        inactiveTrackColor: AppTheme.lineSubtle,
                        thumbColor: AppTheme.cinnabar,
                        overlayColor: AppTheme.cinnabar.withValues(alpha: 0.12),
                      ),
                      child: Slider(
                        value: settings.speechRate,
                        min: AppSettings.minSpeechRate,
                        max: AppSettings.maxSpeechRate,
                        divisions: 13,
                        label: '${settings.speechRate.toStringAsFixed(2)}x',
                        onChanged: onSpeechRateChanged,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SpeedPresetChip(
                          label: s.presetSlow,
                          selected: (settings.speechRate - 0.8).abs() < 0.03,
                          onTap: () => onSpeechRateChanged(0.8),
                        ),
                        _SpeedPresetChip(
                          label: s.presetNormal,
                          selected: (settings.speechRate - 1.0).abs() < 0.03,
                          onTap: () => onSpeechRateChanged(1.0),
                        ),
                        _SpeedPresetChip(
                          label: s.presetFast,
                          selected: (settings.speechRate - 1.2).abs() < 0.03,
                          onTap: () => onSpeechRateChanged(1.2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: AppTheme.lineSubtle),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: onTestEnglishSpeech,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.sumi,
                            side: const BorderSide(color: AppTheme.lineSubtle),
                            shape: const StadiumBorder(),
                          ),
                          icon: Icon(
                            isSpeaking
                                ? Icons.stop_rounded
                                : Icons.volume_up_outlined,
                            size: 16,
                            color: AppTheme.cinnabar,
                          ),
                          label: Text(s.testEnVoice),
                        ),
                        OutlinedButton.icon(
                          onPressed: onTestJapaneseSpeech,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.sumi,
                            side: const BorderSide(color: AppTheme.lineSubtle),
                            shape: const StadiumBorder(),
                          ),
                          icon: Icon(
                            isSpeaking
                                ? Icons.stop_rounded
                                : Icons.volume_up_outlined,
                            size: 16,
                            color: AppTheme.cinnabar,
                          ),
                          label: Text(s.testJaVoice),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. Language & Input Section
              _SectionCard(
                title: s.sectionInputDirection,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      s.activeSourceLangTitle,
                      style: AppTheme.sansStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.sumi,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _OptionPill(
                            label: s.dirEnToJa,
                            selected:
                                activeLanguage == TranslationLanguage.english,
                            onTap: () => onDefaultLanguageChanged(
                              TranslationLanguage.english,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _OptionPill(
                            label: s.dirJaToEn,
                            selected:
                                activeLanguage == TranslationLanguage.japanese,
                            onTap: () => onDefaultLanguageChanged(
                              TranslationLanguage.japanese,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: AppTheme.lineSubtle),
                    const SizedBox(height: 6),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppTheme.cinnabar,
                      activeTrackColor: AppTheme.cinnabarLight,
                      title: Text(
                        s.autoDetectTitle,
                        style: AppTheme.sansStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.sumi,
                        ),
                      ),
                      subtitle: Text(
                        s.autoDetectSubtitle,
                        style: AppTheme.sansStyle(
                          fontSize: 12,
                          color: AppTheme.sumiMuted,
                        ),
                      ),
                      value: settings.autoDetectTypedLanguage,
                      onChanged: (_) => onToggleAutoDetect(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 4. Data Section
              _SectionCard(
                title: s.sectionSessionData,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.savedPhrasesTitle(historyCount),
                            style: AppTheme.sansStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.sumi,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.savedPhrasesSubtitle,
                            style: AppTheme.sansStyle(
                              fontSize: 12,
                              color: AppTheme.sumiMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: historyCount > 0 ? onClearHistory : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.cinnabarDeep,
                        side: BorderSide(
                          color: historyCount > 0
                              ? AppTheme.outlineVariant
                              : AppTheme.lineSubtle,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(s.clearAllButton),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.washiCard.withValues(alpha: 0.93),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.lineSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AppTheme.sansStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: AppTheme.sumiMuted,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SpeedPresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SpeedPresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.cinnabarLight : AppTheme.washiSubtle,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppTheme.cinnabar : AppTheme.lineSubtle,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.sansStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppTheme.cinnabar : AppTheme.sumiMuted,
          ),
        ),
      ),
    );
  }
}

class _OptionPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppTheme.cinnabarLight : AppTheme.washiSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.cinnabar : AppTheme.lineSubtle,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.sansStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppTheme.cinnabar : AppTheme.sumiMuted,
          ),
        ),
      ),
    );
  }
}
