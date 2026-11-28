// ignore_for_file: implementation_imports
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart' as bg;

import 'device_profile.dart';

/// Session options tuned for mobile CPUs: fast-core thread pool, single inter-op
/// thread and full graph optimizations (operator fusion, constant folding).
OrtSessionOptions createTunedSessionOptions({int? threads}) {
  final options = OrtSessionOptions();
  options.setIntraOpNumThreads(threads ?? DeviceProfile.inferenceThreads);
  options.setInterOpNumThreads(1);
  options.setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
  return options;
}

/// Creates an [OrtSession] synchronously in the current isolate.
OrtSession createOrtSessionSync(String path, {int? threads}) {
  try {
    OrtEnv.instance.init();
  } catch (_) {
    // Already initialized (ORT keeps one process-wide environment).
  }
  final options = createTunedSessionOptions(threads: threads);
  try {
    if (Platform.isWindows) {
      // OrtSession.fromBuffer avoids path encoding issues on Windows.
      return OrtSession.fromBuffer(File(path).readAsBytesSync(), options);
    }
    try {
      return OrtSession.fromFile(File(path), options);
    } catch (_) {
      return OrtSession.fromBuffer(File(path).readAsBytesSync(), options);
    }
  } finally {
    options.release();
  }
}

/// Zero-copy float32 view over an ORT output tensor.
///
/// `OrtValueTensor.value` boxes every element into nested Dart lists, which is
/// catastrophically slow for `[1, seq, vocab]` logits and 44.1 kHz audio buffers.
/// This view reads the native buffer directly (valid until [value] is released),
/// falling back to flattening `value.value` only if the tensor is not float32.
Float32List ortFloatTensorView(OrtValue value) {
  final api = OrtEnv.instance.ortApiPtr.ref;
  final infoPtrPtr = calloc<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>();
  final elemTypePtr = calloc<ffi.Int32>();
  final countPtr = calloc<ffi.Size>();
  try {
    var status = api.GetTensorTypeAndShape.asFunction<
        bg.OrtStatusPtr Function(
          ffi.Pointer<bg.OrtValue>,
          ffi.Pointer<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>,
        )>()(value.ptr, infoPtrPtr);
    OrtStatus.checkOrtStatus(status);
    final infoPtr = infoPtrPtr.value;
    int elemType;
    int count;
    try {
      status = api.GetTensorElementType.asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>,
            ffi.Pointer<ffi.Int32>,
          )>()(infoPtr, elemTypePtr);
      OrtStatus.checkOrtStatus(status);
      elemType = elemTypePtr.value;

      status = api.GetTensorShapeElementCount.asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>,
            ffi.Pointer<ffi.Size>,
          )>()(infoPtr, countPtr);
      OrtStatus.checkOrtStatus(status);
      count = countPtr.value;
    } finally {
      api.ReleaseTensorTypeAndShapeInfo.asFunction<
          void Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>)>()(infoPtr);
    }

    if (elemType == ONNXTensorElementDataType.float.value) {
      final dataPtrPtr = calloc<ffi.Pointer<ffi.Void>>();
      try {
        status = api.GetTensorMutableData.asFunction<
            bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtValue>,
              ffi.Pointer<ffi.Pointer<ffi.Void>>,
            )>()(value.ptr, dataPtrPtr);
        OrtStatus.checkOrtStatus(status);
        return dataPtrPtr.value.cast<ffi.Float>().asTypedList(count);
      } finally {
        calloc.free(dataPtrPtr);
      }
    }
  } finally {
    calloc.free(infoPtrPtr);
    calloc.free(elemTypePtr);
    calloc.free(countPtr);
  }

  // Fallback for non-float32 tensors
  final out = <double>[];
  void collect(Object? node) {
    if (node is num) {
      out.add(node.toDouble());
    } else if (node is List) {
      for (final item in node) {
        collect(item);
      }
    }
  }

  collect(value.value);
  return Float32List.fromList(out);
}

/// Allocates an INT64 [OrtValueTensor] directly from [data] without `ListShape.flatten()`.
OrtValueTensor createInt64OrtTensor(Int64List data, List<int> shape) {
  final n = data.length;
  final dataPtr = calloc<ffi.Int64>(n == 0 ? 1 : n);
  if (n > 0) {
    dataPtr.asTypedList(n).setRange(0, n, data);
  }
  return _createTensorWithNativeData(
    dataPtr.cast<ffi.Void>(),
    n * ffi.sizeOf<ffi.Int64>(),
    shape,
    ONNXTensorElementDataType.int64.value,
  );
}

/// Allocates a FLOAT32 [OrtValueTensor] directly from [data] without `ListShape.flatten()`.
OrtValueTensor createFloat32OrtTensor(Float32List data, List<int> shape) {
  final n = data.length;
  final dataPtr = calloc<ffi.Float>(n == 0 ? 1 : n);
  if (n > 0) {
    dataPtr.asTypedList(n).setRange(0, n, data);
  }
  return _createTensorWithNativeData(
    dataPtr.cast<ffi.Void>(),
    n * ffi.sizeOf<ffi.Float>(),
    shape,
    ONNXTensorElementDataType.float.value,
  );
}

OrtValueTensor _createTensorWithNativeData(
  ffi.Pointer<ffi.Void> dataPtr,
  int dataByteCount,
  List<int> shape,
  int elementType,
) {
  final api = OrtEnv.instance.ortApiPtr.ref;
  final shapeSize = shape.length;
  final shapePtr = calloc<ffi.Int64>(shapeSize == 0 ? 1 : shapeSize);
  if (shapeSize > 0) {
    shapePtr.asTypedList(shapeSize).setRange(0, shapeSize, shape);
  }
  final ortMemoryInfoPtrPtr = calloc<ffi.Pointer<bg.OrtMemoryInfo>>();
  final ortValuePtrPtr = calloc<ffi.Pointer<bg.OrtValue>>();
  try {
    var status = api.AllocatorGetInfo.asFunction<
        bg.OrtStatusPtr Function(
          ffi.Pointer<bg.OrtAllocator>,
          ffi.Pointer<ffi.Pointer<bg.OrtMemoryInfo>>,
        )>()(OrtAllocator.instance.ptr, ortMemoryInfoPtrPtr);
    OrtStatus.checkOrtStatus(status);

    status = api.CreateTensorWithDataAsOrtValue.asFunction<
        bg.OrtStatusPtr Function(
          ffi.Pointer<bg.OrtMemoryInfo>,
          ffi.Pointer<ffi.Void>,
          int,
          ffi.Pointer<ffi.Int64>,
          int,
          int,
          ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
        )>()(
      ortMemoryInfoPtrPtr.value,
      dataPtr,
      dataByteCount,
      shapePtr,
      shapeSize,
      elementType,
      ortValuePtrPtr,
    );
    OrtStatus.checkOrtStatus(status);
    return OrtValueTensor(ortValuePtrPtr.value, dataPtr);
  } catch (_) {
    calloc.free(dataPtr);
    rethrow;
  } finally {
    calloc.free(shapePtr);
    calloc.free(ortMemoryInfoPtrPtr);
    calloc.free(ortValuePtrPtr);
  }
}

/// Releases every non-null ORT value in [values].
void releaseOrtValues(Iterable<OrtValue?>? values) {
  if (values == null) return;
  for (final v in values) {
    try {
      v?.release();
    } catch (_) {}
  }
}
