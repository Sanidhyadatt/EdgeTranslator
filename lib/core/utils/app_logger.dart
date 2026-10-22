import 'package:flutter/foundation.dart';

/// Lightweight structured logger for edge AI inference & audio pipeline profiling.
class AppLogger {
  AppLogger._();

  static void info(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[INFO][$tag] $message');
    }
  }

  static void warning(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[WARN][$tag] $message');
    }
  }

  static void error(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[ERROR][$tag] $message');
      if (error != null) debugPrint('Error: $error');
      if (stackTrace != null) debugPrint('StackTrace: $stackTrace');
    }
  }

  static void profile(String stage, int durationMs) {
    if (kDebugMode) {
      debugPrint('[PROFILE][$stage] Completed in ${durationMs}ms');
    }
  }
}
