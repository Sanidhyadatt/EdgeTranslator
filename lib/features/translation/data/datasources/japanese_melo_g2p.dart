/// Converts Japanese text into MeloTTS phoneme token IDs using a cleaned
/// Kanji lexicon, conjugation-aware stem recovery, particle pronunciation
/// rules (`は -> w a`, `へ -> e`), and a complete Hiragana/Katakana table.
class JapaneseMeloG2p {
  final Map<String, int> tokenToId;
  final Map<String, List<String>> lexicon;
  final Map<String, List<String>> kanjiBeforeKana;
  final int maxWordLength;
  final int blankId;

  JapaneseMeloG2p._({
    required this.tokenToId,
    required this.lexicon,
    required this.kanjiBeforeKana,
    required this.maxWordLength,
    required this.blankId,
  });

  static List<String> _splitWhitespace(String input) {
    final out = <String>[];
    var start = -1;
    for (var i = 0; i < input.length; i++) {
      final cu = input.codeUnitAt(i);
      final isWs = cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D || cu == 0x3000;
      if (isWs) {
        if (start != -1) {
          out.add(input.substring(start, i));
          start = -1;
        }
      } else if (start == -1) {
        start = i;
      }
    }
    if (start != -1) {
      out.add(input.substring(start));
    }
    return out;
  }

