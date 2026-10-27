import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../utils/app_logger.dart';
import '../../features/translation/domain/models/chat_message.dart';

/// Universal Speech-to-Text service powered by native device recognizers
/// (Google Speech Services on Android, Web Speech API on Chrome, SFSpeechRecognizer on iOS).
///
/// Keeps listening continuously while streaming live words until the user
/// explicitly taps the Stop button, ensuring it never closes prematurely on pauses.
class SpeechRecognitionService {
  final SpeechToText _stt = SpeechToText();
  bool _isInitialized = false;

  bool _isSessionActive = false;
  String _currentRecognizedText = '';
  ValueChanged<String>? _onResultCallback;
  VoidCallback? _onDoneCallback;

  bool get isListening => _stt.isListening;
  bool get isAvailable => _isInitialized && _stt.isAvailable;
  String get currentTranscript => _currentRecognizedText;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _stt.initialize(
        onError: (val) {
          AppLogger.warning('SpeechRecognitionService', 'Error: ${val.errorMsg}');
        },
        onStatus: (status) {
          AppLogger.info('SpeechRecognitionService', 'Status: $status');
        },
      );
      return _isInitialized;
    } catch (e) {
      AppLogger.warning('SpeechRecognitionService', 'Init error: $e');
      return false;
    }
  }

  /// Starts speech recognition in the target language (English or Japanese).
  ///
  /// Listens continuously in dictation mode without premature timeouts.
  Future<void> startListening({
    required TranslationLanguage language,
    required ValueChanged<String> onResult,
    required VoidCallback onDone,
  }) async {
    if (!_isInitialized) {
      final ready = await initialize();
      if (!ready) {
        throw StateError('Speech recognition unavailable or microphone permission denied.');
      }
    }

    _isSessionActive = true;
    _currentRecognizedText = '';
    _onResultCallback = onResult;
    _onDoneCallback = onDone;

    final localeId = language == TranslationLanguage.japanese ? 'ja_JP' : 'en_US';
    AppLogger.info('SpeechRecognitionService', 'Starting recognition with locale: $localeId');

    try {
      await _stt.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _currentRecognizedText = words;
            _onResultCallback?.call(words);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
          partialResults: true,
        ),
      );
    } catch (e) {
      AppLogger.warning('SpeechRecognitionService', 'Error during stt.listen: $e');
      rethrow;
    }
  }

  /// Manually stops voice listening and submits recognized speech.
  Future<void> stopListening() async {
    if (!_isSessionActive) return;
    _isSessionActive = false;

    try {
      await _stt.stop();
    } catch (_) {}

    final callback = _onDoneCallback;
    _onDoneCallback = null;
    callback?.call();
  }

  /// Cancels listening without processing.
  Future<void> cancelListening() async {
    _isSessionActive = false;
    _onDoneCallback = null;
    try {
      await _stt.cancel();
    } catch (_) {}
  }

  void dispose() {
    _isSessionActive = false;
    _stt.cancel();
  }
}
