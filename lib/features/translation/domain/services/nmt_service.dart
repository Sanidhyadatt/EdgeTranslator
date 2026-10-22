/// Abstract contract for offline Neural Machine Translation (NMT).
abstract class NmtService {
  /// Initializes the ONNX translation model and SentencePiece tokenizers.
  Future<void> initialize();

  /// Translates source text into the target language.
  Future<String> translate(String text, {required String sourceLang, required String targetLang});

  /// Releases ONNX runtime sessions and tokenizer resources.
  Future<void> dispose();
}