  factory JapaneseMeloG2p.fromFiles({
    required List<String> tokenLines,
    required List<String> lexiconLines,
  }) {
    final tokenToId = <String, int>{};
    for (final line in tokenLines) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) continue;
      final parts = _splitWhitespace(trimmed);
      if (parts.length >= 2) {
        final id = int.tryParse(parts.last);
        if (id != null) {
          tokenToId[parts.first] = id;
        }
      } else if (parts.length == 1) {
        final id = int.tryParse(parts.first);
        if (id != null) {
          tokenToId[' '] = id;
        }
      }
    }

    final lexicon = <String, List<String>>{};
    final kanjiBeforeKana = <String, List<String>>{};
    var maxLen = 1;

    for (final line in lexiconLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = _splitWhitespace(trimmed);
      if (parts.length < 3) continue;
      final word = parts[0];
      final rest = parts.sublist(1);
      final phoneCount = rest.length ~/ 2;
      if (phoneCount <= 0) continue;
      final phones = rest.sublist(0, phoneCount);

      // Pure-kana entries in MeloTTS lexicon contain dictionary lemmas (e.g. すみません -> sumumasuzu,
      // で -> da, し -> ki, な -> zu). Deterministic kana rules are strictly more accurate.
      if (!_containsKanji(word)) {
        continue;
      }

      final surfacePhones = _resolveSurfacePhones(word, phones);
      if (surfacePhones != null && surfacePhones.isNotEmpty) {
        lexicon[word] = surfacePhones;
        if (word.length > maxLen) {
          maxLen = word.length;
        }
      }

      _indexKanjiStemBeforeKana(word, surfacePhones ?? phones, kanjiBeforeKana);
    }

    return JapaneseMeloG2p._(
      tokenToId: tokenToId,
      lexicon: lexicon,
      kanjiBeforeKana: kanjiBeforeKana,
      maxWordLength: maxLen,
      blankId: tokenToId['_'] ?? 0,
    );
  }

  /// Resolves true surface phonemes for Kanji/okurigana lexicon entries, repairing
  /// entries where the tokenizer stored dictionary lemma forms (e.g. `止まり` -> `t o m a r u`).
  static List<String>? _resolveSurfacePhones(String word, List<String> phones) {
    final lastUnit = word[word.length - 1];
    if (!_isHiragana(lastUnit)) {
      return phones;
    }

    final expectedTail = _kanaSingle[lastUnit];
    if (expectedTail == null) {
      return phones;
    }

    if (_endsWithPhones(phones, expectedTail)) {
      return phones;
    }

    return _repairLemmatizedPhones(word, phones, lastUnit, expectedTail);
  }

  static List<String>? _repairLemmatizedPhones(
    String word,
    List<String> phones,
    String lastKana,
    List<String> expectedTail,
  ) {
    // 1. i-adjectives conjugated with `く`, `かっ`, or truncated stem `し`
    if (lastKana == 'く' && phones.length >= 2 && phones.last == 'i') {
      return [...phones.sublist(0, phones.length - 1), 'k', 'u'];
    }
    if (lastKana == 'っ' && word.endsWith('かっ') && phones.length >= 2 && phones.last == 'i') {
      return [...phones.sublist(0, phones.length - 1), 'k', 'a', 'q'];
    }
    if (lastKana == 'し' && _endsWithPhones(phones, const ['sh', 'i', 'i'])) {
      return phones.sublist(0, phones.length - 1);
    }

    // 2. Ichidan/vocalization verbs whose lemma ends in `-r u` after matching vowel (e.g. `食べ` -> `t a b e r u`)
    if (_endsWithPhones(phones, const ['r', 'u']) && phones.length >= expectedTail.length + 2) {
      final stemWithoutRu = phones.sublist(0, phones.length - 2);
      if (_endsWithPhones(stemWithoutRu, expectedTail)) {
        return stemWithoutRu;
      }
      // `下さい` -> `k u d a s a r u` => `k u d a s a i`
      if (word.endsWith('さい') && _endsWithPhones(stemWithoutRu, const ['s', 'a'])) {
        return [...stemWithoutRu, 'i'];
      }
      // `感じ`/`信じ` (`z u r u` lemma -> `j i`)
      if (lastKana == 'じ' && _endsWithPhones(phones, const ['z', 'u', 'r', 'u']) && phones.length >= 5) {
        return [...phones.sublist(0, phones.length - 4), 'j', 'i'];
      }
      // Ichidan imperative `-ろ` (`考えろ` -> `k a N g a e r u` -> `k a N g a e r o`)
      if (lastKana == 'ろ') {
        return [...stemWithoutRu, 'r', 'o'];
      }
    }

    // 3. Godan verbs conjugated on vowel columns (`r u -> r i/a/e/o`, `s u -> sh i/s a`, etc.)
    const godanEndings = <List<String>>[
      ['r', 'u'],
      ['k', 'u'],
      ['g', 'u'],
      ['s', 'u'],
      ['ts', 'u'],
      ['n', 'u'],
      ['b', 'u'],
      ['m', 'u'],
    ];

    if (lastKana == 'っ') {
      for (final ending in godanEndings) {
        if (phones.length > ending.length && _endsWithPhones(phones, ending)) {
          return [...phones.sublist(0, phones.length - ending.length), 'q'];
        }
      }
      if (phones.length >= 2 && phones.last == 'u') {
        return [...phones.sublist(0, phones.length - 1), 'q'];
      }
      return null;
    }

    if (lastKana == 'ん') {
      for (final ending in const [
        ['n', 'u'],
        ['b', 'u'],
        ['m', 'u'],
      ]) {
        if (phones.length > ending.length && _endsWithPhones(phones, ending)) {
          return [...phones.sublist(0, phones.length - ending.length), 'N'];
        }
      }
      return null;
    }

    if (lastKana == 'い') {
      if (phones.length >= 3 && (_endsWithPhones(phones, const ['k', 'u']) || _endsWithPhones(phones, const ['g', 'u']))) {
        return [...phones.sublist(0, phones.length - 2), 'i'];
      }
      if (phones.length >= 2 && phones.last == 'u' && !const ['r', 'k', 'g', 's', 'ts', 'n', 'b', 'm', 'ch', 'sh'].contains(phones[phones.length - 2])) {
        return [...phones.sublist(0, phones.length - 1), 'i'];
      }
    }

    if (lastKana == 'わ' && phones.length >= 2 && phones.last == 'u') {
      if (!const ['r', 'k', 'g', 's', 'ts', 'n', 'b', 'm'].contains(phones[phones.length - 2])) {
        return [...phones.sublist(0, phones.length - 1), 'w', 'a'];
      }
    }

    for (final ending in godanEndings) {
      if (phones.length > ending.length && _endsWithPhones(phones, ending)) {
        final stemConsonant = ending[0];
        final targetConsonant = expectedTail.length > 1 ? expectedTail[0] : '';
        final sameRow = stemConsonant == targetConsonant ||
            (stemConsonant == 's' && targetConsonant == 'sh') ||
            (stemConsonant == 'ts' && (targetConsonant == 'ch' || targetConsonant == 't'));
        if (sameRow) {
          return [...phones.sublist(0, phones.length - ending.length), ...expectedTail];
        }
      }
    }

    return null;
  }

  static void _indexKanjiStemBeforeKana(
    String word,
    List<String> phones,
    Map<String, List<String>> kanjiBeforeKana,
  ) {
    // Extract Kanji stem when word is `[Kanji...][Hiragana...]` with exact matching okurigana phonemes
    var firstKanaIdx = -1;
    for (var i = 0; i < word.length; i++) {
      if (_isHiragana(word[i])) {
        firstKanaIdx = i;
        break;
      }
    }
    if (firstKanaIdx <= 0) return;
    final kanjiPrefix = word.substring(0, firstKanaIdx);
    if (!_allKanji(kanjiPrefix) || kanjiBeforeKana.containsKey(kanjiPrefix)) return;

    final okuri = word.substring(firstKanaIdx);
    final okuriPhones = _encodePlainKana(okuri);
    if (okuriPhones.isNotEmpty &&
        phones.length > okuriPhones.length &&
        _endsWithPhones(phones, okuriPhones)) {
      kanjiBeforeKana[kanjiPrefix] = phones.sublist(0, phones.length - okuriPhones.length);
    }
  }

  static List<String> _encodePlainKana(String kana) {
    final out = <String>[];
    var i = 0;
    while (i < kana.length) {
      if (i + 1 < kana.length) {
        final pair = _kanaDigraphs[kana.substring(i, i + 2)];
        if (pair != null) {
          out.addAll(pair);
          i += 2;
          continue;
        }
      }
      final single = _kanaSingle[kana[i]];
      if (single == null) return const [];
      out.addAll(single);
      i++;
    }
    return out;
  }

  static bool _endsWithPhones(List<String> phones, List<String> suffix) {
    if (phones.length < suffix.length) return false;
    final offset = phones.length - suffix.length;
    for (var i = 0; i < suffix.length; i++) {
      if (phones[offset + i] != suffix[i]) return false;
    }
    return true;
  }

  /// Splits [text] into sentences on punctuation and converts each to blank-interleaved
  /// MeloTTS token IDs (`[blank, tok1, blank, tok2, ..., blank]`).
  List<List<int>> encodeSentences(String text) {
    final normalized = _normalizePunctuation(text.trim());
    if (normalized.isEmpty) return const [];

    final rawSentences = <String>[];
    for (final part in normalized.split(RegExp(r'(?<=[.!?])\s*'))) {
      final s = part.trim();
      if (s.isEmpty) continue;
      if (s.length > 24 && s.contains(',')) {
        for (final sub in s.split(RegExp(r'(?<=,)\s*'))) {
          final cleanSub = sub.trim();
          if (cleanSub.isNotEmpty) rawSentences.add(cleanSub);
        }
      } else {
        rawSentences.add(s);
      }
    }

    final encoded = <List<int>>[];
    for (final sentence in rawSentences) {
      final phones = _textToPhonemes(sentence);
      if (phones.isEmpty) continue;
      final ids = <int>[blankId];
      for (final ph in phones) {
        final id = tokenToId[ph];
        if (id != null) {
          ids.add(id);
          ids.add(blankId);
        }
      }
      if (ids.length > 1) {
        encoded.add(ids);
      }
    }
    return encoded;
  }

  List<String> _textToPhonemes(String sentence) {
    final phones = <String>[];
    var i = 0;
    final len = sentence.length;

    while (i < len) {
      final ch = sentence[i];
      if (ch == ',' || ch == '.' || ch == '!' || ch == '?' || ch == '-') {
        if (tokenToId.containsKey(ch)) {
          phones.add(ch);
        }
        i++;
        continue;
      }
      if (ch.trim().isEmpty) {
        i++;
        continue;
      }

      // 1. Fixed irregular Hiragana greetings
      String? specialGreeting;
      for (final key in _specialKanaWords.keys) {
        if (sentence.startsWith(key, i)) {
          specialGreeting = key;
          break;
        }
      }
      if (specialGreeting != null) {
        phones.addAll(_specialKanaWords[specialGreeting]!);
        i += specialGreeting.length;
        continue;
      }

      // 2. Context-aware particles: topic `は` -> `w a`, direction `へ` -> `e`
      if (ch == 'は' && _isTopicParticleHa(sentence, i)) {
        phones.addAll(const ['w', 'a']);
        i++;
        continue;
      }
      if (ch == 'へ' && _isDirectionParticleHe(sentence, i)) {
        phones.add('e');
        i++;
        continue;
      }

      // 3. Curated Kanji long-vowel & common compound pronunciation overrides
      String? overrideWord;
      final maxOverrideEnd = (i + _maxOverrideLength) < len ? (i + _maxOverrideLength) : len;
      for (var end = maxOverrideEnd; end > i; end--) {
        final candidate = sentence.substring(i, end);
        if (_kanjiPronunciationOverrides.containsKey(candidate)) {
          overrideWord = candidate;
          break;
        }
      }
      if (overrideWord != null) {
        phones.addAll(_kanjiPronunciationOverrides[overrideWord]!);
        i += overrideWord.length;
        continue;
      }

      // 4. Longest lexicon match (Kanji compounds and verified Kanji+okurigana forms)
      String? matchedWord;
      final maxEnd = (i + maxWordLength) < len ? (i + maxWordLength) : len;
      for (var end = maxEnd; end > i; end--) {
        final candidate = sentence.substring(i, end);
        if (lexicon.containsKey(candidate)) {
          matchedWord = candidate;
          break;
        }
      }
      if (matchedWord != null) {
        phones.addAll(lexicon[matchedWord]!);
        i += matchedWord.length;
        continue;
      }

      // 4. Conjugated Kanji stem fallback when followed by Hiragana okurigana
      if (_isKanji(ch)) {
        String? stemMatch;
        for (var kLen = 3; kLen >= 1; kLen--) {
          if (i + kLen < len && _isHiragana(sentence[i + kLen])) {
            final stem = sentence.substring(i, i + kLen);
            if (kanjiBeforeKana.containsKey(stem)) {
              stemMatch = stem;
              break;
            }
          }
        }
        if (stemMatch != null) {
          phones.addAll(kanjiBeforeKana[stemMatch]!);
          i += stemMatch.length;
          continue;
        }
      }

      // 5. Try 2-char kana digraph fallback (after normalizing Katakana -> Hiragana)
      if (i + 1 < len) {
        final pair = _toHiragana(sentence.substring(i, i + 2));
        final pairPhones = _kanaDigraphs[pair];
        if (pairPhones != null) {
          phones.addAll(pairPhones);
          i += 2;
          continue;
        }
      }

      // 6. Prolonged vowel mark `ー` repeats preceding vowel phoneme
      final hira = _toHiragana(ch);
      if (hira == 'ー') {
        if (phones.isNotEmpty && _vowelPhonemes.contains(phones.last)) {
          phones.add(phones.last);
        }
        i++;
        continue;
      }

      // 7. Single kana fallback (Hiragana/Katakana)
      final singlePhones = _kanaSingle[hira];
      if (singlePhones != null) {
        phones.addAll(singlePhones);
        i++;
        continue;
      }

      // 8. Multi-digit ASCII integers and single ASCII character fallback
      final cu = ch.codeUnitAt(0);
      if (cu >= 0x30 && cu <= 0x39) {
        var end = i + 1;
        while (end < len) {
          final nextCu = sentence.codeUnitAt(end);
          if (nextCu < 0x30 || nextCu > 0x39) break;
          end++;
        }
        final digits = sentence.substring(i, end);
        final numPhones = _readJapaneseNumber(digits);
        if (numPhones != null) {
          phones.addAll(numPhones);
        } else {
          for (var d = 0; d < digits.length; d++) {
            final dp = _digitReadings[digits[d]];
            if (dp != null) phones.addAll(dp);
          }
        }
        i = end;
        continue;
      }

      final lower = ch.toLowerCase();
      if (_digitReadings.containsKey(lower)) {
        phones.addAll(_digitReadings[lower]!);
      } else if (tokenToId.containsKey(lower)) {
        phones.add(lower);
      }
      i++;
    }

    return phones;
  }

  static bool _isTopicParticleHa(String s, int i) {
    if (i == 0) return false;
    final prev = s[i - 1];
    if (_isKanji(prev) || _isKatakana(prev) || prev == ' ' || prev == ',') {
      return true;
    }
    final prefix = s.substring(0, i);
    for (final p in _topicParticlePrecedes) {
      if (prefix.endsWith(p)) return true;
    }
    return false;
  }

  static bool _isDirectionParticleHe(String s, int i) {
    if (i == 0) return false;
    final prev = s[i - 1];
    if (_isKanji(prev) || _isKatakana(prev) || prev == ' ') return true;
    final prefix = s.substring(0, i);
    return prefix.endsWith('どこ') || prefix.endsWith('ここ') || prefix.endsWith('そこ') || prefix.endsWith('あそこ');
  }

  static bool _containsKanji(String s) {
    for (final r in s.runes) {
      if (r >= 0x4E00 && r <= 0x9FFF) return true;
    }
    return false;
  }

  static bool _allKanji(String s) {
    if (s.isEmpty) return false;
    for (final r in s.runes) {
      if (r < 0x4E00 || r > 0x9FFF) return false;
    }
    return true;
  }

  static bool _isKanji(String ch) {
    if (ch.isEmpty) return false;
    final r = ch.runes.first;
    return r >= 0x4E00 && r <= 0x9FFF;
  }

  static bool _isHiragana(String ch) {
    if (ch.isEmpty) return false;
    final r = ch.runes.first;
    return r >= 0x3041 && r <= 0x3096;
  }

  static bool _isKatakana(String ch) {
    if (ch.isEmpty) return false;
    final r = ch.runes.first;
    return r >= 0x30A1 && r <= 0x30F6;
  }

  static String _normalizePunctuation(String text) {
    return text
        .replaceAll('。', '.')
        .replaceAll('．', '.')
        .replaceAll('、', ',')
        .replaceAll('，', ',')
        .replaceAll('？', '?')
        .replaceAll('！', '!')
        .replaceAll('：', ',')
        .replaceAll('；', ',')
        .replaceAll('\u3000', ' ');
  }

  static String _toHiragana(String input) {
    final sb = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x30A1 && rune <= 0x30F6) {
        sb.writeCharCode(rune - 0x60);
      } else {
        sb.writeCharCode(rune);
      }
    }
    return sb.toString();
  }

  static const Set<String> _vowelPhonemes = {'a', 'i', 'u', 'e', 'o'};

  static const List<String> _topicParticlePrecedes = [
    'これ', 'それ', 'あれ', 'どれ', 'ここ', 'そこ', 'あそこ', 'どこ',
    'だれ', 'わたし', 'あなた', 'みんな', 'では', 'には', 'とは',
    'で', 'に', 'と', 'から', 'まで', 'だけ',
  ];

  static const int _maxOverrideLength = 4;

  static const Map<String, List<String>> _kanjiPronunciationOverrides = {
    'お手洗い': ['o', 't', 'e', 'a', 'r', 'a', 'i'],
    'お父さん': ['o', 't', 'o', 'u', 's', 'a', 'N'],
    'お母さん': ['o', 'k', 'a', 'a', 's', 'a', 'N'],
    'お兄さん': ['o', 'n', 'i', 'i', 's', 'a', 'N'],
    'お姉さん': ['o', 'n', 'e', 'e', 's', 'a', 'N'],
    'お会計': ['o', 'k', 'a', 'i', 'k', 'e', 'i'],
    '領収書': ['ry', 'o', 'u', 'sh', 'u', 'u', 'sh', 'o'],
    '新幹線': ['sh', 'i', 'N', 'k', 'a', 'N', 's', 'e', 'N'],
    '飛行機': ['h', 'i', 'k', 'o', 'u', 'k', 'i'],
    '日本語': ['n', 'i', 'h', 'o', 'N', 'g', 'o'],
    '大丈夫': ['d', 'a', 'i', 'j', 'o', 'u', 'b', 'u'],
    '東京': ['t', 'o', 'u', 'ky', 'o', 'u'],
    '京都': ['ky', 'o', 'u', 't', 'o'],
    '大阪': ['o', 'o', 's', 'a', 'k', 'a'],
    '空港': ['k', 'u', 'u', 'k', 'o', 'u'],
    '英語': ['e', 'i', 'g', 'o'],
    '日本': ['n', 'i', 'h', 'o', 'N'],
    '病院': ['by', 'o', 'u', 'i', 'N'],
    '公園': ['k', 'o', 'u', 'e', 'N'],
    '交番': ['k', 'o', 'u', 'b', 'a', 'N'],
    '先生': ['s', 'e', 'N', 's', 'e', 'i'],
    '学生': ['g', 'a', 'k', 'u', 's', 'e', 'i'],
    '今日': ['ky', 'o', 'u'],
    '昨日': ['k', 'i', 'n', 'o', 'u'],
    '明日': ['a', 'sh', 'i', 't', 'a'],
    '番号': ['b', 'a', 'N', 'g', 'o', 'u'],
    '電話': ['d', 'e', 'N', 'w', 'a'],
    '携帯': ['k', 'e', 'i', 't', 'a', 'i'],
    '料理': ['ry', 'o', 'u', 'r', 'i'],
    '料金': ['ry', 'o', 'u', 'k', 'i', 'N'],
    '注文': ['ch', 'u', 'u', 'm', 'o', 'N'],
    '牛乳': ['gy', 'u', 'u', 'ny', 'u', 'u'],
    '会計': ['k', 'a', 'i', 'k', 'e', 'i'],
    '有名': ['y', 'u', 'u', 'm', 'e', 'i'],
    '丁寧': ['t', 'e', 'i', 'n', 'e', 'i'],
    '綺麗': ['k', 'i', 'r', 'e', 'i'],
    '本当': ['h', 'o', 'N', 't', 'o', 'u'],
  };

  static const Map<String, List<String>> _specialKanaWords = {
    'おはようございます': ['o', 'h', 'a', 'y', 'o', 'u', 'g', 'o', 'z', 'a', 'i', 'm', 'a', 's', 'u'],
    'ありがとうございます': ['a', 'r', 'i', 'g', 'a', 't', 'o', 'u', 'g', 'o', 'z', 'a', 'i', 'm', 'a', 's', 'u'],
    'どういたしまして': ['d', 'o', 'u', 'i', 't', 'a', 'sh', 'i', 'm', 'a', 'sh', 'i', 't', 'e'],
    'こんにちは': ['k', 'o', 'N', 'n', 'i', 'ch', 'i', 'w', 'a'],
    'こんばんは': ['k', 'o', 'N', 'b', 'a', 'N', 'w', 'a'],
    'ありがとう': ['a', 'r', 'i', 'g', 'a', 't', 'o', 'u'],
    'さようなら': ['s', 'a', 'y', 'o', 'u', 'n', 'a', 'r', 'a'],
    'おはよう': ['o', 'h', 'a', 'y', 'o', 'u'],
  };

  static const Map<String, List<String>> _kanaDigraphs = {
    'きゃ': ['ky', 'a'], 'きゅ': ['ky', 'u'], 'きょ': ['ky', 'o'],
    'ぎゃ': ['gy', 'a'], 'ぎゅ': ['gy', 'u'], 'ぎょ': ['gy', 'o'],
    'しゃ': ['sh', 'a'], 'しゅ': ['sh', 'u'], 'しょ': ['sh', 'o'], 'しぇ': ['sh', 'e'],
    'じゃ': ['j', 'a'], 'じゅ': ['j', 'u'], 'じょ': ['j', 'o'], 'じぇ': ['j', 'e'],
    'ちゃ': ['ch', 'a'], 'ちゅ': ['ch', 'u'], 'ちょ': ['ch', 'o'], 'ちぇ': ['ch', 'e'],
    'にゃ': ['ny', 'a'], 'にゅ': ['ny', 'u'], 'にょ': ['ny', 'o'],
    'ひゃ': ['hy', 'a'], 'ひゅ': ['hy', 'u'], 'ひょ': ['hy', 'o'],
    'びゃ': ['by', 'a'], 'びゅ': ['by', 'u'], 'びょ': ['by', 'o'],
    'ぴゃ': ['py', 'a'], 'ぴゅ': ['py', 'u'], 'ぴょ': ['py', 'o'],
    'みゃ': ['my', 'a'], 'みゅ': ['my', 'u'], 'みょ': ['my', 'o'],
    'りゃ': ['ry', 'a'], 'りゅ': ['ry', 'u'], 'りょ': ['ry', 'o'],
    'てぃ': ['t', 'i'], 'でぃ': ['d', 'i'], 'とぅ': ['t', 'u'], 'どぅ': ['d', 'u'],
    'ふぁ': ['f', 'a'], 'ふぃ': ['f', 'i'], 'ふぇ': ['f', 'e'], 'ふぉ': ['f', 'o'],
    'うぃ': ['w', 'i'], 'うぇ': ['w', 'e'], 'うぉ': ['w', 'o'],
    'ゔぁ': ['b', 'a'], 'ゔぃ': ['b', 'i'], 'ゔぇ': ['b', 'e'], 'ゔぉ': ['b', 'o'],
    'つぁ': ['ts', 'a'], 'つぃ': ['ts', 'i'], 'つぇ': ['ts', 'e'], 'つぉ': ['ts', 'o'],
  };

  static const Map<String, List<String>> _kanaSingle = {
    'あ': ['a'], 'い': ['i'], 'う': ['u'], 'え': ['e'], 'お': ['o'],
    'ぁ': ['a'], 'ぃ': ['i'], 'ぅ': ['u'], 'ぇ': ['e'], 'ぉ': ['o'],
    'か': ['k', 'a'], 'き': ['k', 'i'], 'く': ['k', 'u'], 'け': ['k', 'e'], 'こ': ['k', 'o'],
    'が': ['g', 'a'], 'ぎ': ['g', 'i'], 'ぐ': ['g', 'u'], 'げ': ['g', 'e'], 'ご': ['g', 'o'],
    'さ': ['s', 'a'], 'し': ['sh', 'i'], 'す': ['s', 'u'], 'せ': ['s', 'e'], 'そ': ['s', 'o'],
    'ざ': ['z', 'a'], 'じ': ['j', 'i'], 'ず': ['z', 'u'], 'ぜ': ['z', 'e'], 'ぞ': ['z', 'o'],
    'た': ['t', 'a'], 'ち': ['ch', 'i'], 'つ': ['ts', 'u'], 'て': ['t', 'e'], 'と': ['t', 'o'],
    'だ': ['d', 'a'], 'ぢ': ['j', 'i'], 'づ': ['z', 'u'], 'で': ['d', 'e'], 'ど': ['d', 'o'],
    'な': ['n', 'a'], 'に': ['n', 'i'], 'ぬ': ['n', 'u'], 'ね': ['n', 'e'], 'の': ['n', 'o'],
    'は': ['h', 'a'], 'ひ': ['h', 'i'], 'ふ': ['f', 'u'], 'へ': ['h', 'e'], 'ほ': ['h', 'o'],
    'ば': ['b', 'a'], 'び': ['b', 'i'], 'ぶ': ['b', 'u'], 'べ': ['b', 'e'], 'ぼ': ['b', 'o'],
    'ぱ': ['p', 'a'], 'ぴ': ['p', 'i'], 'ぷ': ['p', 'u'], 'ぺ': ['p', 'e'], 'ぽ': ['p', 'o'],
    'ま': ['m', 'a'], 'み': ['m', 'i'], 'む': ['m', 'u'], 'め': ['m', 'e'], 'も': ['m', 'o'],
    'や': ['y', 'a'], 'ゆ': ['y', 'u'], 'よ': ['y', 'o'],
    'ゃ': ['y', 'a'], 'ゅ': ['y', 'u'], 'ょ': ['y', 'o'],
    'ら': ['r', 'a'], 'り': ['r', 'i'], 'る': ['r', 'u'], 'れ': ['r', 'e'], 'ろ': ['r', 'o'],
    'わ': ['w', 'a'], 'を': ['o'], 'ん': ['N'], 'っ': ['q'], 'ゔ': ['b', 'u'],
  };

  static const Map<String, List<String>> _digitReadings = {
    '0': ['z', 'e', 'r', 'o'],
    '1': ['i', 'ch', 'i'],
    '2': ['n', 'i'],
    '3': ['s', 'a', 'N'],
    '4': ['y', 'o', 'N'],
    '5': ['g', 'o'],
    '6': ['r', 'o', 'k', 'u'],
    '7': ['n', 'a', 'n', 'a'],
    '8': ['h', 'a', 'ch', 'i'],
    '9': ['ky', 'u', 'u'],
  };

  static List<String>? _readJapaneseNumber(String digits) {
    if (digits.isEmpty || digits.length > 5) return null;
    if (digits.length > 1 && digits.startsWith('0')) return null;
    final n = int.tryParse(digits);
    if (n == null || n < 0 || n > 99999) return null;
    if (n < 10) return _digitReadings[digits];

    final out = <String>[];
    var rem = n;
    final man = rem ~/ 10000;
    rem %= 10000;
    if (man > 0) {
      out.addAll(_digitReadings[man.toString()]!);
      out.addAll(const ['m', 'a', 'N']);
    }

    final sen = rem ~/ 1000;
    rem %= 1000;
    if (sen > 0) {
      switch (sen) {
        case 1:
          out.addAll(const ['s', 'e', 'N']);
        case 3:
          out.addAll(const ['s', 'a', 'N', 'z', 'e', 'N']);
        case 8:
          out.addAll(const ['h', 'a', 'q', 's', 'e', 'N']);
        default:
          out.addAll(_digitReadings[sen.toString()]!);
          out.addAll(const ['s', 'e', 'N']);
      }
    }

    final hyaku = rem ~/ 100;
    rem %= 100;
    if (hyaku > 0) {
      switch (hyaku) {
        case 1:
          out.addAll(const ['hy', 'a', 'k', 'u']);
        case 3:
          out.addAll(const ['s', 'a', 'N', 'by', 'a', 'k', 'u']);
        case 6:
          out.addAll(const ['r', 'o', 'q', 'py', 'a', 'k', 'u']);
        case 8:
          out.addAll(const ['h', 'a', 'q', 'py', 'a', 'k', 'u']);
        default:
          out.addAll(_digitReadings[hyaku.toString()]!);
          out.addAll(const ['hy', 'a', 'k', 'u']);
      }
    }

    final ju = rem ~/ 10;
    rem %= 10;
    if (ju > 0) {
      if (ju > 1) {
        out.addAll(_digitReadings[ju.toString()]!);
      }
      out.addAll(const ['j', 'u', 'u']);
    }

    if (rem > 0) {
      out.addAll(_digitReadings[rem.toString()]!);
    }
    return out;
  }
}
