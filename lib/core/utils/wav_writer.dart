import 'dart:io';
import 'dart:typed_data';

/// Encodes mono Float32 PCM samples as a 16-bit PCM WAV file (synchronous, so it
/// can run inside background isolates without touching the UI thread).
void writePcm16WavSync(Float32List samples, int sampleRate, String path) {
  final dataBytes = samples.length * 2;
  final bytes = ByteData(44 + dataBytes);

  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // PCM subchunk size
  bytes.setUint16(20, 1, Endian.little); // PCM format
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  bytes.setUint16(32, 2, Endian.little); // block align
  bytes.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);

  var offset = 44;
  for (var i = 0; i < samples.length; i++) {
    var s = samples[i];
    if (s > 1.0) {
      s = 1.0;
    } else if (s < -1.0) {
      s = -1.0;
    }
    bytes.setInt16(offset, (s < 0 ? s * 32768 : s * 32767).toInt(), Endian.little);
    offset += 2;
  }

  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes.buffer.asUint8List(), flush: true);
}
