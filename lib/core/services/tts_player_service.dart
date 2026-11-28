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
/// (`flutter_tts`) for English / Web / fallback, supporting live speech speed control
/// and pipelined sentence-by-sentence playback.
class TtsPlayerService {
  final FlutterTts _flutterTts = FlutterTts();
  final TtsService? _offlineTtsService;
  AudioPlayer? _audioPlayer;

  bool _isInitialized = false;
  bool _isSpeaking = false;
  bool _osSpeakError = false;
  double _speechRate = 1.0;
  int _speakToken = 0;
  Completer<void>? _playbackCompleter;
  StreamSubscription<void>? _completeSub;
  String? _lastTempWavPath;

  final Map<String, bool> _localOsVoiceChecked = {};
  final Map<String, bool> _hasLocalOsVoice = {};
  final Map<String, Map<String, String>> _bestLocalOsVoice = {};

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
      _flutterTts.setErrorHandler((msg) {
        _osSpeakError = true;
        AppLogger.warning('TtsPlayerService', 'OS TTS error callback: $msg');
        unawaited(_flutterTts.stop());
      });
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

  /// Checks whether an installed, offline-capable OS TTS voice exists for [shortCode]
  /// on mobile (Android/iOS), selecting the highest-quality local voice available.
  Future<bool> _ensureLocalOsVoice(String shortCode, String localeCode) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return false;
    if (_localOsVoiceChecked[shortCode] == true) {
      return _hasLocalOsVoice[shortCode] ?? false;
    }

    var available = false;
    try {
      final rawVoices = await _flutterTts.getVoices;
      if (rawVoices is List) {
        Map<String, String>? bestVoice;
        var bestScore = -1;
        for (final entry in rawVoices) {
          if (entry is! Map) continue;
          final name = entry['name']?.toString() ?? '';
          final localeRaw = entry['locale']?.toString() ?? '';
          final localeNorm = localeRaw.toLowerCase().replaceAll('_', '-');
          final matchesLang = localeNorm.startsWith(shortCode) ||
              (shortCode == 'ja' && localeNorm.startsWith('jpn'));
          if (!matchesLang || name.isEmpty) continue;

          final netReq = entry['network_required']?.toString() ?? '0';
          final features = entry['features']?.toString().toLowerCase() ?? '';
          if (netReq == '1' || features.contains('notinstalled')) continue;

          final quality = entry['quality']?.toString().toLowerCase() ?? '';
          var score = switch (quality) {
            'very high' => 30,
            'high' => 20,
            'normal' => 10,
            _ => 5,
          };
          if (name.toLowerCase().contains('local')) score += 5;
          if (score > bestScore) {
            bestScore = score;
            bestVoice = {'name': name, 'locale': localeRaw};
          }
        }
        if (bestVoice != null) {
          _bestLocalOsVoice[shortCode] = bestVoice;
          available = true;
        }
      }

      if (!available) {
        final installed = Platform.isAndroid
            ? await _flutterTts.isLanguageInstalled(localeCode)
            : await _flutterTts.isLanguageAvailable(localeCode);
        available = installed == true;
      }
    } catch (e) {
      AppLogger.warning('TtsPlayerService', 'Local OS voice probe notice ($localeCode): $e');
    }

