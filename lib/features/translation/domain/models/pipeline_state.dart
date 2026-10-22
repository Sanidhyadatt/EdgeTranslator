/// Discrete steps in the offline speech-to-speech translation pipeline.
enum PipelineStep {
  idle,
  recording,
  speechToText,
  translation,
  textToSpeech,
  playing,
  error,
}

extension PipelineStepExtension on PipelineStep {
  String get label {
    switch (this) {
      case PipelineStep.idle:
        return 'Ready';
      case PipelineStep.recording:
        return 'Listening (Microphone)';
      case PipelineStep.speechToText:
        return 'Transcribing (Sherpa-ONNX ASR)';
      case PipelineStep.translation:
        return 'Translating (MarianMT NMT)';
      case PipelineStep.textToSpeech:
        return 'Synthesizing (Sherpa-ONNX TTS)';
      case PipelineStep.playing:
        return 'Playing Japanese Audio';
      case PipelineStep.error:
        return 'Error Occurred';
    }
  }

  bool get isProcessing =>
      this == PipelineStep.recording ||
      this == PipelineStep.speechToText ||
      this == PipelineStep.translation ||
      this == PipelineStep.textToSpeech ||
      this == PipelineStep.playing;
}

/// Immutable state model representing the complete pipeline snapshot.
class TranslationPipelineState {
  final PipelineStep currentStep;
  final String sourceText;
  final String targetText;
  final String? audioPath;
  final String? errorMessage;
  final double decibels;
  final Map<String, int> latencyBreakdown;

  const TranslationPipelineState({
    this.currentStep = PipelineStep.idle,
    this.sourceText = '',
    this.targetText = '',
    this.audioPath,
    this.errorMessage,
    this.decibels = 0.0,
    this.latencyBreakdown = const {},
  });

  TranslationPipelineState copyWith({
    PipelineStep? currentStep,
    String? sourceText,
    String? targetText,
    String? audioPath,
    String? errorMessage,
    double? decibels,
    Map<String, int>? latencyBreakdown,
  }) {
    return TranslationPipelineState(
      currentStep: currentStep ?? this.currentStep,
      sourceText: sourceText ?? this.sourceText,
      targetText: targetText ?? this.targetText,
      audioPath: audioPath ?? this.audioPath,
      errorMessage: errorMessage,
      decibels: decibels ?? this.decibels,
      latencyBreakdown: latencyBreakdown ?? this.latencyBreakdown,
    );
  }

  int get totalLatencyMs => latencyBreakdown.values.fold(0, (sum, val) => sum + val);
}
