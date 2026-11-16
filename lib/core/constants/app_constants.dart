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

  // Model Asset Paths
  static const String modelsBasePath = 'assets/models';
  static const String asrModelDir = '$modelsBasePath/asr';
  static const String nmtModelDir = '$modelsBasePath/nmt';
  static const String ttsModelDir = '$modelsBasePath/tts';

  // Multilingual Whisper ASR Model Files
  static const String whisperEncoderFile = 'tiny-encoder.int8.onnx';
  static const String whisperDecoderFile = 'tiny-decoder.int8.onnx';
  static const String whisperTokensFile = 'tiny-tokens.txt';

  static const String whisperEncoderAssetPath = '$modelsBasePath/$whisperEncoderFile';
  static const String whisperDecoderAssetPath = '$modelsBasePath/$whisperDecoderFile';
  static const String whisperTokensAssetPath = '$modelsBasePath/$whisperTokensFile';

  // MarianMT NMT Model Paths
  static const String nmtEnJaDir = '$modelsBasePath/nmt_en_ja';
  static const String nmtJaEnDir = '$modelsBasePath/nmt_ja_en';

  // Sherpa TTS Model Paths
  static const String ttsEnDir = '$modelsBasePath/tts_en';
  static const String ttsJaDir = '$modelsBasePath/tts_ja';
}