    _localOsVoiceChecked[shortCode] = true;
    _hasLocalOsVoice[shortCode] = available;
    AppLogger.info(
      'TtsPlayerService',
      'OS local voice [$localeCode]: available=$available voice=${_bestLocalOsVoice[shortCode]?['name'] ?? 'default'}',
    );
    return available;
  }

  /// Pre-warms TTS for [text] in the background right after translation finishes
  /// so tapping Speak responds immediately even when falling back to ONNX TTS.
  Future<void> prewarmPhrase(
    String text, {
    required TranslationLanguage language,
    double? speed,
  }) async {
    if (kIsWeb) return;
    final clean = text.trim();
    if (clean.isEmpty) return;

    await initialize();

    final shortCode = language == TranslationLanguage.japanese ? 'ja' : 'en';
    final localeCode = language == TranslationLanguage.japanese ? 'ja-JP' : 'en-US';
    if ((Platform.isAndroid || Platform.isIOS) &&
        await _ensureLocalOsVoice(shortCode, localeCode)) {
      return;
    }

    final offline = _offlineTtsService;
    if (offline == null) return;
    final sentences = _splitTtsSentences(clean);
    final first = sentences.isEmpty ? clean : sentences.first;
    final effectiveSpeed = (speed ?? _speechRate).clamp(0.5, 1.5);
    try {
      await offline.synthesize(first, language: shortCode, speed: effectiveSpeed);
    } catch (_) {}
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
      // 1. On Android/iOS, prefer an installed local OS voice first for natural
      //    Tokyo pitch accent and instant (<80ms) playback; fall back seamlessly
      //    to offline ONNX TTS if no local voice is installed or playback errors.
      final offline = _offlineTtsService;
      final useMobileOsFirst = !kIsWeb &&
          (Platform.isAndroid || Platform.isIOS) &&
          (offline == null || offline is SherpaTtsServiceImpl);
      if (useMobileOsFirst && await _ensureLocalOsVoice(shortCode, localeCode)) {
        if (token != _speakToken) return;
        final ttsRate = toFlutterTtsRate(effectiveSpeed);
        final preferredVoice = _bestLocalOsVoice[shortCode];
        if (preferredVoice != null) {
          try {
            await _flutterTts.setVoice(preferredVoice);
          } catch (_) {}
        }
        await _flutterTts.setLanguage(localeCode);
        await _flutterTts.setSpeechRate(ttsRate);
        _osSpeakError = false;
        AppLogger.info(
          'TtsPlayerService',
          'Speaking via local OS TTS [$localeCode @ ${effectiveSpeed.toStringAsFixed(2)}x]: "$clean"',
        );
        final res = await _flutterTts.speak(clean);
        if (!_osSpeakError && (res == 1 || res == true || token != _speakToken)) {
          return;
        }
        AppLogger.warning(
          'TtsPlayerService',
          'Local OS TTS failed for $localeCode (res=$res); falling back to offline ONNX TTS.',
        );
        _hasLocalOsVoice[shortCode] = false;
      }

      // 2. Offline ONNX TTS (Windows/Desktop, tests, or Android/iOS without local OS voice)
      if (!kIsWeb && offline != null) {
        final managesTemp = offline is SherpaTtsServiceImpl && offline.managesTempFiles;
        if (offline is SherpaTtsServiceImpl) {
          await offline.initializeForLanguage(shortCode);
        } else {
          await offline.initialize();
        }
        final canUseOffline = offline is! SherpaTtsServiceImpl || offline.isAvailableFor(shortCode);
        if (token != _speakToken) return;
        if (canUseOffline) {
          final sentences = _splitTtsSentences(clean);
          final played = await _speakPipelinedOffline(
            offline,
            sentences.isEmpty ? [clean] : sentences,
            language: shortCode,
            speed: effectiveSpeed,
            token: token,
            managesTempFiles: managesTemp,
          );
          if (played || token != _speakToken) return;
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

  /// Synthesizes sentence `i + 1` in parallel while sentence `i` plays back.
  Future<bool> _speakPipelinedOffline(
    TtsService offline,
    List<String> sentences, {
    required String language,
    required double speed,
    required int token,
    required bool managesTempFiles,
  }) async {
    var playedAny = false;
    Future<String> currentFuture = offline.synthesize(
      sentences[0],
      language: language,
      speed: speed,
    );

    for (var i = 0; i < sentences.length; i++) {
      final wavPath = await currentFuture;
      if (token != _speakToken) return playedAny;

      Future<String>? nextFuture;
      if (i + 1 < sentences.length) {
        nextFuture = offline.synthesize(
          sentences[i + 1],
          language: language,
          speed: speed,
        );
      }

      if (wavPath.isNotEmpty && File(wavPath).existsSync()) {
        playedAny = true;
        await _playWavFile(wavPath, token, manageTempCleanup: !managesTempFiles);
      }
      if (token != _speakToken) return playedAny;

      if (nextFuture != null) {
        currentFuture = nextFuture;
      }
    }
    return playedAny;
  }

  List<String> _splitTtsSentences(String text) {
    final parts = text
        .split(RegExp(r'(?<=[。！？!?])\s*|(?<=[.;])\s+(?=[A-Za-z0-9\u3040-\u9FFF])'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? [text] : parts;
  }

  Future<void> _playWavFile(
    String wavPath,
    int token, {
    required bool manageTempCleanup,
  }) async {
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
      if (manageTempCleanup) {
        _deleteLastTempWav();
        _lastTempWavPath = wavPath;
      } else {
        _lastTempWavPath = null;
      }
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
