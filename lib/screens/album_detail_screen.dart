
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_social_media/models/album.dart';
import 'package:local_social_media/screens/full_screen_viewer.dart';
import 'package:local_social_media/services/thumbnail_service.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../services/album_service.dart';
import '../widgets/media_grid_item.dart';

class AlbumDetailScreen extends StatefulWidget {
  final Album album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final AlbumService _albumService = AlbumService();
  final ThumbnailService _thumbnailService = ThumbnailService();
  late List<File> _files;
  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _files = List.from(widget.album.files);
    _files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  void _enterSelectionMode(String filePath) {
    setState(() {
      _selectionMode = true;
      _selectedPaths.add(filePath);
    });
  }

  void _toggleSelect(String filePath) {
    setState(() {
      if (_selectedPaths.contains(filePath)) {
        _selectedPaths.remove(filePath);
      } else {
        _selectedPaths.add(filePath);
      }
    });
  }

  void _selectAll() {
    setState(() {
      for (final f in _files) {
        _selectedPaths.add(f.path);
      }
    });
  }

  List<File> get _selectedFiles =>
      _files.where((f) => _selectedPaths.contains(f.path)).toList();

  Future<void> _deleteSelected() async {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected?'),
        content: Text(
            'Permanently delete ${files.length} item${files.length == 1 ? '' : 's'} from device? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    for (final file in files) {
      if (await file.exists()) await file.delete();
      final thumb = await _thumbnailService.getThumbnailFile(file);
      if (await thumb.exists()) await thumb.delete();
      await _albumService.removeFileFromAllAlbums(file);
    }
    setState(() {
      _files.removeWhere((f) => _selectedPaths.contains(f.path));
      _selectionMode = false;
      _selectedPaths.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted ${files.length} item(s).')));
    }
  }

  Future<void> _moveToAlbum() async {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    final albums = await _albumService.loadAlbums();
    final customAlbums = albums.where((a) => a.isDeletable && a.name != widget.album.name).toList();
    if (customAlbums.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No other custom album. Create one in Albums tab.')),
        );
      }
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<Album>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to album'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: customAlbums
                .map((a) => ListTile(
                      title: Text(a.name),
                      subtitle: Text('${a.files.length} items'),
                      onTap: () => Navigator.pop(ctx, a),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    await _albumService.addFilesToAlbum(chosen.name, files);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${files.length} item(s) to ${chosen.name}'), backgroundColor: Colors.green),
      );
      setState(() {
        _selectionMode = false;
        _selectedPaths.clear();
      });
    }
  }

  Future<void> _removeFromAlbum() async {
    if (!widget.album.isDeletable) return;
    final files = _selectedFiles;
    if (files.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from album?'),
        content: Text(
            'Remove ${files.length} item${files.length == 1 ? '' : 's'} from "${widget.album.name}"? Files stay in your vault.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _albumService.removeFilesFromAlbum(widget.album.name, files);
    setState(() {
      _files.removeWhere((f) => _selectedPaths.contains(f.path));
      _selectionMode = false;
      _selectedPaths.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed ${files.length} item(s) from album.')),
      );
    }
  }

  Future<void> _pickAndAddMedia() async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(
        maxAssets: 100,
        requestType: RequestType.common,
      ),
    );

    if (assets == null) return;

    final Directory appDir = await getApplicationDocumentsDirectory();
    final List<File> newFiles = [];

    for (final AssetEntity asset in assets) {
      final File? file = await asset.file;
      if (file != null) {
        final String fileName = path.basename(file.path);
        final String savePath = path.join(appDir.path, fileName);
        final newFile = await file.copy(savePath);
        newFiles.add(newFile);
      }
    }

    if (widget.album.isDeletable) {
      await _albumService.addFilesToAlbum(widget.album.name, newFiles);
    }

    setState(() {
      _files.addAll(newFiles);
      _files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              backgroundColor: Colors.black,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              ),
              title: Text('${_selectedPaths.length} selected'),
              actions: [
                IconButton(icon: const Icon(Icons.select_all), onPressed: _selectAll, tooltip: 'Select all'),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'delete') _deleteSelected();
                    if (value == 'move') _moveToAlbum();
                    if (value == 'remove') _removeFromAlbum();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'move', child: Row(children: [Icon(Icons.drive_file_move), SizedBox(width: 8), Text('Move to album')])),
                    if (widget.album.isDeletable)
                      const PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.remove_circle_outline), SizedBox(width: 8), Text('Remove from album')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                  ],
                ),
              ],
            )
          : AppBar(
              title: Text(widget.album.name),
              centerTitle: true,
              backgroundColor: Colors.black,
              actions: [
                if (widget.album.isDeletable)
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    onPressed: _pickAndAddMedia,
                  ),
              ],
            ),
      backgroundColor: Colors.black,
      body: _files.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'This album is empty.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  if (widget.album.isDeletable)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text('Add Media'),
                      onPressed: _pickAndAddMedia,
                    )
                ],
              ),
            )
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: _files.length,
              itemBuilder: (context, index) {
                final file = _files[index];
                final pathStr = file.path;
                return MediaGridItem(
                  file: file,
                  index: index,
                  isSelectionMode: _selectionMode,
                  isSelected: _selectedPaths.contains(pathStr),
                  onLongPress: () => _enterSelectionMode(pathStr),
                  onToggleSelect: () => _toggleSelect(pathStr),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FullScreenViewer(
                          files: _files,
                          initialIndex: index,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
