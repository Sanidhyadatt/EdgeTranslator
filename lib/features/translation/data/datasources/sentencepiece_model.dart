import 'dart:typed_data';

/// Minimal, dependency-free SentencePiece **unigram** model.
///
/// Parses the `ModelProto` protobuf stored in `.spm` files (as shipped with
/// MarianMT / opus-mt models) and segments text with a Viterbi search over the
/// piece scores, exactly like the reference SentencePiece implementation.
class SentencePieceModel {
  static const String spaceMarker = '\u2581';

  final Map<String, double> _scores;
  final int _maxPieceLength;
  final double _unkScore;

  SentencePieceModel._(this._scores, this._maxPieceLength, this._unkScore);

  int get vocabSize => _scores.length;

  /// Parses a `.spm` file's raw bytes.
  factory SentencePieceModel.parse(Uint8List bytes) {
    final scores = <String, double>{};
    var maxLen = 1;
    var minScore = 0.0;

    final reader = _ProtoReader(bytes);
    while (!reader.isDone) {
      final tag = reader.readVarint();
      final field = tag >> 3;
      final wire = tag & 7;
      if (field == 1 && wire == 2) {
        final sub = _ProtoReader(reader.readLengthDelimited());
        String? piece;
        double score = 0;
        int type = 1; // NORMAL (proto2 default)
        while (!sub.isDone) {
          final t = sub.readVarint();
          final f = t >> 3;
          final w = t & 7;
          if (f == 1 && w == 2) {
            piece = String.fromCharCodes(
              _decodeUtf8(sub.readLengthDelimited()),
            );
          } else if (f == 2 && w == 5) {
            score = sub.readFloat32();
          } else if (f == 3 && w == 0) {
            type = sub.readVarint();
          } else {
            sub.skip(w);
          }
        }
        // 1 = NORMAL, 4 = USER_DEFINED. Skip UNKNOWN/CONTROL/UNUSED/BYTE.
        if (piece != null && (type == 1 || type == 4)) {
          scores[piece] = score;
          final len = piece.runes.length;
          if (len > maxLen) maxLen = len;
          if (score < minScore) minScore = score;
        }
      } else {
        reader.skip(wire);
      }
    }

    return SentencePieceModel._(scores, maxLen, minScore - 10.0);
  }

  /// NFKC-style normalisation matching SentencePiece `nmt_nfkc`:
  /// folds full-width ASCII (`！`-`～`) to half-width, normalizes curly quotes
  /// and dashes, converts ideographic/non-breaking spaces, and collapses runs.
  static String normalize(String text) {
    final sb = StringBuffer();
    for (final rune in text.runes) {
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        sb.writeCharCode(rune - 0xFEE0);
      } else if (rune == 0x3000 || rune == 0x00A0) {
        sb.write(' ');
      } else if (rune == 0x2018 || rune == 0x2019) {
        sb.write("'");
      } else if (rune == 0x201C || rune == 0x201D) {
        sb.write('"');
      } else if (rune == 0x2013 || rune == 0x2014) {
        sb.write('-');
      } else {
        sb.writeCharCode(rune);
      }
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Candidate substitutes for a character the model does not contain
  /// (width folding in both directions plus CJK punctuation equivalents).
  static List<String> _alternatives(String ch) {
    final rune = ch.runes.first;
    final out = <String>[];
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      out.add(String.fromCharCode(rune - 0xFEE0));
    } else if (rune >= 0x21 && rune <= 0x7E) {
      out.add(String.fromCharCode(rune + 0xFEE0));
    }
    const extra = {
      '.': '\u3002',
      ',': '\u3001',
      '\u3002': '.',
      '\u3001': ',',
      "'": '\u2019',
      '"': '\u201D',
    };
    final mapped = extra[ch];
    if (mapped != null) out.add(mapped);
    return out;
  }

