
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'video_thumbnail_generator.dart';

class MediaGridItem extends StatelessWidget {
  final File file;
  final int index;
  final VoidCallback onTap;
  /// When true, tap toggles selection; long-press still toggles.
  final bool isSelectionMode;
  final bool isSelected;
  /// Called when user long-presses (enter selection mode and select this item).
  final VoidCallback? onLongPress;
  /// Called when user taps in selection mode to toggle this item.
  final VoidCallback? onToggleSelect;

  const MediaGridItem({
    super.key,
    required this.file,
    required this.index,
    required this.onTap,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onToggleSelect,
  });

  bool get isVideo {
    final String extension = path.extension(file.path).toLowerCase();
    return extension == '.mp4' ||
        extension == '.mov' ||
        extension == '.avi' ||
        extension == '.mkv';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (isSelectionMode && onToggleSelect != null) {
          onToggleSelect!();
        } else {
          onTap();
        }
      },
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          if (isVideo)
            VideoThumbnailGenerator(videoFile: file)
          else
            Hero(
              tag: 'media_hero_${file.path}_$index',
              child: Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey[900],
                  child: const Icon(Icons.broken_image, color: Colors.white54, size: 40),
                ),
              ),
            ),
          if (isVideo)
            const Icon(
              Icons.play_circle_outline,
              color: Colors.white70,
              size: 40,
            ),
          if (isSelectionMode)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Theme.of(context).primaryColor : Colors.black54,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isSelected ? Icons.check : Icons.circle_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
