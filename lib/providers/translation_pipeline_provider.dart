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
      await stopContinuousListening(processPending: false);
    } else {
      await startContinuousListening();
    }
  }

  /// Activates continuous 16kHz PCM streaming and Silero VAD loop.
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

      AppLogger.info('Pipeline', 'Continuous listening active.');
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
  Future<void> stopContinuousListening({bool processPending = true}) async {
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;

    final audioService = ref.read(audioServiceProvider);
    await audioService.stopContinuousStream();

    final asrService = ref.read(asrServiceProvider);
    Float32List? pendingSamples;
    if (processPending) {
      pendingSamples = asrService.flushSpeechSegment();
    }
    asrService.resetVad();

    state = state.copyWith(
      isContinuousListening: false,
      status: PipelineStatus.idle,
      clearActiveLanguage: true,
      clearInterim: true,
    );

    AppLogger.info('Pipeline', 'Continuous listening stopped.');

    if (processPending && pendingSamples != null && pendingSamples.isNotEmpty) {
      await _processEndpointedSpeech(pendingSamples);
    }
  }

  /// Immediately stop hearing / listening (Cancel).
  Future<void> stopHearing() async {
    await stopContinuousListening(processPending: false);
  }

  /// Tell the pipeline: "I'm done speaking, translate what I said now".
  Future<void> doneSpeakingNow() async {
    final asrService = ref.read(asrServiceProvider);
    final flushed = asrService.flushSpeechSegment();
    await stopContinuousListening(processPending: false);
    if (flushed != null && flushed.isNotEmpty) {
      await _processEndpointedSpeech(flushed);
    }
  }

  /// Start push-to-talk recording for a specific language.
  Future<void> startPushToTalk(TranslationLanguage language) async {
    try {
      if (state.isContinuousListening) {
        await stopContinuousListening(processPending: false);
      }
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
      await audioService.startRecording();
      state = state.copyWith(
        status: PipelineStatus.recording,
        activeLanguage: language,
        clearInterim: true,
        clearError: true,
      );
    } catch (e, st) {
      AppLogger.error('Pipeline', 'Failed startPushToTalk', e, st);
    }
  }

  /// Finish push-to-talk recording, transcribe, translate, and speak.
  Future<void> stopPushToTalk(TranslationLanguage language) async {
    if (state.status != PipelineStatus.recording) return;
    try {
      final audioService = ref.read(audioServiceProvider);
      final samples = await audioService.stopRecording();
      if (samples.isNotEmpty) {
        await _processEndpointedSpeech(samples, forcedLanguage: language);
      } else {
        state = state.copyWith(status: PipelineStatus.idle, clearActiveLanguage: true);
      }
    } catch (e, st) {
      AppLogger.error('Pipeline', 'Failed stopPushToTalk', e, st);
      state = state.copyWith(status: PipelineStatus.idle, clearActiveLanguage: true);
    }
  }

  /// Cancel push-to-talk recording without translating.
  Future<void> cancelPushToTalk() async {
    final audioService = ref.read(audioServiceProvider);
    await audioService.cancelRecording();
    state = state.copyWith(status: PipelineStatus.idle, clearActiveLanguage: true);
  }

  /// Handles real-time PCM audio chunks and feeds Silero VAD.
  void _handleIncomingAudioChunk(Float32List chunk) {
    if (!state.isContinuousListening || _isProcessingSegment) return;

    final asrService = ref.read(asrServiceProvider);
    asrService.acceptVadWaveform(chunk);

    if (state.status == PipelineStatus.idle) {
      state = state.copyWith(
        status: PipelineStatus.recording,
        activeLanguage: TranslationLanguage.english,
      );
    }

    if (asrService.hasSpeechSegment()) {
      final speechSamples = asrService.popSpeechSegment();
      if (speechSamples != null && speechSamples.isNotEmpty) {
        _processEndpointedSpeech(speechSamples);
      }
    }
  }

  /// Automatically triggered by VAD endpointing or manual Done Speaking: Transcribes -> Translates -> Synthesizes.
  Future<void> _processEndpointedSpeech(
    Float32List speechSamples, {
    TranslationLanguage? forcedLanguage,
  }) async {
    _isProcessingSegment = true;

    AppLogger.info(
      'Pipeline',
      'Processing speech segment with ${speechSamples.length} samples...',
    );

    try {
      // 1. Transcribe speech via Multilingual Whisper ASR
      state = state.copyWith(status: PipelineStatus.transcribing);
      final asrService = ref.read(asrServiceProvider);
      final asrResult = await asrService.transcribe(speechSamples);

      final validTranscript = asrResult.text.trim();
      if (validTranscript.isEmpty) {
        AppLogger.info('Pipeline', 'ASR returned empty transcript (no speech detected).');
        state = state.copyWith(
          status: PipelineStatus.idle,
          clearActiveLanguage: true,
          clearInterim: true,
        );
        return;
      }

      // Evaluate source and target languages
      final sourceLang = forcedLanguage ?? asrResult.translationLanguage;
      final targetLang = sourceLang.opposite;
      final isEnglish = sourceLang == TranslationLanguage.english;

      AppLogger.info(
        'Pipeline',
        'VAD Speech: "$validTranscript" (Detected: ${sourceLang.name}). Translating via Google ML Kit...',
      );

      // 2. Translate text via Google ML Kit NMT
      state = state.copyWith(
        status: PipelineStatus.translating,
        activeLanguage: sourceLang,
        interimTranscript: validTranscript,
      );

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

      AppLogger.info('Pipeline', 'Speech translated and added to history.');
    } catch (e, st) {
      AppLogger.error('Pipeline', 'Error during speech processing', e, st);
      state = state.copyWith(
        status: PipelineStatus.error,
        errorMessage: 'Speech processing error: $e',
      );
    } finally {
      _isProcessingSegment = false;
      final asrService = ref.read(asrServiceProvider);
      asrService.resetVad();
    }
  }

  /// Submits manual text input directly into the translation pipeline,
  /// translates via Google ML Kit, synthesizes voice, and reads aloud.
  Future<void> processText(
    String input, {
    TranslationLanguage? explicitSourceLang,
  }) async {
    final text = input.trim();
    if (text.isEmpty || state.status.isBusy) return;

    final sourceLang = explicitSourceLang ?? detectLanguage(text);
    final targetLang = sourceLang.opposite;
    final isEnglish = sourceLang == TranslationLanguage.english;

    AppLogger.info(
      'Pipeline',
      'Manual text input: "$text" (${sourceLang.name} -> ${targetLang.name}). Translating with Google ML Kit & synthesizing TTS.',
    );

    try {
      state = state.copyWith(
        status: PipelineStatus.translating,
        activeLanguage: sourceLang,
        interimTranscript: text,
        clearError: true,
      );

      // 1. Google ML Kit Translation
      final nmtService = ref.read(nmtServiceProvider);
      final translatedText = await nmtService.translate(
        text,
        sourceLang: isEnglish ? 'en' : 'ja',
        targetLang: isEnglish ? 'ja' : 'en',
      );

      // 2. TTS Voice Synthesis (Japanese TTS for EN->JA, English TTS for JA->EN)
      state = state.copyWith(
        status: PipelineStatus.synthesizing,
        interimTranslation: translatedText,
      );

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
      AppLogger.info('Pipeline', 'Text translation complete and read aloud.');
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
