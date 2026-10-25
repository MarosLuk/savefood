import 'dart:typed_data';
import 'dart:ui';
import 'package:share_plus/share_plus.dart';

Future<void> exportCsvFile(
  String filename,
  Uint8List bytes,
  Rect origin,
) async {
  await exportDataFile(filename, bytes, origin, mimeType: 'text/csv');
}

Future<void> exportDataFile(
  String filename,
  Uint8List bytes,
  Rect origin, {
  required String mimeType,
}) async {
  await Share.shareXFiles(
    [XFile.fromData(bytes, mimeType: mimeType, name: filename)],
    fileNameOverrides: [filename],
    subject: 'Save Food · export údajov',
    sharePositionOrigin: origin,
  );
}
