import 'dart:io';

/// A call-recording audio file discovered on the device.
///
/// On most Android phones (Xiaomi/MIUI, Samsung, Oppo/Realme, Vivo) the
/// built-in dialer's "auto record calls" feature writes an audio file to a
/// vendor-specific folder once a call ends. This model wraps the file we
/// locate there so the rest of the app can treat it transport-agnostically.
///
/// Note: native phone-call recording is **Android only** — iOS exposes no API
/// for it — and depends on the user having enabled auto-recording in their
/// dialer. See [CallRecordingService] for how files are located.
class CallRecording {
  const CallRecording({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.recordedAt,
  });

  /// Absolute path to the audio file on the device.
  final String path;

  /// File name including extension (e.g. `call_rec_20260612_114830.mp3`).
  final String fileName;

  /// Size of the file in bytes.
  final int sizeBytes;

  /// Last-modified timestamp of the file — our best proxy for "when the call
  /// ended", used to match a recording to the call that just happened.
  final DateTime recordedAt;

  /// Lower-cased extension without the dot (e.g. `mp3`, `m4a`, `amr`).
  String get extension {
    final dot = fileName.lastIndexOf('.');
    return dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();
  }

  /// Human-friendly size, e.g. `1.4 MB`.
  String get readableSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// The underlying file handle, for reading/uploading.
  File get file => File(path);

  factory CallRecording.fromFile(File file) {
    final stat = file.statSync();
    final name = file.path.split(Platform.pathSeparator).last;
    return CallRecording(
      path: file.path,
      fileName: name,
      sizeBytes: stat.size,
      recordedAt: stat.modified,
    );
  }
}
