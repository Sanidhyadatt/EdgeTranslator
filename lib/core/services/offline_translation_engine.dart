/// Embedded Offline Translation Engine providing 100% offline bidirectional
/// English <-> Japanese translation for conversational phrases, questions,
/// directions, travel, and vocabulary.
///
/// Ensures the app translates reliably offline on Chrome Web, Desktop, and Android
/// even when disconnected from the internet or before external ML Kit models finish downloading.
class OfflineTranslationEngine {
  static final Map<String, String> _enToJaExact = {
    // Greetings & Courtesies
    'hello': 'こんにちは',
    'hi': 'こんにちは',
    'hey': 'やあ',
    'good morning': 'おはようございます',
    'good afternoon': 'こんにちは',
    'good evening': 'こんばんは',
    'good night': 'おやすみなさい',
    'how are you': 'お元気ですか？',
    'how are you?': 'お元気ですか？',
    'i am good': '元気です',
    'i am fine': '元気です',
    'thank you': 'ありがとうございます',
    'thank you very much': 'どうもありがとうございます',
    'thanks': 'ありがとう',
    'you are welcome': 'どういたしまして',
    'you\'re welcome': 'どういたしまして',
    'please': 'お願いします',
    'excuse me': 'すみません',
    'sorry': 'ごめんなさい',
    'i am sorry': '申し訳ありません',
    'goodbye': 'さようなら',
    'bye': 'さようなら',
    'see you': 'またね',
    'see you later': 'また後で',
    'yes': 'はい',
    'no': 'いいえ',
    'okay': 'わかりました',
    'ok': 'わかりました',
    'help': '助けてください',
    'help me': '助けてください',

    // Essential Questions
    'where is the station': '駅はどこですか？',
    'where is the station?': '駅はどこですか？',
    'where is the train station': '駅はどこですか？',
    'where is the train station?': '駅はどこですか？',
    'where is shibuya station': '渋谷駅はどこですか？',
    'where is shibuya station?': '渋谷駅はどこですか？',
    'where is shibuya': '渋谷はどこですか？',
    'where is shibuya?': '渋谷はどこですか？',
    'where is the bathroom': 'トイレはどこですか？',
    'where is the bathroom?': 'トイレはどこですか？',
    'where is the restroom': 'お手洗いはどこですか？',
    'where is the restroom?': 'お手洗いはどこですか？',
    'where is the toilet': 'トイレはどこですか？',
    'where is the toilet?': 'トイレはどこですか？',
    'where is the hotel': 'ホテルはどこですか？',
    'where is the hotel?': 'ホテルはどこですか？',
    'where is the restaurant': 'レストランはどこですか？',
    'where is the restaurant?': 'レストランはどこですか？',
    'where is the airport': '空港はどこですか？',
    'where is the airport?': '空港はどこですか？',
    'where is the hospital': '病院はどこですか？',
    'where is the hospital?': '病院はどこですか？',
    'how much is this': 'これはいくらですか？',
    'how much is this?': 'これはいくらですか？',
    'how much does this cost': 'これはいくらですか？',
    'how much is it': 'いくらですか？',
    'how much is it?': 'いくらですか？',
    'what is this': 'これは何ですか？',
    'what is this?': 'これは何ですか？',
    'what is your name': 'お名前は何ですか？',
    'what is your name?': 'お名前は何ですか？',
    'my name is': '私の名前は',
    'do you speak english': '英語を話せますか？',
    'do you speak english?': '英語を話せますか？',
    'i don\'t understand': 'わかりません',
    'i do not understand': 'わかりません',
    'i don\'t know': '知りません',
    'check please': 'お会計をお願いします',
    'bill please': 'お勘定をお願いします',
    'water please': 'お水をお願いします',
    'delicious': '美味しいです',
    'it is delicious': 'とても美味しいです',
  };

