import '../../features/translation/domain/models/chat_message.dart';

/// Regular expression covering all core Japanese Unicode blocks:
/// - Hiragana: \u3040 - \u309F
/// - Katakana: \u30A0 - \u30FF
/// - CJK Unified Ideographs (Kanji): \u4E00 - \u9FAF
/// - Katakana Phonetic Extensions: \u31F0 - \u31FF
final RegExp _japaneseRegex = RegExp(
  r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF\u31F0-\u31FF]',
);

/// Detects whether the input string is Japanese or English based on Unicode character analysis.
///
/// Returns [TranslationLanguage.japanese] if any Hiragana, Katakana, or Kanji
/// glyphs are found; otherwise defaults to [TranslationLanguage.english].
TranslationLanguage detectLanguage(String text) {
  if (text.isEmpty) {
    return TranslationLanguage.english;
  }
  return _japaneseRegex.hasMatch(text)
      ? TranslationLanguage.japanese
      : TranslationLanguage.english;
}

/// Helper returning true if the string contains any Japanese characters.
bool isJapaneseText(String text) {
  return _japaneseRegex.hasMatch(text);
}
