# Edge Translator ONNX Models

This directory stores the on-device AI models for 100% offline, low-latency execution:

1. **ASR (Automatic Speech Recognition) - English**:
   - Model: Sherpa-ONNX streaming Zipformer / Whisper INT8 quantized model.
   - Files: `tokens.txt`, `encoder.onnx`, `decoder.onnx`, `joiner.onnx`.

2. **NMT (Neural Machine Translation) - English to Japanese**:
   - Model: MarianMT / Helsinki-NLP (`opus-mt-en-jap`) ONNX converted with SentencePiece tokenizer.
   - Files: `source.spm`, `target.spm`, `model.onnx` or quantized `model_quantized.onnx`.

3. **TTS (Text-to-Speech) - Japanese**:
   - Model: Sherpa-ONNX Japanese VITS model (e.g. `vits-melo-tts-jp`).
   - Files: `model.onnx`, `lexicon.txt`, `tokens.txt`.
