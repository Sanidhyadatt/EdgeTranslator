import 'dart:typed_data';
import '../models/asr_result.dart';

/// Abstract contract for offline multilingual ASR and continuous Voice Activity Detection (VAD).
abstract class AsrService {
  /// Initializes the Sherpa-ONNX offline Whisper multilingual recognizer and Silero VAD engine.
  Future<void> initialize();

  /// Transcribes raw normalized Float32 audio samples into text with detected language code.
  Future<AsrResult> transcribe(Float32List samples);

  /// Pushes a streaming audio chunk into the VAD engine for endpointing.
  void acceptVadWaveform(Float32List samples);

  /// Returns true if the VAD has detected an utterance endpointed by 1.5s of silence.
  bool hasSpeechSegment();

  /// Extracts the finalized speech segment audio samples.
  Float32List? popSpeechSegment();

  /// Flushes whatever speech audio has been accumulated so far (for manual Done/Stop Speaking).
  Float32List? flushSpeechSegment();

  /// Resets internal VAD state.
  void resetVad();

  /// Releases native memory and ONNX runtime sessions.
  Future<void> dispose();
}

/// Type alias matching user terminology
typedef ASRService = AsrService;
