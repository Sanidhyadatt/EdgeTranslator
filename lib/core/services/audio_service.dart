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

  @override
  Future<void> startContinuousStream() async {
    if (_streaming) return;

    final permitted = await hasPermission();
    if (!permitted) {
      throw StateError('Microphone permission not granted.');
    }

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: AppConstants.audioSampleRate,
      numChannels: AppConstants.audioChannels,
    );

    try {
      final rawStream = await _recorder.startStream(config);
      _streaming = true;
      AppLogger.info('AudioService', 'Continuous 16kHz PCM audio stream started.');

      _recordSub = rawStream.listen(
        (chunk) {
          if (chunk.isEmpty) return;
          final byteData = ByteData.sublistView(chunk);
          final sampleCount = chunk.lengthInBytes ~/ 2;
          final floatSamples = Float32List(sampleCount);

          for (int i = 0; i < sampleCount; i++) {
            final int16Sample = byteData.getInt16(i * 2, Endian.little);
            floatSamples[i] = int16Sample / 32768.0;
          }

          if (!_streamController.isClosed) {
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

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: AppConstants.audioSampleRate,
      numChannels: AppConstants.audioChannels,
    );

    try {
      final audioStream = await _recorder.startStream(config);
      _recording = true;
      AppLogger.info('AudioService', 'Audio stream started (16000Hz, mono, PCM16).');

      _recordSub = audioStream.listen(
        (chunk) {
          _pcmBuffer.addAll(chunk);
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

    final byteData = ByteData.sublistView(Uint8List.fromList(_pcmBuffer));
    final sampleCount = totalBytes ~/ 2;
    final floatSamples = Float32List(sampleCount);

    for (int i = 0; i < sampleCount; i++) {
      final int16Sample = byteData.getInt16(i * 2, Endian.little);
      floatSamples[i] = int16Sample / 32768.0;
    }

    _pcmBuffer.clear();
    return floatSamples;
  }

  @override
  Future<void> cancelRecording() async {
    _recording = false;
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
