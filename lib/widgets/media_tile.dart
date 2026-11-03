import 'package:flutter/material.dart';

import '../util/format.dart';

/// Grid cell with optional video badge and selection indicator; used by every
/// grid (gallery, albums, locked gallery).
class MediaTile extends StatelessWidget {
  const MediaTile({
    super.key,
    required this.image,
    this.isVideo = false,
    this.durationSeconds = 0,
    this.selectionMode = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  final Widget image;
  final bool isVideo;
  final int durationSeconds;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: const Color(0xFF1E1E1E), child: image),
          if (selected) const ColoredBox(color: Color(0x553D8BFF)),
          if (isVideo)
            Positioned(
              bottom: 4,
              right: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow, size: 14, color: Colors.white),
                      if (durationSeconds > 0) ...[
                        const SizedBox(width: 2),
                        Text(formatSeconds(durationSeconds), style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (selectionMode)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Colors.blue : Colors.white24,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: selected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Placeholder shown while a thumbnail decodes or when there is none.
class TilePlaceholder extends StatelessWidget {
  const TilePlaceholder({super.key, this.isVideo = false});
  final bool isVideo;

  @override
  Widget build(BuildContext context) => Center(
        child: Icon(isVideo ? Icons.movie_outlined : Icons.image_outlined, color: Colors.white24, size: 32),
      );
}
