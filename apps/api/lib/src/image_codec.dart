import 'dart:typed_data';
import 'dart:isolate';
import 'package:image/image.dart' as img;

Future<(Uint8List, int, int)> sanitizeMarketplacePhoto(Uint8List bytes) =>
    Isolate.run(() => _sanitizeMarketplacePhoto(bytes));

(Uint8List, int, int) _sanitizeMarketplacePhoto(Uint8List bytes) {
  final png =
      bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71;
  final jpeg =
      bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255;
  if (!png && !jpeg) throw const FormatException('JPEG/PNG');
  final img.Decoder decoder = png ? img.PngDecoder() : img.JpegDecoder();
  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 20000000 ||
      info.numFrames > 1) {
    throw const FormatException('Invalid dimensions');
  }
  var photo = decoder.decodeFrame(0);
  if (photo == null) throw const FormatException('Invalid image');
  photo = img.bakeOrientation(photo);
  if (photo.width > 2048 || photo.height > 2048) {
    photo = img.copyResize(
      photo,
      width: photo.width >= photo.height ? 2048 : null,
      height: photo.height > photo.width ? 2048 : null,
    );
  }
  final clean = img.Image(
    width: photo.width,
    height: photo.height,
    numChannels: 3,
  );
  img.fill(clean, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(clean, photo);
  return (
    Uint8List.fromList(img.encodeJpg(clean, quality: 85)),
    clean.width,
    clean.height,
  );
}
