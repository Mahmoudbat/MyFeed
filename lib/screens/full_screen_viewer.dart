
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_social_media/services/album_service.dart';
import 'package:local_social_media/services/thumbnail_service.dart';
import 'package:path/path.dart' as path;
import 'package:local_social_media/widgets/video_player_widget.dart';

class FullScreenViewer extends StatefulWidget {
  final List<File> files;
  final int initialIndex;

  const FullScreenViewer(
      {super.key, required this.files, required this.initialIndex});

  @override
  State<FullScreenViewer> createState() => _FullScreenViewerState();
}

class _FullScreenViewerState extends State<FullScreenViewer> {
  final AlbumService _albumService = AlbumService();
  final ThumbnailService _thumbnailService = ThumbnailService();
  late PageController _pageController;
  late List<File> _currentFiles;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentFiles = List.from(widget.files);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  void _showDeleteConfirmation() {
    if (_currentFiles.isEmpty) return;

    final fileToDelete = _currentFiles[_currentIndex];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Media?'),
        content: const Text(
            'Are you sure you want to permanently delete this file? This action cannot be undone.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
            onPressed: () {
              Navigator.of(context).pop();
              _deleteFile(fileToDelete);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFile(File fileToDelete) async {
    // 1. Physically delete the file
    if (await fileToDelete.exists()) {
      await fileToDelete.delete();
    }

    // 2. Remove its thumbnail from the cache
    final thumbFile = await _thumbnailService.getThumbnailFile(fileToDelete);
    if (await thumbFile.exists()) {
      await thumbFile.delete();
    }

    // 3. Remove it from the album service's JSON file
    await _albumService.removeFileFromAllAlbums(fileToDelete);

    // 4. Update the UI
    setState(() {
      _currentFiles.removeWhere((f) => f.path == fileToDelete.path);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File deleted.')),
      );
    }

    // If the list is now empty, close the viewer
    if (_currentFiles.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: isLandscape,
      appBar: isLandscape
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _showDeleteConfirmation,
                ),
              ],
            ),
      body: _currentFiles.isEmpty
          ? const Center(
              child: Text('No media to display.', style: TextStyle(color: Colors.white70)),
            )
          : PageView.builder(
              scrollDirection: Axis.vertical, // Set back to vertical scrolling
              controller: _pageController,
              itemCount: _currentFiles.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final file = _currentFiles[index];
                final ext = path.extension(file.path).toLowerCase();
                final isVideo = ext == '.mp4' || ext == '.mov' || ext == '.avi';

                if (isVideo) {
                  return Center(child: VideoPlayerWidget(file: file));
                } else {
                  return Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Hero(
                        tag: 'media_hero_${file.path}_$index',
                        child: Image.file(
                          file,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[900],
                            child: const Icon(Icons.broken_image, color: Colors.white54, size: 80),
                          ),
                        ),
                      ),
                    ),
                  );
                }
              },
            ),
    );
  }
}
