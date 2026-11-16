import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_logger.dart';
import '../core/utils/language_detector.dart';
import '../features/translation/domain/models/chat_message.dart';
import 'service_providers.dart';
import 'settings_provider.dart';

/// State of the translation pipeline with continuous VAD listening support.
class TranslationState {
  final PipelineStatus status;
  final bool isContinuousListening;
  final TranslationLanguage activeLanguage;
  final int recordingSeconds;
  final String? interimTranscript;
  final String? interimTranslation;
  final List<ChatMessage> messages;
  final String? errorMessage;
  final String? playingMessageId;

  const TranslationState({
    this.status = PipelineStatus.idle,
    this.isContinuousListening = false,
    this.activeLanguage = TranslationLanguage.english,
    this.recordingSeconds = 0,
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
    int? recordingSeconds,
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
      activeLanguage: clearActiveLanguage ? TranslationLanguage.english : (activeLanguage ?? this.activeLanguage),
      recordingSeconds: recordingSeconds ?? this.recordingSeconds,
      interimTranscript: clearInterim ? null : (interimTranscript ?? this.interimTranscript),
      interimTranslation: clearInterim ? null : (interimTranslation ?? this.interimTranslation),
      messages: messages ?? this.messages,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      playingMessageId: clearPlaying ? null : (playingMessageId ?? this.playingMessageId),
    );
  }
}

/// Riverpod Notifier managing Speech-to-Speech and Text-to-Text translation pipelines.
class TranslationPipelineNotifier extends Notifier<TranslationState> {
  StreamSubscription<Float32List>? _audioStreamSub;
  Timer? _recordingTimer;
  bool _isProcessingSegment = false;
  bool _isFinishingVoiceSpeech = false;
  int _playbackRunId = 0;