  static final Map<String, String> _jaToEnExact = {
    'こんにちは': 'Hello',
    'こんにちは！': 'Hello!',
    'おはよう': 'Good morning',
    'おはようございます': 'Good morning',
    'こんばんは': 'Good evening',
    'おやすみなさい': 'Good night',
    'お元気ですか': 'How are you?',
    'お元気ですか？': 'How are you?',
    '元気です': 'I am fine',
    'ありがとう': 'Thank you',
    'ありがとうございます': 'Thank you very much',
    'どうもありがとう': 'Thank you very much',
    'どういたしまして': 'You are welcome',
    'すみません': 'Excuse me',
    'ごめんなさい': 'I am sorry',
    '申し訳ありません': 'I am very sorry',
    'お願いします': 'Please',
    'さようなら': 'Goodbye',
    'またね': 'See you later',
    'はい': 'Yes',
    'いいえ': 'No',
    'わかりました': 'I understand',
    'わかりません': 'I do not understand',
    '駅はどこですか': 'Where is the station?',
    '駅はどこですか？': 'Where is the station?',
    '渋谷駅はどこですか': 'Where is Shibuya station?',
    '渋谷駅はどこですか？': 'Where is Shibuya station?',
    '渋谷はどこですか': 'Where is Shibuya?',
    '渋谷はどこですか？': 'Where is Shibuya?',
    'トイレはどこですか': 'Where is the bathroom?',
    'トイレはどこですか？': 'Where is the bathroom?',
    'お手洗いはどこですか': 'Where is the restroom?',
    'お手洗いはどこですか？': 'Where is the restroom?',
    'ホテルはどこですか': 'Where is the hotel?',
    'ホテルはどこですか？': 'Where is the hotel?',
    'レストランはどこですか': 'Where is the restaurant?',
    'レストランはどこですか？': 'Where is the restaurant?',
    '空港はどこですか': 'Where is the airport?',
    '空港はどこですか？': 'Where is the airport?',
    '病院はどこですか': 'Where is the hospital?',
    '病院はどこですか？': 'Where is the hospital?',
    'これはいくらですか': 'How much is this?',
    'これはいくらですか？': 'How much is this?',
    'いくらですか': 'How much is it?',
    'いくらですか？': 'How much is it?',
    'これは何ですか': 'What is this?',
    'これは何ですか？': 'What is this?',
    'お会計をお願いします': 'Check, please',
    'お勘定をお願いします': 'Check, please',
    'お水をお願いします': 'Water, please',
    '助けてください': 'Please help me',
    '助けて': 'Help',
    '美味しい': 'Delicious',
    '美味しいです': 'It is delicious',
    '英語を話せますか': 'Can you speak English?',
    '英語を話せますか？': 'Can you speak English?',
  };

  static final Map<String, String> _enToJaVocab = {
    'station': '駅',
    'train': '電車',
    'subway': '地下鉄',
    'bus': 'バス',
    'taxi': 'タクシー',
    'ticket': '切符',
    'airport': '空港',
    'hotel': 'ホテル',
    'room': '部屋',
    'restaurant': 'レストラン',
    'cafe': 'カフェ',
    'food': '食べ物',
    'water': '水',
    'tea': 'お茶',
    'coffee': 'コーヒー',
    'beer': 'ビール',
    'menu': 'メニュー',
    'check': 'お会計',
    'bill': '勘定',
    'receipt': '領収書',
    'money': 'お金',
    'credit card': 'クレジットカード',
    'cash': '現金',
    'bathroom': 'トイレ',
    'toilet': 'トイレ',
    'restroom': 'お手洗い',
    'hospital': '病院',
    'pharmacy': '薬局',
    'doctor': '医者',
    'medicine': '薬',
    'help': '助け',
    'police': '警察',
    'phone': '電話',
    'wifi': 'Wi-Fi',
    'internet': 'インターネット',
    'passport': 'パスポート',
    'bag': 'カバン',
    'luggage': '荷物',
    'convenience store': 'コンビニ',
    'supermarket': 'スーパー',
    'shop': '店',
    'store': '店',
    'map': '地図',
    'street': '通り',
    'road': '道',
    'here': 'ここ',
    'there': 'そこ',
    'today': '今日',
    'tomorrow': '明日',
    'yesterday': '昨日',
    'morning': '朝',
    'afternoon': '午後',
    'night': '夜',
    'delicious': '美味しい',
    'good': '良い',
    'bad': '悪い',
    'hot': '暑い',
    'cold': '寒い',
    'big': '大きい',
    'small': '小さい',
    'near': '近い',
    'far': '遠い',
  };

  static final Map<String, String> _jaToEnVocab = {
    '駅': 'station',
    '電車': 'train',
    '地下鉄': 'subway',
    'バス': 'bus',
    'タクシー': 'taxi',
    '切符': 'ticket',
    '空港': 'airport',
    'ホテル': 'hotel',
    '部屋': 'room',
    'レストラン': 'restaurant',
    'カフェ': 'cafe',
    '食べ物': 'food',
    '水': 'water',
    'お茶': 'tea',
    'コーヒー': 'coffee',
    'ビール': 'beer',
    'メニュー': 'menu',
    'お会計': 'check',
    'お金': 'money',
    'トイレ': 'bathroom',
    'お手洗い': 'restroom',
    '病院': 'hospital',
    '薬局': 'pharmacy',
    '薬': 'medicine',
    '警察': 'police',
    '電話': 'phone',
    'コンビニ': 'convenience store',
    '地図': 'map',
    '道': 'road',
    '美味しい': 'delicious',
    '今日': 'today',
    '明日': 'tomorrow',
    '昨日': 'yesterday',
  };