  /// Splits [text] into SentencePiece pieces (with the leading `▁` markers).
  /// When [allowedPieces] is provided (e.g. `vocab.json` keys), pieces outside
  /// that vocabulary are ignored during Viterbi search so valid subwords are
  /// chosen instead of emitting `<unk>`.
  List<String> encode(String text, {Set<String>? allowedPieces}) {
    final normalized = normalize(text);
    if (normalized.isEmpty) return const [];

    bool isUsable(String piece) {
      return _scores.containsKey(piece) &&
          (allowedPieces == null || allowedPieces.contains(piece));
    }

    final prepared = '$spaceMarker${normalized.replaceAll(' ', spaceMarker)}';
    final chars = prepared.runes.map(String.fromCharCode).toList();
    for (var i = 0; i < chars.length; i++) {
      final ch = chars[i];
      if (isUsable(ch)) continue;
      for (final alt in _alternatives(ch)) {
        if (isUsable(alt)) {
          chars[i] = alt;
          break;
        }
      }
    }
    final n = chars.length;

    final best = List<double>.filled(n + 1, double.negativeInfinity);
    final backLen = List<int>.filled(n + 1, 0);
    final backUnk = List<bool>.filled(n + 1, false);
    best[0] = 0;

    for (var i = 0; i < n; i++) {
      if (best[i] == double.negativeInfinity) continue;
      final sb = StringBuffer();
      var singleCharKnown = false;
      final maxLen = (n - i) < _maxPieceLength ? (n - i) : _maxPieceLength;
      for (var len = 1; len <= maxLen; len++) {
        sb.write(chars[i + len - 1]);
        final candidatePiece = sb.toString();
        final score = _scores[candidatePiece];
        if (score == null) continue;
        if (allowedPieces != null && !allowedPieces.contains(candidatePiece)) {
          continue;
        }
        if (len == 1) singleCharKnown = true;
        final candidate = best[i] + score;
        if (candidate > best[i + len]) {
          best[i + len] = candidate;
          backLen[i + len] = len;
          backUnk[i + len] = false;
        }
      }
      if (!singleCharKnown) {
        final candidate = best[i] + _unkScore;
        if (candidate > best[i + 1]) {
          best[i + 1] = candidate;
          backLen[i + 1] = 1;
          backUnk[i + 1] = true;
        }
      }
    }

    final pieces = <String>[];
    var pos = n;
    while (pos > 0) {
      final len = backLen[pos];
      if (len == 0) break;
      pieces.add(backUnk[pos] ? '<unk>' : chars.sublist(pos - len, pos).join());
      pos -= len;
    }
    return pieces.reversed.toList();
  }
}

List<int> _decodeUtf8(Uint8List bytes) {
  final out = <int>[];
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    int cp;
    int extra;
    if (b < 0x80) {
      cp = b;
      extra = 0;
    } else if (b >> 5 == 0x6) {
      cp = b & 0x1F;
      extra = 1;
    } else if (b >> 4 == 0xE) {
      cp = b & 0x0F;
      extra = 2;
    } else {
      cp = b & 0x07;
      extra = 3;
    }
    for (var k = 1; k <= extra && i + k < bytes.length; k++) {
      cp = (cp << 6) | (bytes[i + k] & 0x3F);
    }
    i += extra + 1;
    if (cp > 0xFFFF) {
      cp -= 0x10000;
      out.add(0xD800 + (cp >> 10));
      out.add(0xDC00 + (cp & 0x3FF));
    } else {
      out.add(cp);
    }
  }
  return out;
}

class _ProtoReader {
  final Uint8List _bytes;
  int _pos = 0;

  _ProtoReader(this._bytes);

  bool get isDone => _pos >= _bytes.length;

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (_pos < _bytes.length) {
      final b = _bytes[_pos++];
      result |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
    }
    return result;
  }

  Uint8List readLengthDelimited() {
    final len = readVarint();
    final out = Uint8List.sublistView(_bytes, _pos, _pos + len);
    _pos += len;
    return out;
  }

  double readFloat32() {
    final value = ByteData.sublistView(_bytes, _pos, _pos + 4)
        .getFloat32(0, Endian.little);
    _pos += 4;
    return value;
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
        break;
      case 1:
        _pos += 8;
        break;
      case 2:
        final len = readVarint();
        _pos += len;
        break;
      case 5:
        _pos += 4;
        break;
      default:
        _pos = _bytes.length;
    }
  }
}
