import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui';
import 'package:web/web.dart' as web;

Future<void> exportCsvFile(
  String filename,
  Uint8List bytes,
  Rect origin,
) async {
  await exportDataFile(
    filename,
    bytes,
    origin,
    mimeType: 'text/csv;charset=utf-8',
  );
}

Future<void> exportDataFile(
  String filename,
  Uint8List bytes,
  Rect origin, {
  required String mimeType,
}) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  try {
    web.document.body?.append(anchor);
    anchor.click();
    // Allow the browser to retain the blob before releasing the temporary URL.
    await Future<void>.delayed(const Duration(seconds: 1));
  } finally {
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }
}
