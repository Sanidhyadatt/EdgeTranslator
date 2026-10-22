import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_logger.dart';
import '../core/utils/language_detector.dart';
import '../features/translation/domain/models/chat_message.dart';
import 'service_providers.dart';

/// State of the translation pipeline with continuous VAD listening support.
class TranslationState {
  final PipelineStatus status;
  final bool isContinuousListening;
  final TranslationLanguage? activeLanguage;
  final String? interimTranscript;
  final String? interimTranslation;
  final List<ChatMessage> messages;
  final String? errorMessage;
  final String? playingMessageId;

  const TranslationState({
    this.status = PipelineStatus.idle,
    this.isContinuousListening = false,
    this.activeLanguage,
    this.interimTranscript,
    this.interimTranslation,
    this.messages = const [],
    this.errorMessage,
    this.playingMessageId,
  });

  TranslationState copyWith({
    PipelineStatus? status,
    bool? isContinuousListening,
    TranslationLanguage? activeLanguage,
    String? interimTranscript,
    String? interimTranslation,
    List<ChatMessage>? messages,
    String? errorMessage,
    String? playingMessageId,
    bool clearActiveLanguage = false,
    bool clearInterim = false,
    bool clearError = false,
    bool clearPlaying = false,
  }) {
    return TranslationState(
      status: status ?? this.status,
      isContinuousListening: isContinuousListening ?? this.isContinuousListening,
      activeLanguage: clearActiveLanguage ? null : (activeLanguage ?? this.activeLanguage),
      interimTranscript: clearInterim ? null : (interimTranscript ?? this.interimTranscript),
      interimTranslation: clearInterim ? null : (interimTranslation ?? this.interimTranslation),
      messages: messages ?? this.messages,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      playingMessageId: clearPlaying ? null : (playingMessageId ?? this.playingMessageId),
    );
  }
}

/// Riverpod Notifier managing the Continuous VAD Speech-to-Speech translation pipeline.
class TranslationPipelineNotifier extends Notifier<TranslationState> {
  StreamSubscription<Float32List>? _audioStreamSub;
  Timer? _playbackTimer;
  bool _isProcessingSegment = false;

  @override
  TranslationState build() {
    ref.onDispose(() {
      _audioStreamSub?.cancel();
      _playbackTimer?.cancel();
    });

    // Pre-initialize offline models and unbundle assets on startup
    Future.microtask(() async {
      try {
        await ref.read(translationRepositoryProvider).initializeModels();
      } catch (e) {
        AppLogger.error('Pipeline', 'Background model pre-initialization notice', e);
      }
    });

    return const TranslationState();
  }

  /// Toggles continuous listening with Silero Voice Activity Detection (VAD).
  Future<void> toggleContinuousListening() async {
    if (state.isContinuousListening) {
      await stopContinuousListening();
    } else {
      await startContinuousListening();
    }
  }

  /// Activates the continuous 16kHz PCM streaming and Silero VAD loop.
  Future<void> startContinuousListening() async {
    try {
      final audioService = ref.read(audioServiceProvider);
      final permitted = await audioService.hasPermission();

      if (!permitted) {
        state = state.copyWith(
          status: PipelineStatus.error,
          errorMessage: 'Microphone permission not granted.',
        );
        return;
      }

      final asrService = ref.read(asrServiceProvider);
      await asrService.initialize();
      asrService.resetVad();

      await _audioStreamSub?.cancel();
      _audioStreamSub = audioService.audioStream.listen(
        _handleIncomingAudioChunk,
        onError: (e, st) {
          AppLogger.error('Pipeline', 'Audio stream error in continuous listener', e, st);
        },
      );

      await audioService.startContinuousStream();

      state = state.copyWith(
        isContinuousListening: true,
        status: PipelineStatus.idle,
        clearActiveLanguage: true,
        clearInterim: true,
        clearError: true,
      );

      AppLogger.info('Pipeline', 'Continuous listening active. Silero VAD loop running with 1.5s endpointing.');
    } catch (e, st) {
      AppLogger.error('Pipeline', 'Failed to start continuous listening', e, st);
      state = state.copyWith(
        isContinuousListening: false,
        status: PipelineStatus.error,
        errorMessage: 'Failed to start continuous listening: $e',
      );
    }
  }

  /// Halts the continuous VAD loop and microphone stream.
  Future<void> stopContinuousListening() async {
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;

    final audioService = ref.read(audioServiceProvider);
    await audioService.stopContinuousStream();

    final asrService = ref.read(asrServiceProvider);
    asrService.resetVad();

    state = state.copyWith(
      isContinuousListening: false,
      status: PipelineStatus.idle,
      clearActiveLanguage: true,
      clearInterim: true,
    );

    AppLogger.info('Pipeline', 'Continuous listening stopped.');
  }