  @override
  TranslationState build() {
    ref.onDispose(() {
      _audioStreamSub?.cancel();
      _recordingTimer?.cancel();
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

  /// Sets the active translation language direction.
  void setLanguage(TranslationLanguage lang) {
    state = state.copyWith(activeLanguage: lang);
  }

  /// Toggles the active translation language direction between English and Japanese.
  void toggleLanguage() {
    final next = state.activeLanguage == TranslationLanguage.english
        ? TranslationLanguage.japanese
        : TranslationLanguage.english;
    state = state.copyWith(activeLanguage: next);
  }

  /// Unified toggle to start/stop listening to voice speech.
  Future<void> toggleVoiceListening() async {
    if (state.status == PipelineStatus.recording) {
      await stopVoiceListening();
    } else if (!state.status.isProcessing) {
      await startVoiceListening();
    }
  }

  /// Starts voice listening and keeps recording until the user explicitly taps Stop.
  ///
  /// On native platforms, captures 16kHz PCM audio continuously via [AudioService]
  /// for offline Whisper ASR without premature silence timeouts.
  /// On Web, falls back to browser speech recognition.
  Future<void> startVoiceListening() async {
    // Halt any ongoing TTS playback before opening microphone
    if (state.status == PipelineStatus.playing) {
      await stopAudioPlayback();
    }

    if (!kIsWeb) {
      await _startOfflineRecorderListening();
      return;
    }

    final lang = state.activeLanguage;
    final sttService = ref.read(speechRecognitionServiceProvider);

    state = state.copyWith(
      status: PipelineStatus.recording,
      recordingSeconds: 0,
      interimTranscript: '',
      clearError: true,
    );
    _startRecordingTimer();

    try {
      await sttService.startListening(
        language: lang,
        onResult: (text) {
          state = state.copyWith(interimTranscript: text);
        },
        onDone: () async {
          await _finishVoiceSpeech();
        },
      );
    } catch (e) {
      AppLogger.warning('Pipeline', 'SpeechRecognitionService notice: $e');
      _stopRecordingTimer();
      state = state.copyWith(
        status: PipelineStatus.error,
        recordingSeconds: 0,
        errorMessage: 'Speech recognition unavailable: $e',
      );
    }
  }

  Future<void> _startOfflineRecorderListening() async {
    try {
      if (state.isContinuousListening) {
        await stopContinuousListening(processPending: false);
      }
      final audioService = ref.read(audioServiceProvider);
      final permitted = await audioService.hasPermission();
      if (!permitted) {
        state = state.copyWith(
          status: PipelineStatus.error,
          recordingSeconds: 0,
          errorMessage: 'Microphone permission not granted.',
        );
        return;
      }

      final asrService = ref.read(asrServiceProvider);
      await asrService.initialize();
      await audioService.startRecording();

      state = state.copyWith(
        status: PipelineStatus.recording,
        recordingSeconds: 0,
        clearInterim: true,
        clearError: true,
      );
      _startRecordingTimer();
      AppLogger.info('Pipeline', 'Listening continuously until Stop is pressed...');
    } catch (e, st) {
      _stopRecordingTimer();
      AppLogger.error('Pipeline', 'Failed to start microphone recording', e, st);
      state = state.copyWith(
        status: PipelineStatus.error,
        recordingSeconds: 0,
        errorMessage: 'Could not start microphone: $e',
      );
    }
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.status == PipelineStatus.recording) {
        state = state.copyWith(recordingSeconds: state.recordingSeconds + 1);
      } else {
        _stopRecordingTimer();
      }
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  /// Stops voice listening and translates whatever was spoken into the appropriate language.
  Future<void> stopVoiceListening() async {
    _stopRecordingTimer();
    final audioService = ref.read(audioServiceProvider);

    if (!kIsWeb && audioService.isRecording) {
      try {
        final samples = await audioService.stopRecording();
        state = state.copyWith(recordingSeconds: 0);
        if (samples.length < 3200) {
          state = state.copyWith(
            status: PipelineStatus.idle,
            clearInterim: true,
            errorMessage: 'Recording too short. Speak clearly and then press Stop.',
          );
          return;
        }
        await _processEndpointedSpeech(samples);
      } catch (e, st) {
        AppLogger.error('Pipeline', 'Failed stopping voice recording', e, st);
        state = state.copyWith(
          status: PipelineStatus.error,
          recordingSeconds: 0,
          errorMessage: 'Failed processing recorded audio: $e',
        );
      }
      return;
    }

    final sttService = ref.read(speechRecognitionServiceProvider);
    await sttService.stopListening();
    await _finishVoiceSpeech();
  }

  /// Cancels active voice recording and discards captured audio without translating.
  Future<void> cancelVoiceListening() async {
    _stopRecordingTimer();
    final audioService = ref.read(audioServiceProvider);
    if (audioService.isRecording) {
      await audioService.cancelRecording();
    }
    if (kIsWeb) {
      await ref.read(speechRecognitionServiceProvider).cancelListening();
    }
    state = state.copyWith(
      status: PipelineStatus.idle,
      recordingSeconds: 0,
      clearInterim: true,
      clearError: true,
    );
  }

  Future<void> _finishVoiceSpeech() async {
    if (_isFinishingVoiceSpeech) return;
    _isFinishingVoiceSpeech = true;
    _stopRecordingTimer();
    try {
      final sttService = ref.read(speechRecognitionServiceProvider);
      var transcript = state.interimTranscript?.trim() ?? '';
      if (transcript.isEmpty) {
        transcript = sttService.currentTranscript.trim();
      }

      if (transcript.isEmpty) {
        state = state.copyWith(
          status: PipelineStatus.idle,
          recordingSeconds: 0,
          clearInterim: true,
        );
        return;
      }

      state = state.copyWith(recordingSeconds: 0, clearInterim: true);
      await processText(transcript);
    } finally {
      _isFinishingVoiceSpeech = false;
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

  /// Transcribes recorded speech via Whisper and translates to the appropriate target language.
  /// Generated translations are displayed in chat and spoken when requested by the user.
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
      state = state.copyWith(status: PipelineStatus.transcribing, clearError: true);
      final asrService = ref.read(asrServiceProvider);
      final asrResult = await asrService.transcribe(speechSamples);

      final validTranscript = asrResult.text.trim();
      if (validTranscript.isEmpty) {
        AppLogger.info('Pipeline', 'ASR returned empty transcript (no speech detected).');
        state = state.copyWith(
          status: PipelineStatus.idle,
          clearInterim: true,
          errorMessage: 'No speech detected. Please speak clearly into the microphone.',
        );
        return;
      }

      // Always resolve source language from the actual recognized script/language
      // so English speech translates to Japanese and Japanese speech translates to English.
      final detectedFromScript = detectLanguage(validTranscript);
      final sourceLang = forcedLanguage ??
          (detectedFromScript == TranslationLanguage.japanese || asrResult.isJapanese
              ? TranslationLanguage.japanese
              : TranslationLanguage.english);
      final targetLang = sourceLang.opposite;
      final isEnglish = sourceLang == TranslationLanguage.english;
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();

      AppLogger.info(
        'Pipeline',
        'ASR Speech: "$validTranscript" (Detected: ${sourceLang.name} -> ${targetLang.name}). Translating on-device...',
      );

      // Optimistically append ChatMessage so UI shows user transcript immediately
      final initialMessage = ChatMessage(
        id: messageId,
        sourceLang: sourceLang,
        targetLang: targetLang,
        originalText: validTranscript,
        translatedText: 'Translating...',
        timestamp: DateTime.now(),
      );

      // 2. Translate text via on-device NMT
      state = state.copyWith(
        status: PipelineStatus.translating,
        activeLanguage: sourceLang,
        interimTranscript: validTranscript,
        messages: [...state.messages, initialMessage],
        clearError: true,
      );

      final nmtService = ref.read(nmtServiceProvider);
      final translatedText = await nmtService.translate(
        validTranscript,
        sourceLang: isEnglish ? 'en' : 'ja',
        targetLang: isEnglish ? 'ja' : 'en',
      );

      // Update message with actual translated text in chat log immediately
      final updatedMessages = state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(translatedText: translatedText);
        }
        return m;
      }).toList();

      state = state.copyWith(
        status: PipelineStatus.idle,
        messages: updatedMessages,
        clearInterim: true,
      );

      AppLogger.info('Pipeline', 'Speech transcribed and translated into chat history.');
    } catch (e, st) {
      AppLogger.error('Pipeline', 'Error during speech processing', e, st);
      state = state.copyWith(
        status: PipelineStatus.error,
        clearInterim: true,
        errorMessage: 'Speech processing error: $e',
      );
    } finally {
      _isProcessingSegment = false;
      final asrService = ref.read(asrServiceProvider);
      asrService.resetVad();
    }
  }

