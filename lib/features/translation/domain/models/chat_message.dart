/// Languages supported by the offline Edge Translator.
enum TranslationLanguage {
  english(name: 'English', code: 'EN', flag: '🇺🇸', label: 'English (US)'),
  japanese(name: 'Japanese', code: 'JA', flag: '🇯🇵', label: '日本語 (JP)');

  final String name;
  final String code;
  final String flag;
  final String label;

  const TranslationLanguage({
    required this.name,
    required this.code,
    required this.flag,
    required this.label,
  });

  TranslationLanguage get opposite =>
      this == TranslationLanguage.english ? TranslationLanguage.japanese : TranslationLanguage.english;
}

/// Pipeline states strictly covering all stages of the translation lifecycle.
enum PipelineStatus {
  idle,
  recording,
  transcribing,
  translating,
  synthesizing,
  playing,
  error;

  String get label {
    switch (this) {
      case PipelineStatus.idle:
        return 'Ready';
      case PipelineStatus.recording:
        return 'Recording Audio...';
      case PipelineStatus.transcribing:
        return 'Transcribing Speech (ASR)...';
      case PipelineStatus.translating:
        return 'Translating Text (NMT)...';
      case PipelineStatus.synthesizing:
        return 'Synthesizing Voice (TTS)...';
      case PipelineStatus.playing:
        return 'Playing Audio Output...';
      case PipelineStatus.error:
        return 'Pipeline Error';
    }
  }

  bool get isRecording => this == PipelineStatus.recording;
  bool get isProcessing =>
      this == PipelineStatus.transcribing ||
      this == PipelineStatus.translating ||
      this == PipelineStatus.synthesizing;
  bool get isPlaying => this == PipelineStatus.playing;
  bool get isBusy => isRecording || isProcessing || isPlaying;
}

/// A completed conversation item in the chat log.
class ChatMessage {
  final String id;
  final TranslationLanguage sourceLang;
  final TranslationLanguage targetLang;
  final String originalText;
  final String translatedText;
  final DateTime timestamp;
  final bool isPlaying;

  const ChatMessage({
    required this.id,
    required this.sourceLang,
    required this.targetLang,
    required this.originalText,
    required this.translatedText,
    required this.timestamp,
    this.isPlaying = false,
  });

  ChatMessage copyWith({
    String? id,
    TranslationLanguage? sourceLang,
    TranslationLanguage? targetLang,
    String? originalText,
    String? translatedText,
    DateTime? timestamp,
    bool? isPlaying,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      sourceLang: sourceLang ?? this.sourceLang,
      targetLang: targetLang ?? this.targetLang,
      originalText: originalText ?? this.originalText,
      translatedText: translatedText ?? this.translatedText,
      timestamp: timestamp ?? this.timestamp,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}
