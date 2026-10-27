import 'package:flutter_tts/flutter_tts.dart';

import '../utils/app_logger.dart';
import '../../features/translation/domain/models/chat_message.dart';

/// Universal Text-to-Speech service powered by native device TTS engines
/// (Android TextToSpeech, Web SpeechSynthesis, iOS AVSpeechSynthesizer).
class TtsPlayerService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isInitialized = true;
      AppLogger.info('TtsPlayerService', 'Universal TTS engine initialized.');
    } catch (e) {
      AppLogger.warning('TtsPlayerService', 'TTS initialization notice: $e');
    }
  }

  /// Speaks text aloud in the specified language (English or Japanese).
  Future<void> speak(String text, {required TranslationLanguage language}) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    if (!_isInitialized) {
      await initialize();
    }

    final langCode = language == TranslationLanguage.japanese ? 'ja-JP' : 'en-US';

    try {
      AppLogger.info('TtsPlayerService', 'Speaking [$langCode]: "$clean"');
      await _flutterTts.setLanguage(langCode);
      await _flutterTts.speak(clean);
    } catch (e) {
      AppLogger.warning('TtsPlayerService', 'Error during TTS speech playback: $e');
    }
  }

  /// Halts any active speech audio output.
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      AppLogger.warning('TtsPlayerService', 'Error stopping TTS: $e');
    }
  }

  Future<void> dispose() async {
    await stop();
  }
}
