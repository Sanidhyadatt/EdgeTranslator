# IKHO On-Device ONNX Models

All offline AI models are packaged in the Android install-time AI pack module:
`android/ai_models/src/main/assets/models/`

They are intentionally excluded from Flutter `pubspec.yaml` `assets` so the base app module does not duplicate the ~857.5 MB model bundle.

## AI Pack Directory Structure

1. **Multilingual ASR (Automatic Speech Recognition) & VAD (`sherpa_onnx`):**
   - `asr/sense-voice.int8.onnx`
   - `asr/sense-voice-tokens.txt`
   - `silero_vad.onnx`

2. **Bidirectional NMT (`onnxruntime` MarianMT):**
   - `nmt_en_ja/` (`encoder_model_quantized.onnx`, `decoder_model_quantized.onnx`, `source.spm`, `target.spm`, `vocab.json`, `tokenizer_config.json`)
   - `nmt_ja_en/` (`encoder_model_quantized.onnx`, `decoder_model_quantized.onnx`, `source.spm`, `target.spm`, `vocab.json`, `tokenizer_config.json`)

3. **TTS (Text-to-Speech):**
   - `tts_en/` (`en_US-lessac-medium.onnx`, `tokens.txt`, `espeak-ng-data/`) — via `sherpa_onnx`
   - `tts_ja/` (`model (1).onnx`, `tokens (2).txt`, `lexicon.txt`, `metadata.json`) — via `onnxruntime`
