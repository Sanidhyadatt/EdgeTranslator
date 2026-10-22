import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_logger.dart';
import '../features/translation/domain/models/pipeline_state.dart';
import 'service_providers.dart';

/// Riverpod State Machine managing the end-to-end translation pipeline:
/// Idle -> Recording -> ASR -> NMT -> TTS -> Playback -> Idle.
class PipelineNotifier extends Notifier<TranslationPipelineState> {
  @override
  TranslationPipelineState build() {
    return const TranslationPipelineState();
  }

  /// Toggles recording session on / off.
  Future<void> toggleRecording() async {
    if (state.currentStep == PipelineStep.recording) {
      await stopAndProcess();
    } else if (state.currentStep == PipelineStep.idle || state.currentStep == PipelineStep.error) {
      await startRecording();
    }
  }

  /// Begins mic capture session.
  Future<void> startRecording() async {
    try {
      final recorder = ref.read(audioRecorderProvider);
      final hasPermission = await recorder.hasPermission();

      if (!hasPermission) {
        state = state.copyWith(
          currentStep: PipelineStep.error,
          errorMessage: 'Microphone permission not granted.',
        );
        return;
      }

      state = state.copyWith(
        currentStep: PipelineStep.recording,
        errorMessage: null,
      );

      AppLogger.info('PipelineNotifier', 'Audio recording started.');
    } catch (e, st) {
      AppLogger.error('PipelineNotifier', 'Failed to start recording', e, st);
      state = state.copyWith(
        currentStep: PipelineStep.error,
        errorMessage: 'Failed to start audio recording: $e',
      );
    }
  }

  /// Halts recording and executes the sequence: ASR -> NMT -> TTS.
  Future<void> stopAndProcess() async {
    final latencies = <String, int>{};

    try {
      // Step 1: Complete Recording
      AppLogger.info('PipelineNotifier', 'Stopping audio recording...');
      final recordingStopwatch = Stopwatch()..start();
      // Simulated audio file path for foundation check
      const capturedAudioPath = 'simulated_audio.wav';
      recordingStopwatch.stop();

      // Step 2: Speech-to-Text (ASR)
      state = state.copyWith(
        currentStep: PipelineStep.speechToText,
        audioPath: capturedAudioPath,
      );
      final asrStopwatch = Stopwatch()..start();
      final asrService = ref.read(asrServiceProvider);
      final asrResult = await asrService.transcribe(Float32List(16000));
      final transcribedText = asrResult.text;
      asrStopwatch.stop();
      latencies['ASR'] = asrStopwatch.elapsedMilliseconds;

      state = state.copyWith(
        sourceText: transcribedText,
        currentStep: PipelineStep.translation,
      );

      // Step 3: Neural Machine Translation (NMT)
      final nmtStopwatch = Stopwatch()..start();
      final nmtService = ref.read(nmtServiceProvider);
      final translatedText = await nmtService.translate(
        transcribedText,
        sourceLang: 'en',
        targetLang: 'ja',
      );
      nmtStopwatch.stop();
      latencies['NMT'] = nmtStopwatch.elapsedMilliseconds;

      state = state.copyWith(
        targetText: translatedText,
        currentStep: PipelineStep.textToSpeech,
      );

      // Step 4: Text-to-Speech (TTS)
      final ttsStopwatch = Stopwatch()..start();
      final ttsService = ref.read(ttsServiceProvider);
      final ttsAudioPath = await ttsService.synthesize(translatedText);
      ttsStopwatch.stop();
      latencies['TTS'] = ttsStopwatch.elapsedMilliseconds;

      // Completed successfully
      state = state.copyWith(
        currentStep: PipelineStep.idle,
        audioPath: ttsAudioPath,
        latencyBreakdown: latencies,
      );
      AppLogger.info(
        'PipelineNotifier',
        'Pipeline completed in ${state.totalLatencyMs}ms: $latencies',
      );
    } catch (e, st) {
      AppLogger.error('PipelineNotifier', 'Pipeline failure occurred', e, st);
      state = state.copyWith(
        currentStep: PipelineStep.error,
        errorMessage: 'Pipeline error: $e',
      );
    }
  }

  /// Replays the generated speech for the translated Japanese text.
  Future<void> playTranslatedAudio() async {
    if (state.targetText.isEmpty) return;
    try {
      state = state.copyWith(currentStep: PipelineStep.playing);
      AppLogger.info('PipelineNotifier', 'Playing synthesized audio...');
      // Simulated playback wait for UI feedback
      await Future<void>.delayed(const Duration(milliseconds: 600));
      state = state.copyWith(currentStep: PipelineStep.idle);
    } catch (e, st) {
      AppLogger.error('PipelineNotifier', 'Playback failed', e, st);
      state = state.copyWith(
        currentStep: PipelineStep.error,
        errorMessage: 'Playback error: $e',
      );
    }
  }

  /// Clears transcription and translation history.
  void clear() {
    state = const TranslationPipelineState();
  }
}

/// Provider exposing the translation pipeline state and actions to UI widgets.
final pipelineNotifierProvider =
    NotifierProvider<PipelineNotifier, TranslationPipelineState>(PipelineNotifier.new);
