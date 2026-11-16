import '../../features/translation/domain/models/chat_message.dart';

/// Complete localized UI copy for IKHO supporting two explicit UI modes:
/// English instructions (`TranslationLanguage.english`) and
/// Japanese instructions (`TranslationLanguage.japanese`).
class AppStrings {
  final TranslationLanguage lang;

  const AppStrings(this.lang);

  bool get isJa => lang == TranslationLanguage.japanese;

  static AppStrings of(TranslationLanguage lang) => AppStrings(lang);

  // Brand
  String get appTitle => 'IKHO';

  // Bottom Navigation
  String get navTranslate => isJa ? '翻訳' : 'Translate';
  String get navHistory => isJa ? '履歴' : 'History';
  String get navSettings => isJa ? '設定' : 'Settings';

  // Language names
  String langName(TranslationLanguage l) {
    if (isJa) {
      return l == TranslationLanguage.english ? '英語' : '日本語';
    }
    return l == TranslationLanguage.english ? 'English' : 'Japanese';
  }

  String directionBadge(TranslationLanguage source) {
    final target = source.opposite;
    if (isJa) {
      return '${langName(source)} → ${langName(target)}';
    }
    return source == TranslationLanguage.english ? 'EN → JA' : 'JA → EN';
  }

  // Pure Console View
  String get emptyHeroTitle =>
      isJa ? 'マイクを押すか文字を入力してください' : 'Tap microphone or Type below';
  String get emptyHeroSubtitle => isJa
      ? '英語または日本語で話しかけるか入力すると翻訳できます。'
      : 'Speak or type in English or Japanese to translate.';
  String get copyTooltip => isJa ? '翻訳をコピー' : 'Copy translation';
  String get copiedSnackbar =>
      isJa ? 'クリップボードにコピーしました' : 'Translation copied to clipboard';
  String get listenOriginalTooltip => isJa ? '元の文を再生' : 'Listen to original';
  String get translatingLabel => isJa ? '翻訳中…' : 'Translating…';
  String get slowSpeedLabel => isJa ? '0.8倍速' : '0.8x Slow';
  String get expandLabel => isJa ? '拡大' : 'Expand';
  String get listenLabel => isJa ? '聞く' : 'Listen';
  String get stopLabel => isJa ? '停止' : 'Stop';
  String get recentPhrasesTitle => isJa ? '最近の翻訳' : 'RECENT PHRASES';
  String get todayLabel => isJa ? '今日' : 'Today';
  String get replayTooltip => isJa ? '音声を再生' : 'Replay audio';
  String get typeButton => isJa ? '入力' : 'Type';
  String get hideInputTooltip => isJa ? '入力欄を閉じる' : 'Hide text input';
  String composerHint(TranslationLanguage active) {
    if (isJa) {
      return active == TranslationLanguage.english
          ? '英語または日本語を入力...'
          : '日本語または英語を入力...';
    }
    return active == TranslationLanguage.english
        ? 'Type English or Japanese...'
        : 'Type Japanese or English...';
  }

  String speakTooltip(TranslationLanguage active) =>
      isJa ? '押して話す（${langName(active)}）' : 'Tap to speak (${langName(active)})';

  // Pure Recording View
  String get listeningHeading => isJa ? '聞き取っています…' : 'Listening…';
  String get finishingHeading =>
      isJa ? '文字起こしを完了しています…' : 'Finishing transcription…';
  String get recordingInstruction => isJa
      ? '話し終わったら「完了」を押してください'
      : 'Speak freely — tap Done when finished';
  String get translatingInstruction =>
      isJa ? '文字起こしと翻訳を行っています…' : 'Transcribing & translating…';
  String get cancelLabel => isJa ? '取消' : 'Cancel';
  String get doneLabel => isJa ? '完了' : 'Done';
  String get savingLabel => isJa ? '翻訳中...' : 'Saving...';

  // Fullscreen Modal
  String get fullscreenHeader =>
      isJa ? '相手に見せる画面' : 'Display Translation';
  String get fullscreenPlayAudio => isJa ? '音声を再生' : 'Play Audio';
  String get fullscreenStopAudio => isJa ? '停止' : 'Stop';
  String get fullscreenFooterHint =>
      isJa ? '閉じるを押して戻る' : 'Tap Close to return';

