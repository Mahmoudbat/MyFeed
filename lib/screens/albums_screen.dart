
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_social_media/screens/album_detail_screen.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/album.dart';
import '../services/album_service.dart';
import '../widgets/video_thumbnail_generator.dart';

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  final AlbumService _albumService = AlbumService();
  List<Album> _albums = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    setState(() => _isLoading = true);
    final loadedAlbums = await _albumService.loadAlbums();
    setState(() {
      _albums = loadedAlbums;
      _isLoading = false;
    });
  }

  void _showCreateAlbumDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Album'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Album Name'),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text('Create'),
            onPressed: () {
              final String name = controller.text.trim();
              if (name.isNotEmpty) {
                _createAlbum(name);
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _createAlbum(String name) async {
    await _albumService.createAlbum(name);
    await _loadAlbums(); // Refresh the album list
  }

  Future<void> _deleteAlbum(String name) async {
    await _albumService.deleteAlbum(name);
    await _loadAlbums();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Album "$name" deleted.')),
      );
    }
  }

  void _showDeleteConfirmation(String albumName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Album?'),
        content: Text(
            'Are you sure you want to delete the album "$albumName"? The media inside will remain in your vault.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
            onPressed: () {
              Navigator.of(context).pop();
              _deleteAlbum(albumName);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Albums'),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAlbums,
              child: _albums.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text(
                          'No albums found. Press the + button to create one!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _albums.length,
                      itemBuilder: (context, index) {
                        final album = _albums[index];
                        return _buildAlbumTile(context, album: album);
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateAlbumDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildAlbumTile(BuildContext context, {required Album album}) {
    Widget leadingWidget;
    if (album.files.isEmpty) {
      leadingWidget = const Icon(Icons.folder_outlined, size: 56);
    } else {
      final firstFile = album.files.first;
      final isVideo = [ '.mp4', '.mov', '.avi'].any((ext) => firstFile.path.toLowerCase().endsWith(ext));
      leadingWidget = isVideo ? VideoThumbnailGenerator(videoFile: firstFile) : Image.file(firstFile, fit: BoxFit.cover);
    }

    return ListTile(
      leading: SizedBox(width: 56, height: 56, child: leadingWidget),
      title: Text(album.name),
      subtitle: Text('${album.files.length} items'),
      trailing: album.isDeletable
          ? IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _showDeleteConfirmation(album.name),
            )
          : null,
      onTap: () => _navigateToDetail(album),
    );
  }

  void _navigateToDetail(Album album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(album: album),
      ),
    ).then((_) => _loadAlbums()); // Refresh albums when returning
  }
}
