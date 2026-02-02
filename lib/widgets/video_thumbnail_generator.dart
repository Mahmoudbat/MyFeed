
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:local_social_media/services/thumbnail_service.dart';

class VideoThumbnailGenerator extends StatefulWidget {
  final File videoFile;
  const VideoThumbnailGenerator({super.key, required this.videoFile});

  @override
  State<VideoThumbnailGenerator> createState() =>
      _VideoThumbnailGeneratorState();
}

class _VideoThumbnailGeneratorState extends State<VideoThumbnailGenerator> {
  final ThumbnailService _thumbnailService = ThumbnailService();
  Uint8List? _thumbnailBytes;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    // Try to load from cache first
    final cachedBytes = await _thumbnailService.getThumbnail(widget.videoFile);
    if (cachedBytes != null) {
      if (mounted) {
        setState(() => _thumbnailBytes = cachedBytes);
      }
      return;
    }

    // If not in cache, generate and save it
    await _thumbnailService.generateAndSaveThumbnail(widget.videoFile);
    final newBytes = await _thumbnailService.getThumbnail(widget.videoFile);
    if (newBytes != null && mounted) {
      setState(() => _thumbnailBytes = newBytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbnailBytes == null) {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child:
              CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white54),
        ),
      );
    }
    return Image.memory(
      _thumbnailBytes!,
      fit: BoxFit.cover,
      gaplessPlayback: true, // Prevents flickering when the image loads
    );
  }
}
