/// Application-wide constants for IKHO.
class AppConstants {
  AppConstants._();

  static const String appName = 'IKHO';
  static const String appTagline = '100% Offline Real-Time Voice Translation';
  static const String washiWallpaperAsset = 'assets/images/washi_wallpaper.jpg';

  // Audio Configuration
  static const int audioSampleRate = 16000;
  static const int audioChannels = 1;

  // Language Defaults
  static const String defaultSourceLanguage = 'English';
  static const String defaultSourceCode = 'en';
  static const String defaultTargetLanguage = 'Japanese';
  static const String defaultTargetCode = 'ja';

  // On-device AI Pack Model Paths (delivered via Android :ai_models install-time pack)
  static const String aiModelsPackAssetRoot = 'models';
  static const String sileroVadFile = 'silero_vad.onnx';

  // Multilingual SenseVoice Small (INT8) ASR Model Files
  static const String senseVoiceModelFile = 'asr/sense-voice.int8.onnx';
  static const String senseVoiceTokensFile = 'asr/sense-voice-tokens.txt';

  // Legacy Whisper ASR fallback filenames
  static const String whisperEncoderFile = 'tiny-encoder.int8.onnx';
  static const String whisperDecoderFile = 'tiny-decoder.int8.onnx';
  static const String whisperTokensFile = 'tiny-tokens.txt';

  // MarianMT NMT Model Subdirectories (within local models directory)
  static const String nmtEnJaSubdir = 'nmt_en_ja';
  static const String nmtJaEnSubdir = 'nmt_ja_en';

  // Sherpa / ORT TTS Model Subdirectories (within local models directory)
  static const String ttsEnSubdir = 'tts_en';
  static const String ttsJaSubdir = 'tts_ja';
}
