/// Abstract contract for offline Text-to-Speech (TTS) synthesis.
abstract class TtsService {
  /// Initializes the Sherpa-ONNX offline TTS models (Japanese and English).
  Future<void> initialize();

  /// Synthesizes target text into speech audio for the specified language.
  ///
  /// [language]: Language code, e.g. 'ja' for Japanese VITS or 'en' for English VITS.
  Future<String> synthesize(
    String text, {
    String language = 'ja',
    double speed = 1.0,
  });

  /// Releases TTS engine memory.
  Future<void> dispose();
}
