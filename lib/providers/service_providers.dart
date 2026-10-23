import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../core/services/audio_service.dart';
import '../features/translation/data/datasources/mlkit_nmt_service_impl.dart';
import '../features/translation/data/datasources/model_loader.dart';
import '../features/translation/data/datasources/sherpa_asr_service_impl.dart';
import '../features/translation/data/datasources/sherpa_tts_service_impl.dart';
import '../features/translation/data/repositories/translation_repository.dart';
import '../features/translation/domain/services/asr_service.dart';
import '../features/translation/domain/services/nmt_service.dart';
import '../features/translation/domain/services/tts_service.dart';
import '../core/services/translation_service.dart';
export '../core/services/translation_service.dart';

/// Provider for microphone audio capture service (16kHz PCM Float32).
final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioServiceImpl();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for audio recording hardware abstraction.
final audioRecorderProvider = Provider.autoDispose<AudioRecorder>((ref) {
  final recorder = AudioRecorder();
  ref.onDispose(() => recorder.dispose());
  return recorder;
});

/// Provider for audio playback hardware abstraction.
final audioPlayerProvider = Provider.autoDispose<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(() => player.dispose());
  return player;
});

/// Provider for offline ASR speech-to-text service.
final asrServiceProvider = Provider<AsrService>((ref) {
  final modelLoader = ref.watch(modelLoaderProvider);
  final service = SherpaAsrServiceImpl(modelLoader: modelLoader);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for offline NMT neural machine translation service.
final nmtServiceProvider = Provider<NmtService>((ref) {
  final translationService = ref.watch(translationServiceProvider);
  final service = MlKitNmtServiceImpl(translationService: translationService);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for offline TTS speech synthesis service.
final ttsServiceProvider = Provider<TtsService>((ref) {
  final modelLoader = ref.watch(modelLoaderProvider);
  final service = SherpaTtsServiceImpl(modelLoader: modelLoader);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for local asset/model storage preparation.
final modelLoaderProvider = Provider<ModelLoader>((ref) {
  return const ModelLoader();
});

/// Provider coordinating offline ML repository lifecycle.
final translationRepositoryProvider = Provider<TranslationRepository>((ref) {
  final repo = TranslationRepository(
    asrService: ref.watch(asrServiceProvider),
    nmtService: ref.watch(nmtServiceProvider),
    ttsService: ref.watch(ttsServiceProvider),
    modelLoader: ref.watch(modelLoaderProvider),
  );
  ref.onDispose(() => repo.dispose());
  return repo;
});