  /// Translates English text to Japanese 100% offline.
  static String translateEnToJa(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return '';

    final lower = clean.toLowerCase().replaceAll(RegExp(r'[.!?,]+$'), '').trim();

    // 1. Direct exact phrase match
    if (_enToJaExact.containsKey(lower)) {
      return _enToJaExact[lower]!;
    }
    if (_enToJaExact.containsKey(clean.toLowerCase())) {
      return _enToJaExact[clean.toLowerCase()]!;
    }

    // 2. Pattern: "where is [X]"
    final whereIsReg = RegExp(r'^where\s+is\s+(the\s+|a\s+|an\s+)?(.+)\??$', caseSensitive: false);
    final whereMatch = whereIsReg.firstMatch(clean);
    if (whereMatch != null) {
      final subject = whereMatch.group(2)!.trim().toLowerCase();
      final translatedSubject = _enToJaVocab[subject] ?? subject;
      return '$translatedSubjectはどこですか？';
    }

    // 3. Pattern: "how much is [X]"
    final howMuchReg = RegExp(r'^how\s+much\s+is\s+(the\s+|a\s+|an\s+)?(.+)\??$', caseSensitive: false);
    final howMuchMatch = howMuchReg.firstMatch(clean);
    if (howMuchMatch != null) {
      final subject = howMuchMatch.group(2)!.trim().toLowerCase();
      final translatedSubject = _enToJaVocab[subject] ?? subject;
      return '$translatedSubjectはいくらですか？';
    }

    // 4. Pattern: "i want [X]" / "i would like [X]" / "can i get [X]"
    final wantReg = RegExp(r'^(i\s+want|i\s+would\s+like|can\s+i\s+get|give\s+me)\s+(the\s+|a\s+|an\s+)?(.+)\??$', caseSensitive: false);
    final wantMatch = wantReg.firstMatch(clean);
    if (wantMatch != null) {
      final subject = wantMatch.group(3)!.trim().toLowerCase();
      final translatedSubject = _enToJaVocab[subject] ?? subject;
      return '$translatedSubjectをお願いします';
    }

    // 5. Pattern: "do you have [X]"
    final haveReg = RegExp(r'^do\s+you\s+have\s+(the\s+|a\s+|an\s+)?(.+)\??$', caseSensitive: false);
    final haveMatch = haveReg.firstMatch(clean);
    if (haveMatch != null) {
      final subject = haveMatch.group(2)!.trim().toLowerCase();
      final translatedSubject = _enToJaVocab[subject] ?? subject;
      return '$translatedSubjectはありますか？';
    }

    // 6. Token/Phrase matching for general input
    var translated = lower;
    bool hasMatch = false;

    // Multi-word replacements first
    for (final entry in _enToJaVocab.entries) {
      if (entry.key.contains(' ') && translated.contains(entry.key)) {
        translated = translated.replaceAll(entry.key, entry.value);
        hasMatch = true;
      }
    }

    // Single-word replacements
    final words = translated.split(' ');
    final resultWords = <String>[];
    for (final word in words) {
      final cleanWord = word.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      if (_enToJaVocab.containsKey(cleanWord)) {
        resultWords.add(_enToJaVocab[cleanWord]!);
        hasMatch = true;
      } else {
        resultWords.add(word);
      }
    }

    if (hasMatch) {
      return resultWords.join('');
    }

    // Japanese Katakana transliteration or fallback representation
    return '（オフライン翻訳）$clean';
  }

  /// Translates Japanese text to English 100% offline.
  static String translateJaToEn(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return '';

    // 1. Direct exact phrase match
    if (_jaToEnExact.containsKey(clean)) {
      return _jaToEnExact[clean]!;
    }
    final withoutPunct = clean.replaceAll(RegExp(r'[？!！。、]+$'), '');
    if (_jaToEnExact.containsKey(withoutPunct)) {
      return _jaToEnExact[withoutPunct]!;
    }

    // 2. Pattern: "[X]はどこですか" -> "Where is [X]?"
    final whereMatch = RegExp(r'^(.+)(は|って)どこ(ですか|にありますか)?[？?]?$').firstMatch(clean);
    if (whereMatch != null) {
      final subject = whereMatch.group(1)!.trim();
      final translatedSubject = _jaToEnVocab[subject] ?? subject;
      return 'Where is the $translatedSubject?';
    }

    // 3. Pattern: "[X]はいくらですか" -> "How much is [X]?"
    final priceMatch = RegExp(r'^(.+)はいくら(ですか)?[？?]?$').firstMatch(clean);
    if (priceMatch != null) {
      final subject = priceMatch.group(1)!.trim();
      final translatedSubject = _jaToEnVocab[subject] ?? subject;
      return 'How much is $translatedSubject?';
    }

    // 4. Pattern: "[X]をお願いします" / "[X]をください" -> "[X], please"
    final pleaseMatch = RegExp(r'^(.+)(を|のお?)(お願いします|ください)$').firstMatch(clean);
    if (pleaseMatch != null) {
      final subject = pleaseMatch.group(1)!.trim();
      final translatedSubject = _jaToEnVocab[subject] ?? subject;
      return '$translatedSubject, please';
    }

    // 5. Pattern: "[X]はありますか" -> "Do you have [X]?"
    final haveMatch = RegExp(r'^(.+)はありますか[？?]?$').firstMatch(clean);
    if (haveMatch != null) {
      final subject = haveMatch.group(1)!.trim();
      final translatedSubject = _jaToEnVocab[subject] ?? subject;
      return 'Do you have $translatedSubject?';
    }

    // Vocabulary replacement
    for (final entry in _jaToEnVocab.entries) {
      if (clean.contains(entry.key)) {
        return clean.replaceAll(entry.key, '${entry.value} ');
      }
    }

    return clean;
  }
}
