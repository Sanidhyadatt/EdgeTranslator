import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../utils/app_logger.dart';
import '../../features/translation/data/datasources/sherpa_tts_service_impl.dart';
import '../../features/translation/domain/models/chat_message.dart';
import '../../features/translation/domain/services/tts_service.dart';

/// Universal Text-to-Speech player combining 100% offline ONNX VITS synthesis
/// (e.g. Melo-VITS for Japanese on all native platforms) with native OS TTS
/// (`flutter_tts`) for English / Web / fallback, supporting live speech speed control.
class TtsPlayerService {
  final FlutterTts _flutterTts = FlutterTts();
  final TtsService? _offlineTtsService;
  AudioPlayer? _audioPlayer;

  bool _isInitialized = false;
  bool _isSpeaking = false;
  double _speechRate = 1.0;
  int _speakToken = 0;
  Completer<void>? _playbackCompleter;
  StreamSubscription<void>? _completeSub;
  String? _lastTempWavPath;

  bool get isSpeaking => _isSpeaking;
  double get speechRate => _speechRate;

  TtsPlayerService({
    this._offlineTtsService,
    this._audioPlayer,
    double initialSpeechRate = 1.0,
  }) : _speechRate = initialSpeechRate.clamp(0.5, 1.5);

  /// Updates the default speech speed multiplier (`0.6` .. `1.3`, default `1.0`).
  void setSpeechRate(double rate) {
    _speechRate = rate.clamp(0.5, 1.5);
  }

  /// Converts a user-facing speed multiplier (`1.0` = normal, `0.8` = slow)
  /// to `flutter_tts`'s native `[0.0..1.0]` scale where `0.5` is normal speed.
  static double toFlutterTtsRate(double speed) {
    return (0.5 * speed).clamp(0.15, 1.0);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _flutterTts.setSpeechRate(toFlutterTtsRate(_speechRate));
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.awaitSpeakCompletion(true);
      _isInitialized = true;
      AppLogger.info('TtsPlayerService', 'TTS playback engine initialized.');
    } catch (e) {
      AppLogger.warning('TtsPlayerService', 'TTS initialization notice: $e');
    }
  }

  /// Speaks text aloud in the specified language (English or Japanese) at the
  /// configured [speechRate] and completes once playback finishes or is stopped.
  Future<void> speak(
    String text, {
    required TranslationLanguage language,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    await stop();

    final effectiveSpeed = _speechRate.clamp(0.5, 1.5);

    if (!_isInitialized) {
      await initialize();
    }

    final token = ++_speakToken;
    _isSpeaking = true;
    final shortCode = language == TranslationLanguage.japanese ? 'ja' : 'en';
    final localeCode = language == TranslationLanguage.japanese ? 'ja-JP' : 'en-US';

    try {
      // 1. Prefer offline ONNX TTS when native weights are active for the target language
      //    (critical on Windows where ja-JP OS TTS voices are usually not installed).
      final offline = _offlineTtsService;
      if (!kIsWeb && offline != null) {
        await offline.initialize();
        final canUseOffline = offline is! SherpaTtsServiceImpl || offline.isAvailableFor(shortCode);
        if (token != _speakToken) return;
        if (canUseOffline) {
          final wavPath = await offline.synthesize(
            clean,
            language: shortCode,
            speed: effectiveSpeed,
          );
          if (token != _speakToken) return;
          if (wavPath.isNotEmpty && File(wavPath).existsSync()) {
            await _playWavFile(wavPath, token);
            return;
          }
        }
      }

      // 2. Fallback / English native OS TTS via flutter_tts
      if (token != _speakToken) return;
      final ttsRate = toFlutterTtsRate(effectiveSpeed);
      AppLogger.info(
        'TtsPlayerService',
        'Speaking via OS TTS [$localeCode @ ${effectiveSpeed.toStringAsFixed(2)}x -> rate=$ttsRate]: "$clean"',
      );
      await _flutterTts.setLanguage(localeCode);
      await _flutterTts.setSpeechRate(ttsRate);
      await _flutterTts.speak(clean);
    } catch (e) {
      AppLogger.warning('TtsPlayerService', 'Error during TTS speech playback: $e');
    } finally {
      if (token == _speakToken) {
        _isSpeaking = false;
      }
    }
  }

  Future<void> _playWavFile(String wavPath, int token) async {
    _audioPlayer ??= AudioPlayer();
    final player = _audioPlayer!;

    await _completeSub?.cancel();
    _completeSub = null;
    if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
      _playbackCompleter!.complete();
    }

    final completer = Completer<void>();
    _playbackCompleter = completer;

    _completeSub = player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      AppLogger.info('TtsPlayerService', 'Playing offline WAV audio: $wavPath');
      await player.stop();
      if (token != _speakToken) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      _deleteLastTempWav();
      _lastTempWavPath = wavPath;
      await player.play(DeviceFileSource(wavPath));
      // Wait for completion (with a generous safety timeout in case platform event drops)
      await completer.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () {},
      );
    } finally {
      await _completeSub?.cancel();
      _completeSub = null;
      if (_playbackCompleter == completer) {
        _playbackCompleter = null;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  void _deleteLastTempWav() {
    final oldPath = _lastTempWavPath;
    _lastTempWavPath = null;
    if (oldPath != null) {
      try {
        final f = File(oldPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  /// Halts any active speech audio output immediately.
  Future<void> stop() async {
    _speakToken++;
    _isSpeaking = false;
    if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
      _playbackCompleter!.complete();
    }
    try {
      await _audioPlayer?.stop();
    } catch (e) {
      AppLogger.warning('TtsPlayerService', 'Error stopping AudioPlayer: $e');
    }
    try {
      await _flutterTts.stop();
    } catch (e) {
      AppLogger.warning('TtsPlayerService', 'Error stopping FlutterTts: $e');
    }
  }

  Future<void> dispose() async {
    await stop();
    await _completeSub?.cancel();
    _completeSub = null;
    try {
      await _audioPlayer?.dispose();
    } catch (_) {}
    _audioPlayer = null;
    _deleteLastTempWav();
  }
}
