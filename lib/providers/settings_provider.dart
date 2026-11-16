import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/translation/domain/models/chat_message.dart';
import 'service_providers.dart';

/// User preferences, UI language mode, and TTS speed controls.
class AppSettings {
  static const double minSpeechRate = 0.6;
  static const double maxSpeechRate = 1.25;
  static const double slowSpeechRate = 0.8;
  static const double normalSpeechRate = 1.0;

  /// Speech speed multiplier applied to both OS TTS (`flutter_tts`) and offline VITS.
  final double speechRate;

  /// Whether typed input should auto-detect English vs Japanese script.
  final bool autoDetectTypedLanguage;

  /// Default conversation source language used on startup / reset.
  final TranslationLanguage defaultLanguage;

  /// App UI & instruction language (`english` or `japanese`).
  final TranslationLanguage uiLanguage;

  const AppSettings({
    this.speechRate = normalSpeechRate,
    this.autoDetectTypedLanguage = true,
    this.defaultLanguage = TranslationLanguage.english,
    this.uiLanguage = TranslationLanguage.english,
  });

  bool get isSlowMode => speechRate <= 0.85;

  AppSettings copyWith({
    double? speechRate,
    bool? autoDetectTypedLanguage,
    TranslationLanguage? defaultLanguage,
    TranslationLanguage? uiLanguage,
  }) {
    return AppSettings(
      speechRate: speechRate ?? this.speechRate,
      autoDetectTypedLanguage:
          autoDetectTypedLanguage ?? this.autoDetectTypedLanguage,
      defaultLanguage: defaultLanguage ?? this.defaultLanguage,
      uiLanguage: uiLanguage ?? this.uiLanguage,
    );
  }
}

/// Manages session settings including OS & offline TTS speech speed and UI language.
class SettingsNotifier extends Notifier<AppSettings> {
  double _lastNonSlowRate = AppSettings.normalSpeechRate;

  @override
  AppSettings build() {
    return const AppSettings();
  }

  /// Sets the speech rate (`0.6` .. `1.25`) and syncs it with [TtsPlayerService].
  void setSpeechRate(double rate) {
    final clamped =
        rate.clamp(AppSettings.minSpeechRate, AppSettings.maxSpeechRate);
    final rounded = (clamped * 20).round() / 20.0;
    if (rounded > 0.85) {
      _lastNonSlowRate = rounded;
    }
    state = state.copyWith(speechRate: rounded);
    ref.read(ttsPlayerServiceProvider).setSpeechRate(rounded);
  }

  /// Toggles between `0.8x Slow` and normal playback speed (`1.0x` or last rate).
  void toggleSlowMode() {
    if (state.isSlowMode) {
      setSpeechRate(
        _lastNonSlowRate > 0.85 ? _lastNonSlowRate : AppSettings.normalSpeechRate,
      );
    } else {
      if (state.speechRate > 0.85) {
        _lastNonSlowRate = state.speechRate;
      }
      setSpeechRate(AppSettings.slowSpeechRate);
    }
  }

  void setAutoDetectTypedLanguage(bool enabled) {
    state = state.copyWith(autoDetectTypedLanguage: enabled);
  }

  void setDefaultLanguage(TranslationLanguage language) {
    state = state.copyWith(defaultLanguage: language);
  }

  /// Switches all app instructions and UI labels between English and Japanese.
  void setUiLanguage(TranslationLanguage language) {
    state = state.copyWith(uiLanguage: language);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
