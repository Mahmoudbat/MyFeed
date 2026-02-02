import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../services/encryption_service.dart';
import '../models/album.dart';
import '../services/album_service.dart';

class LockedAlbumsScreen extends StatefulWidget {
  const LockedAlbumsScreen({super.key});

  @override
  State<LockedAlbumsScreen> createState() => _LockedAlbumsScreenState();
}

class _LockedAlbumsScreenState extends State<LockedAlbumsScreen> {
  final EncryptionService _encryptionService = EncryptionService();
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
    await _encryptionService.initialize();
    
    final albums = await _albumService.loadAlbums();
    
    // Filter out the virtual "All Media", "Images", and "Videos" albums for locked view
    // These are created from app directory files, not encrypted files
    final filteredAlbums = albums.where((album) => 
      album.name != 'All Media' && 
      album.name != 'Images' && 
      album.name != 'Videos'
    ).toList();
    
    setState(() {
      _albums = filteredAlbums;
      _isLoading = false;
    });
  }

  void _showCreateAlbumDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('New Locked Album', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Album Name',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white54),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text('Create'),
            onPressed: () async {
              final String name = controller.text.trim();
              if (name.isNotEmpty) {
                await _albumService.createAlbum(name);
                Navigator.of(context).pop();
                await _loadAlbums();
              }
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
        title: const Text('Locked Albums'),
        centerTitle: true,
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateAlbumDialog,
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _albums.isEmpty
              ? Center(
                  child: Text(
                    'No locked albums.\nTap + to create one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _albums.length,
                  itemBuilder: (context, index) {
                    final album = _albums[index];
                    return _LockedAlbumCard(
                      album: album,
                      encryptionService: _encryptionService,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _LockedAlbumDetailScreen(
                              album: album,
                              encryptionService: _encryptionService,
                            ),
                          ),
                        ).then((_) => _loadAlbums());
                      },
                    );
                  },
                ),
    );
  }
}

class _LockedAlbumCard extends StatelessWidget {
  final Album album;
  final EncryptionService encryptionService;
  final VoidCallback onTap;

  const _LockedAlbumCard({
    required this.album,
    required this.encryptionService,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final coverFile = album.files.isNotEmpty ? album.files.first : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                child: coverFile == null
                    ? Container(
                        color: Colors.grey[800],
                        child: const Center(
                          child: Icon(Icons.photo_album, size: 48, color: Colors.white38),
                        ),
                      )
                    : FutureBuilder<Uint8List>(
                        future: encryptionService.decryptFile(coverFile),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                            );
                          }
                          return Container(
                            color: Colors.grey[800],
                            child: const Center(child: CircularProgressIndicator()),
                          );
                        },
                      ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${album.files.length} items',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedAlbumDetailScreen extends StatelessWidget {
  final Album album;
  final EncryptionService encryptionService;

  const _LockedAlbumDetailScreen({
    required this.album,
    required this.encryptionService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(album.name),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: album.files.isEmpty
          ? Center(
              child: Text(
                'This album is empty',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
            )
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: album.files.length,
              itemBuilder: (context, index) {
                final file = album.files[index];
                
                return GestureDetector(
                  onTap: () {
                    // Could add fullscreen viewer here
                  },
                  child: FutureBuilder<Uint8List>(
                    future: encryptionService.decryptFile(file),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                        );
                      }
                      return Container(
                        color: Colors.grey[900],
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
