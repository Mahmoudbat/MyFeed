import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'vault_store.dart';

/// [ImageProvider] that decrypts a vault image (or its thumbnail) on demand.
///
/// Going through Flutter's [ImageCache] bounds memory use and avoids
/// re-decrypting on every rebuild; the cache is cleared when the vault locks.
@immutable
class LockedImage extends ImageProvider<LockedImage> {
  const LockedImage(this.store, this.itemId, {this.thumbnail = false});

  final VaultStore store;
  final String itemId;
  final bool thumbnail;

  @override
  Future<LockedImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(LockedImage key, ImageDecoderCallback decode) {
    // Multi-frame so animated GIF/WebP keep animating.
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(key, decode),
      scale: 1.0,
      debugLabel: 'LockedImage($itemId, thumbnail: $thumbnail)',
    );
  }

  Future<ui.Codec> _loadCodec(LockedImage key, ImageDecoderCallback decode) async {
    final bytes = key.thumbnail ? await store.readThumbnail(itemId) : await store.readAll(itemId);
    if (bytes == null) throw StateError('no thumbnail for $itemId');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is LockedImage && other.itemId == itemId && other.thumbnail == thumbnail && identical(other.store, store);

  @override
  int get hashCode => Object.hash(itemId, thumbnail, store);
}
