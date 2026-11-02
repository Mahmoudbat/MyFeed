import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decodes [imageBytes] at reduced size and re-encodes it as PNG, for use
/// as an (encrypted) grid thumbnail. Returns null for undecodable input.
Future<Uint8List?> makeImageThumbnail(Uint8List imageBytes, {int maxSize = 320}) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(imageBytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final landscape = descriptor.width >= descriptor.height;
    codec = await descriptor.instantiateCodec(
      targetWidth: landscape ? null : maxSize,
      targetHeight: landscape ? maxSize : null,
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}
