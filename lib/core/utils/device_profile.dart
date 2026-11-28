import 'dart:io';
import 'dart:math' as math;

/// Lightweight hardware profile used to tune on-device inference for low-end phones.
///
/// Reads `/proc/meminfo` and per-core `cpufreq` limits on Android/Linux so the
/// ONNX Runtime / sherpa-onnx thread pools only use the fast (big/prime) cores.
/// Spreading a single inference across slow LITTLE cores makes the fast cores
/// wait on stragglers and contends with the UI/audio threads.
class DeviceProfile {
  DeviceProfile._();

  /// Logical CPU count.
  static final int cores = _safeCores();

  /// Number of cores in the fastest cluster(s) (>= 75% of the top max frequency).
  static final int fastCores = _detectFastCores();

  /// Total device RAM in MB, or 0 when unknown.
  static final int totalRamMb = _readTotalRamMb();

  /// True for phones with <= 4 cores or < 4 GB RAM.
  static bool get isLowEnd => cores <= 4 || (totalRamMb > 0 && totalRamMb < 4096);

  /// Recommended intra-op thread count for heavy neural inference (1..4).
  static int get inferenceThreads {
    if (cores <= 2) return 1;
    final candidate = fastCores > 0 ? fastCores : cores ~/ 2;
    return candidate.clamp(cores >= 4 ? 2 : 1, 4);
  }

  static int _safeCores() {
    try {
      return math.max(1, Platform.numberOfProcessors);
    } catch (_) {
      return 2;
    }
  }

  static int _detectFastCores() {
    if (!(Platform.isAndroid || Platform.isLinux)) return 0;
    try {
      final freqs = <int>[];
      for (var i = 0; i < cores; i++) {
        final f = File('/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq');
        if (!f.existsSync()) continue;
        final v = int.tryParse(f.readAsStringSync().trim());
        if (v != null && v > 0) freqs.add(v);
      }
      if (freqs.isEmpty) return 0;
      final top = freqs.reduce(math.max);
      return freqs.where((f) => f >= top * 0.75).length;
    } catch (_) {
      return 0;
    }
  }

  static int _readTotalRamMb() {
    if (!(Platform.isAndroid || Platform.isLinux)) return 0;
    try {
      final f = File('/proc/meminfo');
      if (!f.existsSync()) return 0;
      for (final line in f.readAsLinesSync()) {
        if (line.startsWith('MemTotal:')) {
          final kb = int.tryParse(line.replaceAll(RegExp(r'[^0-9]'), ''));
          return kb == null ? 0 : kb ~/ 1024;
        }
      }
    } catch (_) {}
    return 0;
  }

  static String describe() =>
      'cores=$cores fastCores=$fastCores ramMb=$totalRamMb lowEnd=$isLowEnd threads=$inferenceThreads';
}
