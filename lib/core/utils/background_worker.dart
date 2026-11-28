import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// Handler executed inside the worker isolate. [state] persists across requests
/// so native engines (sherpa-onnx recognizers / ORT sessions / TTS) can live in the worker.
typedef WorkerHandler = Object? Function(Object? request, Map<String, Object?> state);

/// A long-lived background isolate that owns blocking native inference engines,
/// keeping the Flutter UI isolate responsive while models run.
class BackgroundWorker {
  BackgroundWorker._(
    this._handler,
    this._inlineMode, [
    this._isolate,
    this._receivePort,
  ]);

  final WorkerHandler _handler;
  final bool _inlineMode;
  final Isolate? _isolate;
  final ReceivePort? _receivePort;
  final Map<String, Object?> _inlineState = {};
  late final SendPort _sendPort;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  bool _closed = false;

  bool get isClosed => _closed;

  /// Spawns a worker running [handler] (must be a top-level or static function).
  ///
  /// Inside `testWidgets` `FakeAsync` zones (`FLUTTER_TEST` && non-root zone),
  /// runs [handler] inline so widget tests never stall on isolate ports.
  static Future<BackgroundWorker> spawn(WorkerHandler handler, {String? debugName}) async {
    final useInline =
        Platform.environment.containsKey('FLUTTER_TEST') && Zone.current != Zone.root;
    if (useInline) {
      return BackgroundWorker._(handler, true);
    }

    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerMain,
      _WorkerBoot(receivePort.sendPort, handler),
      debugName: debugName,
      errorsAreFatal: false,
    );
    final worker = BackgroundWorker._(
      handler,
      false,
      isolate,
      receivePort,
    );
    final ready = Completer<void>();
    receivePort.listen((message) {
      if (message is SendPort) {
        worker._sendPort = message;
        if (!ready.isCompleted) ready.complete();
        return;
      }
      if (message is List && message.length == 3) {
        final completer = worker._pending.remove(message[0] as int);
        if (completer == null) return;
        if (message[1] == true) {
          completer.complete(message[2]);
        } else {
          completer.completeError(StateError(message[2].toString()));
        }
      }
    });
    await ready.future;
    return worker;
  }

  /// Sends [request] to the worker and resolves with the handler's result.
  Future<Object?> request(Object? request) {
    if (_closed) {
      return Future.error(StateError('BackgroundWorker is closed'));
    }
    return _sendInternal(request);
  }

  Future<Object?> _sendInternal(Object? request) {
    if (_inlineMode) {
      try {
        return Future.value(_handler(request, _inlineState));
      } catch (e) {
        return Future.error(StateError(e.toString()));
      }
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _sendPort.send([id, request]);
    return completer.future;
  }

  /// Marks the worker closed immediately, runs an optional [finalRequest]
  /// (e.g. free native engines) sequentially after any in-flight call, then shuts down.
  Future<void> close({Object? finalRequest}) async {
    if (_closed) return;
    _closed = true;
    if (finalRequest != null) {
      try {
        await _sendInternal(finalRequest).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    if (_inlineMode) {
      _inlineState.clear();
      return;
    }
    try {
      _sendPort.send(null);
    } catch (_) {}
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('BackgroundWorker closed'));
    }
    _pending.clear();
  }
}

class _WorkerBoot {
  const _WorkerBoot(this.replyPort, this.handler);
  final SendPort replyPort;
  final WorkerHandler handler;
}

void _workerMain(_WorkerBoot boot) {
  final port = ReceivePort();
  final state = <String, Object?>{};
  boot.replyPort.send(port.sendPort);
  port.listen((message) {
    if (message == null) {
      port.close();
      return;
    }
    final list = message as List;
    final id = list[0] as int;
    try {
      final result = boot.handler(list[1], state);
      boot.replyPort.send([id, true, result]);
    } catch (e) {
      boot.replyPort.send([id, false, e.toString()]);
    }
  });
}