  // History View
  String get historyTitle => isJa ? '履歴' : 'History';
  String get clearButton => isJa ? 'すべて削除' : 'Clear';
  String get searchPlaceholder =>
      isJa ? '保存されたフレーズを検索...' : 'Search saved phrases...';
  String filterAll(int count) => isJa ? 'すべて ($count)' : 'All ($count)';
  String get filterEnToJa => isJa ? '英語 → 日本語' : 'EN → JA';
  String get filterJaToEn => isJa ? '日本語 → 英語' : 'JA → EN';
  String get expandTooltip => isJa ? '拡大表示' : 'Expand fullscreen';
  String get noMatchingHistoryTitle =>
      isJa ? '一致する翻訳がありません' : 'No matching translations';
  String get noMatchingHistorySubtitle => isJa
      ? '検索語句やフィルターを変更してみてください。'
      : 'Try clearing your search or language filter.';
  String get emptyHistoryTitle =>
      isJa ? '履歴はまだありません' : 'No translation history yet';
  String get emptyHistorySubtitle => isJa
      ? '音声やテキストで翻訳した履歴がここに表示されます。'
      : 'Translated voice and text phrases appear here.';

  // Clear Dialog
  String get clearDialogTitle =>
      isJa ? '履歴をすべて削除しますか？' : 'Clear Conversation?';
  String get clearDialogMessage => isJa
      ? '現在のセッションで翻訳したすべての履歴が削除されます。'
      : 'This will remove all translated messages from your current session.';
  String get dialogCancel => isJa ? 'キャンセル' : 'Cancel';
  String get dialogConfirmClear => isJa ? '削除する' : 'Clear All';

  // Settings View
  String get settingsTitle => isJa ? '設定' : 'Settings';
  String get sectionAppLanguage => isJa ? 'アプリ表示言語' : 'APP LANGUAGE';
  String get uiLanguageTitle => isJa ? '説明・表示言語' : 'Instruction & UI Language';
  String get uiLanguageSubtitle => isJa
      ? 'すべての案内・ボタン・メニューを日本語または英語に切り替えます。'
      : 'Show all instructions, buttons, and menus in English or Japanese.';

  String get sectionSpeechSpeed => isJa ? '音声・再生速度' : 'SPEECH & TTS SPEED';
  String get playbackRateTitle => isJa ? '再生スピード' : 'Playback Rate';
  String get playbackRateSubtitle => isJa
      ? '英語および日本語の読み上げ速度を調整します。'
      : 'Controls both OS text-to-speech rate (English) and Japanese voice speed.';
  String get presetSlow => isJa ? '0.8倍速' : '0.8x Slow';
  String get presetNormal => isJa ? '標準 (1.0x)' : '1.0x Normal';
  String get presetFast => isJa ? '1.2倍速' : '1.2x Fast';
  String get testEnVoice => isJa ? '英語テスト' : 'Test EN Voice';
  String get testJaVoice => isJa ? '日本語テスト' : 'Test JA Voice';

  String get sectionInputDirection => isJa ? '翻訳の方向と入力' : 'INPUT & DIRECTION';
  String get activeSourceLangTitle => isJa ? '翻訳の元言語' : 'Active Source Language';
  String get dirEnToJa => isJa ? '英語 → 日本語' : 'English → Japanese';
  String get dirJaToEn => isJa ? '日本語 → 英語' : 'Japanese → English';
  String get autoDetectTitle => isJa ? '入力言語を自動判別' : 'Auto-detect typed script';
  String get autoDetectSubtitle => isJa
      ? '切り替え設定にかかわらず入力された日本語・英語を自動判別します。'
      : 'Automatically translate Japanese or English text regardless of toggle direction.';

  String get sectionSessionData => isJa ? '履歴データ' : 'SESSION DATA';
  String savedPhrasesTitle(int count) =>
      isJa ? '保存された履歴 ($count件)' : 'Saved Phrases ($count)';
  String get savedPhrasesSubtitle => isJa
      ? 'このセッション中のメモリにのみ一時保存されます。'
      : 'Stored only in memory for this session.';
  String get clearAllButton => isJa ? 'すべて削除' : 'Clear All';
}
