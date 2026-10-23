# Edge Translator ONNX Models

This directory stores the on-device AI models for 100% offline, low-latency execution.

## Automated Download
All models can be downloaded and verified automatically by running:
```bash
python tool/download_models.py
```

## Directory Structure

1. **Multilingual ASR (Automatic Speech Recognition) & VAD**:
   - `tiny-encoder.int8.onnx` (OpenAI Whisper-tiny quantized encoder)
   - `tiny-decoder.int8.onnx` (OpenAI Whisper-tiny quantized decoder)
   - `tiny-tokens.txt` (Multilingual Whisper vocabulary tokens)
   - `silero_vad.onnx` (Silero Voice Activity Detector)

2. **Bidirectional NMT (Neural Machine Translation - MarianMT)**:
   - `nmt_en_ja/` (English -> Japanese):
     - `encoder_model_quantized.onnx`
     - `decoder_model_quantized.onnx`
     - `source.spm`
     - `target.spm`
     - `vocab.json`
     - `tokenizer_config.json`
   - `nmt_ja_en/` (Japanese -> English):
     - `encoder_model_quantized.onnx`
     - `decoder_model_quantized.onnx`
     - `source.spm`
     - `target.spm`
     - `vocab.json`
     - `tokenizer_config.json`

3. **TTS (Text-to-Speech - VITS)**:
   - `tts_en/` (Piper English VITS):
     - `en_US-lessac-medium.onnx`
     - `tokens.txt`
     - `lexicon.txt`
   - `tts_ja/` (MeloTTS Japanese VITS):
     - `model.onnx`
     - `tokens.txt`
     - `lexicon.txt`