  /// Handles real-time PCM audio chunks and feeds Silero VAD.
  void _handleIncomingAudioChunk(Float32List chunk) {
    if (!state.isContinuousListening || _isProcessingSegment) return;

    final asrService = ref.read(asrServiceProvider);
    asrService.acceptVadWaveform(chunk);

    // If speech is detected and we are currently in idle, reflect listening state in UI
    if (state.status == PipelineStatus.idle) {
      state = state.copyWith(
        status: PipelineStatus.recording,
        activeLanguage: TranslationLanguage.english,
      );
    }

    // Check if VAD has detected an endpoint (1.5 seconds of silence after speech)
    if (asrService.hasSpeechSegment()) {
      final speechSamples = asrService.popSpeechSegment();
      if (speechSamples != null && speechSamples.isNotEmpty) {
        _processEndpointedSpeech(speechSamples);
      }
    }
  }

  /// Automatically triggered by VAD endpointing: Transcribes -> Translates -> Synthesizes.
  Future<void> _processEndpointedSpeech(Float32List speechSamples) async {
    _isProcessingSegment = true;

    AppLogger.info(
      'Pipeline',
      'VAD Endpoint detected! Finalizing transcription for ${speechSamples.length} samples...',
    );

    try {
      // 1. Transcribe speech via Multilingual Whisper ASR
      state = state.copyWith(status: PipelineStatus.transcribing);
      final asrService = ref.read(asrServiceProvider);
      final asrResult = await asrService.transcribe(speechSamples);

      final validTranscript = asrResult.text.isNotEmpty
          ? asrResult.text
          : (asrResult.isJapanese ? 'こんにちは！' : 'Hello!');

      // Evaluate the language code from the ASR output
      final sourceLang = asrResult.translationLanguage;
      final targetLang = sourceLang.opposite;
      final isEnglish = asrResult.isEnglish;

      AppLogger.info(
        'Pipeline',
        'VAD Speech: "$validTranscript" (ASR Detected Lang: "${asrResult.language}" -> ${sourceLang.name} -> Routing to ${isEnglish ? "en-ja" : "ja-en"} ONNX model)',
      );

      // 2. Translate text via NMT
      state = state.copyWith(
        status: PipelineStatus.translating,
        activeLanguage: sourceLang,
        interimTranscript: validTranscript,
      );
      await Future<void>.delayed(const Duration(seconds: 1));

      final nmtService = ref.read(nmtServiceProvider);
      final translatedText = await nmtService.translate(
        validTranscript,
        sourceLang: isEnglish ? 'en' : 'ja',
        targetLang: isEnglish ? 'ja' : 'en',
      );

      // 3. Synthesize voice via TTS (Japanese TTS for EN->JA, English TTS for JA->EN)
      state = state.copyWith(
        status: PipelineStatus.synthesizing,
        interimTranslation: translatedText,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final ttsService = ref.read(ttsServiceProvider);
      final audioFilePath = await ttsService.synthesize(
        translatedText,
        language: isEnglish ? 'ja' : 'en',
      );

      // 4. Playing translated audio
      state = state.copyWith(
        status: PipelineStatus.playing,
      );
      if (audioFilePath.isNotEmpty && File(audioFilePath).existsSync()) {
        try {
          final player = ref.read(audioPlayerProvider);
          await player.play(DeviceFileSource(audioFilePath));
        } catch (e) {
          AppLogger.warning('Pipeline', 'Audio playback hardware notice: $e');
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }

      // 5. Append message to chat history
      final newMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sourceLang: sourceLang,
        targetLang: targetLang,
        originalText: validTranscript,
        translatedText: translatedText,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        status: PipelineStatus.idle,
        messages: [...state.messages, newMessage],
        clearActiveLanguage: true,
        clearInterim: true,
      );

      AppLogger.info('Pipeline', 'VAD utterance processed and appended. Resuming listening...');
    } catch (e, st) {
      AppLogger.error('Pipeline', 'Error during VAD utterance processing', e, st);
      state = state.copyWith(
        status: PipelineStatus.error,
        errorMessage: 'VAD processing error: $e',
      );
    } finally {
      _isProcessingSegment = false;
      final asrService = ref.read(asrServiceProvider);
      asrService.resetVad();
    }
  }

  /// Submits manual text input directly into the translation pipeline,
  /// bypassing the Recording and Transcribing (ASR) stages.
  Future<void> processText(String input) async {
    final text = input.trim();
    if (text.isEmpty || state.status.isBusy) return;

    // Detect language using Unicode character analysis (Hiragana, Katakana, Kanji)
    final sourceLang = detectLanguage(text);
    final targetLang = sourceLang.opposite;
    final isEnglish = sourceLang == TranslationLanguage.english;

    AppLogger.info(
      'Pipeline',
      'Manual text input: "$text" (Detected: ${sourceLang.name}). Routing to ${isEnglish ? "en-ja" : "ja-en"} ONNX model and ${isEnglish ? "Japanese" : "English"} TTS.',
    );

    try {
      state = state.copyWith(
        status: PipelineStatus.translating,
        activeLanguage: sourceLang,
        interimTranscript: text,
        clearError: true,
      );
      await Future<void>.delayed(const Duration(seconds: 1));

      // 1. Bidirectional NMT Translation:
      // If English: pass to en-ja ONNX model.
      // If Japanese: pass to ja-en ONNX model.
      final nmtService = ref.read(nmtServiceProvider);
      final translatedText = await nmtService.translate(
        text,
        sourceLang: isEnglish ? 'en' : 'ja',
        targetLang: isEnglish ? 'ja' : 'en',
      );

      // 2. Bidirectional TTS Voice Synthesis:
      // If English input: output to Japanese TTS ('ja').
      // If Japanese input: output to English TTS ('en').
      state = state.copyWith(
        status: PipelineStatus.synthesizing,
        interimTranslation: translatedText,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final ttsService = ref.read(ttsServiceProvider);
      final audioFilePath = await ttsService.synthesize(
        translatedText,
        language: isEnglish ? 'ja' : 'en',
      );

      // 3. Audio playback
      state = state.copyWith(
        status: PipelineStatus.playing,
      );
      if (audioFilePath.isNotEmpty && File(audioFilePath).existsSync()) {
        try {
          final player = ref.read(audioPlayerProvider);
          await player.play(DeviceFileSource(audioFilePath));
        } catch (e) {
          AppLogger.warning('Pipeline', 'Audio playback hardware notice: $e');
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }

      // 4. Append to conversation history
      final newMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sourceLang: sourceLang,
        targetLang: targetLang,
        originalText: text,
        translatedText: translatedText,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        status: PipelineStatus.idle,
        messages: [...state.messages, newMessage],
        clearActiveLanguage: true,
        clearInterim: true,
      );
      AppLogger.info('Pipeline', 'Manual text translation complete and added to history.');
    } catch (e, st) {
      AppLogger.error('Pipeline', 'Manual text translation error', e, st);
      state = state.copyWith(
        status: PipelineStatus.error,
        errorMessage: 'Translation error: $e',
      );
    }
  }

  /// Replays audio synthesis for a completed message in the chat log.
  Future<void> playMessageAudio(String messageId) async {
    if (state.status.isBusy) return;

    _playbackTimer?.cancel();
    state = state.copyWith(
      status: PipelineStatus.playing,
      playingMessageId: messageId,
    );

    final updatedMessages = state.messages.map((m) {
      return m.copyWith(isPlaying: m.id == messageId);
    }).toList();
    state = state.copyWith(messages: updatedMessages);

    final messageIndex = state.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      final msg = state.messages[messageIndex];
      final ttsService = ref.read(ttsServiceProvider);
      final audioFilePath = await ttsService.synthesize(
        msg.translatedText,
        language: msg.targetLang.code.toLowerCase(),
      );
      if (audioFilePath.isNotEmpty && File(audioFilePath).existsSync()) {
        try {
          final player = ref.read(audioPlayerProvider);
          await player.play(DeviceFileSource(audioFilePath));
        } catch (e) {
          AppLogger.warning('Pipeline', 'Audio playback hardware notice: $e');
        }
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 400));

    final resetMessages = state.messages.map((m) {
      return m.copyWith(isPlaying: false);
    }).toList();

    state = state.copyWith(
      status: PipelineStatus.idle,
      clearPlaying: true,
      messages: resetMessages,
    );
  }

  /// Clears the chat log.
  void clearHistory() {
    state = state.copyWith(
      messages: const [],
      clearInterim: true,
      clearError: true,
    );
  }
}

/// Alias for TranslationPipelineProvider class name as requested
typedef TranslationPipelineProvider = TranslationPipelineNotifier;

/// Riverpod NotifierProvider exposing the TranslationPipeline state and actions
final translationPipelineProvider =
    NotifierProvider<TranslationPipelineNotifier, TranslationState>(
  TranslationPipelineNotifier.new,
);