  /// Submits manual text input directly into the translation pipeline and
  /// generates the translation on-device. Speech playback is triggered when requested.
  Future<void> processText(
    String input, {
    TranslationLanguage? explicitSourceLang,
  }) async {
    final text = input.trim();
    if (text.isEmpty || state.status.isRecording || state.status.isProcessing) return;

    if (state.status == PipelineStatus.playing) {
      await stopAudioPlayback();
    }

    final sourceLang = explicitSourceLang ?? detectLanguage(text);
    final targetLang = sourceLang.opposite;
    final isEnglish = sourceLang == TranslationLanguage.english;
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();

    AppLogger.info(
      'Pipeline',
      'Text input: "$text" (${sourceLang.name} -> ${targetLang.name}). Translating with on-device NMT.',
    );

    // Optimistically create and append ChatMessage right away so UI updates immediately
    final initialMessage = ChatMessage(
      id: messageId,
      sourceLang: sourceLang,
      targetLang: targetLang,
      originalText: text,
      translatedText: 'Translating...',
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      status: PipelineStatus.translating,
      activeLanguage: sourceLang,
      interimTranscript: text,
      messages: [...state.messages, initialMessage],
      clearError: true,
    );

    try {
      final nmtService = ref.read(nmtServiceProvider);
      final translatedText = await nmtService.translate(
        text,
        sourceLang: isEnglish ? 'en' : 'ja',
        targetLang: isEnglish ? 'ja' : 'en',
      );

      final updatedMessages = state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(translatedText: translatedText);
        }
        return m;
      }).toList();

      state = state.copyWith(
        status: PipelineStatus.idle,
        messages: updatedMessages,
        clearInterim: true,
      );

      AppLogger.info('Pipeline', 'Text translation complete.');
    } catch (e, st) {
      AppLogger.error('Pipeline', 'Manual text translation error', e, st);
      final failedMessages = state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(translatedText: '[Translation failed: $e]');
        }
        return m;
      }).toList();
      state = state.copyWith(
        status: PipelineStatus.error,
        messages: failedMessages,
        errorMessage: 'Translation error: $e',
        clearInterim: true,
      );
    }
  }

  /// Speaks a message's translated (or [speakOriginal] source) text aloud at
  /// [speed] (defaults to [settingsProvider] speechRate), or stops if that
  /// message is already playing.
  Future<void> playMessageAudio(
    String messageId, {
    bool speakOriginal = false,
    double? speed,
  }) async {
    if (state.status.isRecording || state.status.isProcessing) return;

    if (!speakOriginal &&
        state.status == PipelineStatus.playing &&
        state.playingMessageId == messageId) {
      await stopAudioPlayback();
      return;
    }

    final messageIndex = state.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    final msg = state.messages[messageIndex];
    final spokenText = speakOriginal ? msg.originalText : msg.translatedText;
    final spokenLang = speakOriginal ? msg.sourceLang : msg.targetLang;
    if (spokenText.trim().isEmpty || spokenText == 'Translating...') {
      return;
    }

    final runId = ++_playbackRunId;
    final effectiveSpeed = speed ?? ref.read(settingsProvider).speechRate;
    final updatedMessages = state.messages.map((m) {
      return m.copyWith(isPlaying: !speakOriginal && m.id == messageId);
    }).toList();

    state = state.copyWith(
      status: PipelineStatus.playing,
      playingMessageId: speakOriginal ? null : messageId,
      clearPlaying: speakOriginal,
      messages: updatedMessages,
      clearError: true,
    );

    try {
      final ttsPlayer = ref.read(ttsPlayerServiceProvider);
      ttsPlayer.setSpeechRate(effectiveSpeed);
      await ttsPlayer.speak(spokenText, language: spokenLang);
    } catch (e) {
      AppLogger.warning('Pipeline', 'Audio playback notice: $e');
    } finally {
      if (runId == _playbackRunId) {
        final resetMessages = state.messages.map((m) {
          return m.copyWith(isPlaying: false);
        }).toList();
        state = state.copyWith(
          status: PipelineStatus.idle,
          clearPlaying: true,
          messages: resetMessages,
        );
      }
    }
  }

  /// Speaks an arbitrary preview phrase (e.g. from Settings speech-rate test)
  /// without polluting the chat history, or stops if already playing preview.
  Future<void> speakPreview(
    String text, {
    required TranslationLanguage language,
    double? speed,
  }) async {
    if (state.status.isRecording || state.status.isProcessing) return;

    if (state.status == PipelineStatus.playing && state.playingMessageId == null) {
      await stopAudioPlayback();
      return;
    }

    final runId = ++_playbackRunId;
    final effectiveSpeed = speed ?? ref.read(settingsProvider).speechRate;
    final resetMessages = state.messages.map((m) => m.copyWith(isPlaying: false)).toList();

    state = state.copyWith(
      status: PipelineStatus.playing,
      clearPlaying: true,
      messages: resetMessages,
      clearError: true,
    );

    try {
      final ttsPlayer = ref.read(ttsPlayerServiceProvider);
      ttsPlayer.setSpeechRate(effectiveSpeed);
      await ttsPlayer.speak(text, language: language);
    } catch (e) {
      AppLogger.warning('Pipeline', 'Preview playback notice: $e');
    } finally {
      if (runId == _playbackRunId) {
        state = state.copyWith(
          status: PipelineStatus.idle,
          clearPlaying: true,
        );
      }
    }
  }

  /// Dismisses any visible notice/error message and returns error state to idle.
  void dismissError() {
    state = state.copyWith(
      status: state.status == PipelineStatus.error ? PipelineStatus.idle : state.status,
      clearError: true,
    );
  }

  /// Stops active speech playback immediately.
  Future<void> stopAudioPlayback() async {
    _playbackRunId++;
    try {
      await ref.read(ttsPlayerServiceProvider).stop();
    } catch (_) {}
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
