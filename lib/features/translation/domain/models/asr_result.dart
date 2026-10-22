import 'chat_message.dart';

/// Result from multilingual Automatic Speech Recognition (ASR).
/// Contains the transcribed text alongside the detected language code.
class AsrResult {
  final String text;
  final String language; // e.g. 'en', 'ja'

  const AsrResult({
    required this.text,
    required this.language,
  });

  /// Maps the raw language code to the supported TranslationLanguage enum.
  TranslationLanguage get translationLanguage =>
      language.toLowerCase() == 'ja'
          ? TranslationLanguage.japanese
          : TranslationLanguage.english;

  bool get isEnglish => translationLanguage == TranslationLanguage.english;
  bool get isJapanese => translationLanguage == TranslationLanguage.japanese;

  @override
  String toString() => 'AsrResult(text: "$text", language: "$language")';
}
