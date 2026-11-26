import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

import '../constants/app_constants.dart';
import '../utils/app_logger.dart';

/// Contract for audio capture supporting both one-shot buffers and continuous streaming for VAD.
abstract class AudioService {
  Future<bool> hasPermission();
  Future<void> startRecording();
  Future<Float32List> stopRecording();
  Future<void> cancelRecording();
  bool get isRecording;

  /// Continuous streaming buffer for real-time Voice Activity Detection (VAD).
  Stream<Float32List> get audioStream;
  Future<void> startContinuousStream();
  Future<void> stopContinuousStream();
  bool get isStreaming;

  void dispose();
}

/// Implementation of AudioService using the record package for continuous 16kHz PCM Float32 streaming.
class AudioServiceImpl implements AudioService {
  final AudioRecorder _recorder;
  final List<int> _pcmBuffer = [];
  final StreamController<Float32List> _streamController = StreamController<Float32List>.broadcast();
  StreamSubscription<Uint8List>? _recordSub;

  int? _streamPendingByte;
  bool _recording = false;
  bool _streaming = false;

  AudioServiceImpl({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  @override
  bool get isRecording => _recording;

  @override
  bool get isStreaming => _streaming;

  @override
  Stream<Float32List> get audioStream => _streamController.stream;

  @override
  Future<bool> hasPermission() async {
    return _recorder.hasPermission();
  }

  /// Opens a 16kHz mono PCM stream with hardware AGC, noise suppression,
  /// and Android's voice-recognition mic path, falling back if unsupported.
  Future<Stream<Uint8List>> _openSpeechPcmStream() async {
    const enhancedConfig = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: AppConstants.audioSampleRate,
      numChannels: AppConstants.audioChannels,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
      androidConfig: AndroidRecordConfig(
        audioSource: AndroidAudioSource.voiceRecognition,
      ),
    );
    try {
      return await _recorder.startStream(enhancedConfig);
    } catch (e) {
      AppLogger.warning(
        'AudioService',
        'Enhanced speech RecordConfig unavailable ($e); retrying standard 16kHz PCM.',
      );
      const fallbackConfig = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AppConstants.audioSampleRate,
        numChannels: AppConstants.audioChannels,
      );
      return await _recorder.startStream(fallbackConfig);
    }
  }

  Float32List _decodePcm16ToFloat32(Uint8List bytes, {bool carryOddByte = false}) {
    Uint8List aligned = bytes;
    if (carryOddByte && _streamPendingByte != null) {
      aligned = Uint8List(bytes.length + 1);
      aligned[0] = _streamPendingByte!;
      aligned.setAll(1, bytes);
      _streamPendingByte = null;
    }

    var usableLen = aligned.lengthInBytes;
    if (usableLen.isOdd) {
      if (carryOddByte) {
        _streamPendingByte = aligned[usableLen - 1];
      }
      usableLen -= 1;
    }
    if (usableLen < 2) return Float32List(0);

    final byteData = ByteData.sublistView(aligned, 0, usableLen);
    final sampleCount = usableLen ~/ 2;
    final floatSamples = Float32List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      floatSamples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return floatSamples;
  }

  @override
  Future<void> startContinuousStream() async {
    if (_streaming) return;

    final permitted = await hasPermission();
    if (!permitted) {
      throw StateError('Microphone permission not granted.');
    }

    _streamPendingByte = null;
    await _recordSub?.cancel();

    try {
      final rawStream = await _openSpeechPcmStream();
      _streaming = true;
      AppLogger.info('AudioService', 'Continuous 16kHz speech-enhanced PCM stream started.');

      _recordSub = rawStream.listen(
        (chunk) {
          if (chunk.isEmpty) return;
          final floatSamples = _decodePcm16ToFloat32(chunk, carryOddByte: true);
          if (floatSamples.isNotEmpty && !_streamController.isClosed) {
            _streamController.add(floatSamples);
          }
        },
        onError: (err, st) {
          AppLogger.error('AudioService', 'Error in continuous audio stream', err, st);
        },
        cancelOnError: false,
      );
    } catch (e, st) {
      AppLogger.error('AudioService', 'Failed to start continuous audio stream', e, st);
      _streaming = false;
      rethrow;
    }
  }

  @override
  Future<void> stopContinuousStream() async {
    if (!_streaming) return;
    _streaming = false;
    _streamPendingByte = null;
    await _recordSub?.cancel();
    _recordSub = null;

    try {
      await _recorder.stop();
    } catch (e) {
      AppLogger.error('AudioService', 'Error stopping continuous recorder', e);
    }
    AppLogger.info('AudioService', 'Continuous audio stream stopped.');
  }

  @override
  Future<void> startRecording() async {
    if (_recording) return;

    final permitted = await hasPermission();
    if (!permitted) {
      throw StateError('Microphone permission not granted.');
    }

    _pcmBuffer.clear();
    await _recordSub?.cancel();

    try {
      final audioStream = await _openSpeechPcmStream();
      _recording = true;
      AppLogger.info('AudioService', 'Audio stream started (16000Hz, mono, PCM16, voice-enhanced).');

      _recordSub = audioStream.listen(
        (chunk) {
          if (chunk.isNotEmpty) {
            _pcmBuffer.addAll(chunk);
          }
        },
        onError: (err, st) {
          AppLogger.error('AudioService', 'Error in audio stream', err, st);
        },
        cancelOnError: false,
      );
    } catch (e, st) {
      AppLogger.error('AudioService', 'Failed to start audio stream', e, st);
      _recording = false;
      rethrow;
    }
  }

  @override
  Future<Float32List> stopRecording() async {
    if (!_recording) {
      return Float32List(0);
    }

    _recording = false;
    await _recordSub?.cancel();
    _recordSub = null;

    try {
      await _recorder.stop();
    } catch (e) {
      AppLogger.error('AudioService', 'Error stopping recorder', e);
    }

    final totalBytes = _pcmBuffer.length;
    AppLogger.info('AudioService', 'Captured $totalBytes bytes of PCM audio.');

    final floatSamples = _decodePcm16ToFloat32(Uint8List.fromList(_pcmBuffer));
    _pcmBuffer.clear();
    return floatSamples;
  }

  @override
  Future<void> cancelRecording() async {
    _recording = false;
    _streamPendingByte = null;
    await _recordSub?.cancel();
    _recordSub = null;
    _pcmBuffer.clear();
    try {
      await _recorder.stop();
    } catch (_) {}
    AppLogger.info('AudioService', 'Recording cancelled.');
  }

  @override
  void dispose() {
    _recordSub?.cancel();
    _streamController.close();
    _recorder.dispose();
  }
}
