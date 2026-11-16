/// Converts Japanese text into MeloTTS phoneme token IDs using longest-match
/// over `lexicon.txt` combined with a complete Hiragana/Katakana phoneme fallback.
class JapaneseMeloG2p {
  final Map<String, int> tokenToId;
  final Map<String, List<String>> lexicon;
  final int maxWordLength;
  final int blankId;

  JapaneseMeloG2p._({
    required this.tokenToId,
    required this.lexicon,
    required this.maxWordLength,
    required this.blankId,
  });

  factory JapaneseMeloG2p.fromFiles({
    required List<String> tokenLines,
    required List<String> lexiconLines,
  }) {
    final tokenToId = <String, int>{};
    for (final line in tokenLines) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
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
    var maxLen = 1;
    for (final line in lexiconLines) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 3) continue;
      final word = parts[0];
      final rest = parts.sublist(1);
      final phoneCount = rest.length ~/ 2;
      if (phoneCount <= 0) continue;
      lexicon[word] = rest.sublist(0, phoneCount);
      if (word.length > maxLen) {
        maxLen = word.length;
      }
    }

    return JapaneseMeloG2p._(
      tokenToId: tokenToId,
      lexicon: lexicon,
      maxWordLength: maxLen,
      blankId: tokenToId['_'] ?? 0,
    );
  }

  /// Splits [text] into sentences on punctuation and converts each to blank-interleaved
  /// MeloTTS token IDs (`[blank, tok1, blank, tok2, ..., blank]`).
  List<List<int>> encodeSentences(String text) {
    final normalized = _normalizePunctuation(text.trim());
    if (normalized.isEmpty) return const [];

    final rawSentences = normalized
        .split(RegExp(r'(?<=[.,!?])\s*'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

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
      // 1. Check punctuation directly
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

      // 2. Try longest lexicon match (covers Kanji & common phrases/particles)
      String? matchedWord;
      final maxEnd = (i + maxWordLength) < len ? (i + maxWordLength) : len;
      for (var end = maxEnd; end > i; end--) {
        final candidate = sentence.substring(i, end);
        // Single kana 'ん'/'っ' are handled by the kana table for accurate 'N'/'q'.
        if (candidate.length == 1 &&
            (candidate == 'ん' || candidate == 'ン' || candidate == 'っ' || candidate == 'ッ')) {
          continue;
        }
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

      // 3. Try 2-char kana digraph fallback (after normalizing Katakana -> Hiragana)
      if (i + 1 < len) {
        final pair = _toHiragana(sentence.substring(i, i + 2));
        final pairPhones = _kanaDigraphs[pair];
        if (pairPhones != null) {
          phones.addAll(pairPhones);
          i += 2;
          continue;
        }
      }

      // 4. Try single kana fallback (Hiragana/Katakana)
      final hira = _toHiragana(ch);
      if (hira == 'ー') {
        // Prolonged vowel mark is absorbed in MeloTTS lexicon convention
        i++;
        continue;
      }
      final singlePhones = _kanaSingle[hira];
      if (singlePhones != null) {
        phones.addAll(singlePhones);
        i++;
        continue;
      }

      // 5. Fallback for ASCII digits/letters if embedded
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
      // Katakana U+30A1..U+30F6 -> Hiragana U+3041..U+3096
      if (rune >= 0x30A1 && rune <= 0x30F6) {
        sb.writeCharCode(rune - 0x60);
      } else {
        sb.writeCharCode(rune);
      }
    }
    return sb.toString();
  }

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
    '9': ['ky', 'u'],
  };
}
